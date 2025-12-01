package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"

	texttospeech "cloud.google.com/go/texttospeech/apiv1"
	"cloud.google.com/go/texttospeech/apiv1/texttospeechpb"
	"github.com/gorilla/websocket"
	"google.golang.org/genai"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

type StoryRequest struct {
	Topic    string `json:"topic"`
	Voice    string `json:"voice"`
	TTSModel string `json:"tts_model"`
	Context  string `json:"context"`
}

type StoryResponse struct {
	Type    string      `json:"type"` // "title", "sentence", "image", "suggestions", "context"
	Content string      `json:"content,omitempty"`
	Data    interface{} `json:"data,omitempty"`
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	http.HandleFunc("/ws", handleWebSocket)
	
	fs := http.FileServer(http.Dir("../frontend/build/web"))
	http.Handle("/", fs)

	log.Printf("Echo Storyteller Server listening on port %s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}

func handleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("Upgrade error:", err)
		return
	}
	defer conn.Close()

	ctx := context.Background()
	
	ttsClient, err := texttospeech.NewClient(ctx)
	if err != nil {
		log.Printf("TTS init error: %v", err)
		return
	}
	defer ttsClient.Close()

	projectID := os.Getenv("GOOGLE_CLOUD_PROJECT")
	location := os.Getenv("GOOGLE_CLOUD_LOCATION")
	var genaiClient *genai.Client

	if projectID != "" && location != "" {
		genaiClient, err = genai.NewClient(ctx, &genai.ClientConfig{
			Project:  projectID,
			Location: location,
			Backend:  genai.BackendVertexAI,
		})
		if err != nil {
			log.Printf("Vertex AI init error: %v", err)
		}
	} else {
		log.Println("Warning: GOOGLE_CLOUD_PROJECT or GOOGLE_CLOUD_LOCATION not set. Story generation disabled.")
	}

	for {
		_, message, err := conn.ReadMessage()
		if err != nil {
			log.Printf("WS Read Error: %v", err)
			break
		}
		
		// Parse Payload (JSON or Raw String)
		var topic string
		var voice string = "Puck"
		var ttsModel string = "gemini-2.5-flash-tts"
		var storyContext string

		var req StoryRequest
		if err := json.Unmarshal(message, &req); err == nil && req.Topic != "" {
			topic = req.Topic
			if req.Voice != "" {
				voice = req.Voice
			}
			if req.TTSModel != "" {
				ttsModel = req.TTSModel
			}
			storyContext = req.Context
		} else {
			topic = string(message)
		}

		log.Printf("Topic: %s | Voice: %s | TTS Model: %s", topic, voice, ttsModel)

		if genaiClient != nil {
			if err := streamStory(ctx, genaiClient, ttsClient, conn, topic, voice, ttsModel, storyContext); err != nil {
				log.Printf("Story Error: %v", err)
			}
		} else {
			streamTTS(ctx, ttsClient, conn, topic)
		}
	}
}

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}

func GenerateImage(ctx context.Context, client *genai.Client, prompt string) (string, error) {
	// Use gemini-3-pro-image-preview for high quality illustrations
	model := getEnv("GEMINI_MODEL_IMAGE", "gemini-3-pro-image-preview")
	
	log.Printf("Generating image for prompt: %s using model: %s", prompt, model)

	// We want a square image for the storybook feel (or 16:9, but default 1:1 is fine)
	// The SDK might change config, but basic GenerateContent with text -> image modality is standard.
	resp, err := client.Models.GenerateContent(ctx, model, genai.Text(prompt), &genai.GenerateContentConfig{
		ResponseModalities: []string{"IMAGE"},
	})
	if err != nil {
		log.Printf("GenAI Image Generation failed: %v", err)
		return "", err
	}

	if len(resp.Candidates) == 0 || len(resp.Candidates[0].Content.Parts) == 0 {
		return "", fmt.Errorf("no content generated")
	}

	for _, part := range resp.Candidates[0].Content.Parts {
		if part.InlineData != nil {
			log.Printf("Image generated successfully. Bytes: %d", len(part.InlineData.Data))
			return base64.StdEncoding.EncodeToString(part.InlineData.Data), nil
		}
	}
	
	return "", fmt.Errorf("no inline image data found")
}

func SummarizeStory(ctx context.Context, client *genai.Client, oldContext, newChapter string) (string, error) {
	model := getEnv("GEMINI_MODEL_SUMMARY", "gemini-2.5-flash-preview-09-2025") // Fast model
	prompt := fmt.Sprintf(`
Summarize the following story segment, merging it with the previous context. 
Keep key characters, current location, and plot points concise (max 100 words).
Previous Context: %s
New Segment: %s
`, oldContext, newChapter)

	log.Printf("Summarizing story with model: %s", model)
	resp, err := client.Models.GenerateContent(ctx, model, genai.Text(prompt), nil)
	if err != nil {
		return "", err
	}
	if len(resp.Candidates) > 0 && len(resp.Candidates[0].Content.Parts) > 0 {
		return resp.Candidates[0].Content.Parts[0].Text, nil
	}
	return "", fmt.Errorf("no summary generated")
}

func GenerateSuggestions(ctx context.Context, client *genai.Client, summary string) ([]string, error) {
	model := getEnv("GEMINI_MODEL_SUMMARY", "gemini-2.5-flash-preview-09-2025") // Re-use flash
	prompt := fmt.Sprintf(`
Based on this story summary: "%s", suggest 3 short, intriguing plot continuations or user actions.
Keep them under 10 words each.
Format: JSON list of strings. Example: ["Open the door", "Run away"]
`, summary)

	log.Printf("Generating suggestions with model: %s", model)
	resp, err := client.Models.GenerateContent(ctx, model, genai.Text(prompt), &genai.GenerateContentConfig{
		ResponseMIMEType: "application/json",
	})
	if err != nil {
		return nil, err
	}
	
	if len(resp.Candidates) > 0 && len(resp.Candidates[0].Content.Parts) > 0 {
		var suggestions []string
		text := resp.Candidates[0].Content.Parts[0].Text
		// Clean up potential markdown code blocks
		text = strings.TrimPrefix(text, "```json")
		text = strings.TrimPrefix(text, "```")
		text = strings.TrimSuffix(text, "```")
		
		if err := json.Unmarshal([]byte(text), &suggestions); err == nil {
			return suggestions, nil
		}
		log.Printf("Failed to unmarshal suggestions JSON: %s", text)
	}
	return []string{"Continue..."}, nil
}

func streamStory(ctx context.Context, genClient *genai.Client, ttsClient *texttospeech.Client, wsConn *websocket.Conn, topic string, voice string, ttsModel string, storyContext string) error {
	log.Printf("Starting Story Generation for topic: %s (Voice: %s, TTS Model: %s)", topic, voice, ttsModel)

	var wsMu sync.Mutex
	writeWS := func(messageType int, data []byte) error {
		wsMu.Lock()
		defer wsMu.Unlock()
		return wsConn.WriteMessage(messageType, data)
	}

	// Helper to speak a single sentence (New Stream per sentence)
	speakSentence := func(text string) error {
		log.Printf("Speaking Sentence (Length: %d): %s", len(text), text)
		
		stream, err := ttsClient.StreamingSynthesize(ctx)
		if err != nil {
			log.Printf("TTS StreamingSynthesize failed: %v", err)
			return err
		}

		// Send Config
		err = stream.Send(&texttospeechpb.StreamingSynthesizeRequest{
			StreamingRequest: &texttospeechpb.StreamingSynthesizeRequest_StreamingConfig{
				StreamingConfig: &texttospeechpb.StreamingSynthesizeConfig{
					Voice: &texttospeechpb.VoiceSelectionParams{
						Name:         voice,
						LanguageCode: "en-US",
						ModelName:    ttsModel,
					},
				},
			},
		})
		if err != nil {
			return fmt.Errorf("TTS Config Send failed: %v", err)
		}

		// Send Text
		err = stream.Send(&texttospeechpb.StreamingSynthesizeRequest{
			StreamingRequest: &texttospeechpb.StreamingSynthesizeRequest_Input{
				Input: &texttospeechpb.StreamingSynthesisInput{
					InputSource: &texttospeechpb.StreamingSynthesisInput_Text{Text: text},
				},
			},
		})
		if err != nil {
			return fmt.Errorf("TTS Input Send failed: %v", err)
		}
		
		// Close Send to signal end of input
		if err := stream.CloseSend(); err != nil {
			return fmt.Errorf("TTS CloseSend failed: %v", err)
		}

		// Receive Audio
		for {
			resp, err := stream.Recv()
			if err == io.EOF {
				break
			}
			if err != nil {
				return fmt.Errorf("TTS Recv Error: %v", err)
			}
			if len(resp.AudioContent) > 0 {
				writeWS(websocket.BinaryMessage, resp.AudioContent)
			}
		}
		return nil
	}

	prompt := fmt.Sprintf(`
You are a master storyteller. 
Your audience is listening to this story, so use evocative language, clear imagery, and a natural rhythm. 
Topic: %s
%s

Instructions:
1. First, provide a creative Title for the story in the format: "Title: [Your Title]".
2. Then, tell the story (approx. 150 words).
3. Focus on sensory details (sight, sound, smell).
4. Ensure a clear narrative arc with a satisfying conclusion.
5. Avoid markdown formatting (like bold or italics) as this is for TTS.
`, topic, func() string {
		if storyContext != "" {
			return fmt.Sprintf("Previous Story Context: %s\nContinue the story naturally from this context.", storyContext)
		}
		return ""
	}())
	log.Printf("Gemini Prompt: %s", prompt)

	storyModel := getEnv("GEMINI_MODEL_STORY", "gemini-3-pro-preview")
	iter := genClient.Models.GenerateContentStream(ctx, storyModel, genai.Text(prompt), nil)

	// Trigger Image Generation (Parallel)
	go func() {
		imagePrompt := fmt.Sprintf("A cinematic, storybook illustration for a story about: %s. High contrast, magical atmosphere.", topic)
		log.Printf("Image Generation Prompt: %s", imagePrompt)
		b64Image, err := GenerateImage(ctx, genClient, imagePrompt)
		if err != nil {
			log.Printf("Image Gen Error: %v", err)
			return
		}
		msg, _ := json.Marshal(StoryResponse{Type: "image", Content: b64Image})
		writeWS(websocket.TextMessage, msg)
	}()

	// Channel to buffer sentences for TTS
	sentenceChan := make(chan string, 5) // Buffer up to 5 sentences
	
	// Error channel to propagate errors from the goroutine
	errChan := make(chan error, 1)

	// Producer: Gemini Generation
	go func() {
		defer close(sentenceChan)
		defer close(errChan)

		var buffer strings.Builder
		var fullStory strings.Builder

		for resp, err := range iter {
			if err != nil {
				log.Printf("Gemini Stream Error: %v", err)
				errChan <- err
				return
			}

			for _, part := range resp.Candidates[0].Content.Parts {
				if part.Text != "" {
					buffer.WriteString(part.Text)
					fullStory.WriteString(part.Text)

					// Check for Title (Line based)
					if strings.HasPrefix(buffer.String(), "Title: ") && strings.Contains(buffer.String(), "\n") {
						parts := strings.SplitN(buffer.String(), "\n", 2)
						title := strings.TrimSpace(strings.TrimPrefix(parts[0], "Title: "))
						log.Printf("Generated Title: %s", title)
						
						msg, _ := json.Marshal(StoryResponse{Type: "title", Content: title})
						writeWS(websocket.TextMessage, msg)
						
						buffer.Reset()
						buffer.WriteString(parts[1]) // Keep the rest
					}

					// Sentence Splitter Loop
					for {
						text := buffer.String()
						idx := strings.IndexAny(text, ".?!")
						if idx == -1 {
							if len(text) > 200 {
								spaceIdx := strings.LastIndex(text, " ")
								if spaceIdx > 0 {
									idx = spaceIdx
								} else {
									idx = len(text)
								}
							} else {
								break
							}
						} else {
							idx += 1 
						}

						sentence := strings.TrimSpace(text[:idx])
						remaining := text[idx:]

						if len(sentence) > 0 {
							if strings.HasPrefix(sentence, "Title: ") {
								parts := strings.SplitN(sentence, "\n", 2)
								title := strings.TrimSpace(strings.TrimPrefix(parts[0], "Title: "))
								msg, _ := json.Marshal(StoryResponse{Type: "title", Content: title})
								writeWS(websocket.TextMessage, msg)
								if len(parts) > 1 {
									sentence = parts[1]
								} else {
									buffer.Reset()
									buffer.WriteString(remaining)
									continue
								}
							}

							log.Printf("Generated Sentence: %s", sentence)
							msg, _ := json.Marshal(StoryResponse{Type: "sentence", Content: sentence})
							writeWS(websocket.TextMessage, msg)
							sentenceChan <- sentence
						}
						buffer.Reset()
						buffer.WriteString(remaining)
					}
				}
			}
		}

		if buffer.Len() > 0 {
			sentence := strings.TrimSpace(buffer.String())
			if len(sentence) > 0 {
				if strings.HasPrefix(sentence, "Title: ") {
					parts := strings.SplitN(sentence, "\n", 2)
					title := strings.TrimSpace(strings.TrimPrefix(parts[0], "Title: "))
					msg, _ := json.Marshal(StoryResponse{Type: "title", Content: title})
					writeWS(websocket.TextMessage, msg)
					if len(parts) > 1 {
						sentence = parts[1]
					} else {
						return 
					}
				}
				log.Printf("Generated Final Sentence: %s", sentence)
				msg, _ := json.Marshal(StoryResponse{Type: "sentence", Content: sentence})
				writeWS(websocket.TextMessage, msg)
				sentenceChan <- sentence
			}
		}
		log.Printf("Gemini Stream Finished (Producer).")

		// --- Post-Processing: Summary & Suggestions ---
		newSummary, err := SummarizeStory(ctx, genClient, storyContext, fullStory.String())
		if err == nil {
			log.Printf("New Summary: %s", newSummary)
			msg, _ := json.Marshal(StoryResponse{Type: "context", Content: newSummary})
			writeWS(websocket.TextMessage, msg)
			
			suggestions, err := GenerateSuggestions(ctx, genClient, newSummary)
			if err == nil {
				log.Printf("Suggestions: %v", suggestions)
				msg, _ := json.Marshal(StoryResponse{Type: "suggestions", Data: suggestions})
				writeWS(websocket.TextMessage, msg)
			} else {
				log.Printf("Suggestion Error: %v", err)
			}
		} else {
			log.Printf("Summarize Error: %v", err)
		}
	}()

	// Consumer: TTS Playback (Main Block)
	// This runs in the main goroutine and blocks until the channel is closed
	for sentence := range sentenceChan {
		if err := speakSentence(sentence); err != nil {
			log.Printf("Speak Error: %v", err)
			return err
		}
	}

	// Check if Producer had an error
	if err := <-errChan; err != nil {
		return err
	}

	log.Printf("Story Generation Finished Successfully.")
	return nil
}

func streamTTS(ctx context.Context, client *texttospeech.Client, wsConn *websocket.Conn, text string) error {
	// Legacy Echo implementation (Omitted for brevity, Story mode is primary)
	return nil
}