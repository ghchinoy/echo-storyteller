package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"

	texttospeech "cloud.google.com/go/texttospeech/apiv1"
	"cloud.google.com/go/texttospeech/apiv1/texttospeechpb"
	"github.com/gorilla/websocket"
	"google.golang.org/genai"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

type StoryRequest struct {
	Topic string `json:"topic"`
	Voice string `json:"voice"`
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

		var req StoryRequest
		if err := json.Unmarshal(message, &req); err == nil && req.Topic != "" {
			topic = req.Topic
			if req.Voice != "" {
				voice = req.Voice
			}
		} else {
			topic = string(message)
		}

		log.Printf("Topic: %s | Voice: %s", topic, voice)

		if genaiClient != nil {
			if err := streamStory(ctx, genaiClient, ttsClient, conn, topic, voice); err != nil {
				log.Printf("Story Error: %v", err)
			}
		} else {
			streamTTS(ctx, ttsClient, conn, topic)
		}
	}
}

func streamStory(ctx context.Context, genClient *genai.Client, ttsClient *texttospeech.Client, wsConn *websocket.Conn, topic string, voice string) error {
	log.Printf("Starting Story Generation for topic: %s (Voice: %s)", topic, voice)
	
	ttsStream, err := ttsClient.StreamingSynthesize(ctx)
	if err != nil {
		log.Printf("TTS StreamingSynthesize failed: %v", err)
		return err
	}

	log.Printf("Sending TTS Config...")
	err = ttsStream.Send(&texttospeechpb.StreamingSynthesizeRequest{
		StreamingRequest: &texttospeechpb.StreamingSynthesizeRequest_StreamingConfig{
			StreamingConfig: &texttospeechpb.StreamingSynthesizeConfig{
				Voice: &texttospeechpb.VoiceSelectionParams{
					Name:         voice,
					LanguageCode: "en-US",
					ModelName:    "gemini-2.5-flash-tts",
				},
			},
		},
	})
	if err != nil {
		log.Printf("TTS Config Send failed: %v", err)
		return err
	}

	ttsDone := make(chan error)
	go func() {
		defer close(ttsDone)
		var totalBytes int
		for {
			resp, err := ttsStream.Recv()
			if err == io.EOF {
				log.Printf("TTS Stream Completed (EOF). Total Audio Bytes: %d", totalBytes)
				ttsDone <- nil
				return
			}
			if err != nil {
				log.Printf("TTS Recv Error: %v", err)
				ttsDone <- err
				return
			}
			if len(resp.AudioContent) > 0 {
				totalBytes += len(resp.AudioContent)
				// log.Printf("Received Audio Chunk: %d bytes", len(resp.AudioContent)) // Verbose
				wsConn.WriteMessage(websocket.BinaryMessage, resp.AudioContent)
			}
		}
	}()

	prompt := fmt.Sprintf("Tell a short, engaging story about: %s. Keep it under 100 words.", topic)
	log.Printf("Gemini Prompt: %s", prompt)
	
	iter := genClient.Models.GenerateContentStream(ctx, "gemini-2.5-flash", genai.Text(prompt), nil)
	
	var buffer strings.Builder

	for resp, err := range iter {
		if err != nil {
			log.Printf("Gemini Stream Error: %v", err)
			break
		}
		
		for _, part := range resp.Candidates[0].Content.Parts {
			if part.Text != "" {
				buffer.WriteString(part.Text)
				
				if strings.ContainsAny(part.Text, ".?!") || buffer.Len() > 100 {
					sentence := strings.TrimSpace(buffer.String())
					if len(sentence) > 0 {
						log.Printf("Generated Sentence: %s", sentence)
						
						// 1. Send Text to Frontend (Subtitle)
						wsConn.WriteMessage(websocket.TextMessage, []byte(sentence))
						
						// 2. Send to TTS
						err := ttsStream.Send(&texttospeechpb.StreamingSynthesizeRequest{
							StreamingRequest: &texttospeechpb.StreamingSynthesizeRequest_Input{
								Input: &texttospeechpb.StreamingSynthesisInput{
									InputSource: &texttospeechpb.StreamingSynthesisInput_Text{Text: sentence},
								},
							},
						})
						if err != nil {
							log.Printf("TTS Send Text Error: %v", err)
							return err
						}
						buffer.Reset()
					}
				}
			}
		}
	}
	
	if buffer.Len() > 0 {
		sentence := strings.TrimSpace(buffer.String())
		if len(sentence) > 0 {
			log.Printf("Generated Final Sentence: %s", sentence)
			wsConn.WriteMessage(websocket.TextMessage, []byte(sentence))
			ttsStream.Send(&texttospeechpb.StreamingSynthesizeRequest{
				StreamingRequest: &texttospeechpb.StreamingSynthesizeRequest_Input{
					Input: &texttospeechpb.StreamingSynthesisInput{
						InputSource: &texttospeechpb.StreamingSynthesisInput_Text{Text: sentence},
					},
				},
			})
		}
	}

	log.Printf("Gemini Stream Finished. Closing TTS Send...")
	if err := ttsStream.CloseSend(); err != nil {
		log.Printf("TTS CloseSend Error: %v", err)
		return err
	}

	log.Printf("Waiting for TTS to finish...")
	finalErr := <-ttsDone
	if finalErr != nil {
		log.Printf("Story Generation Finished with Error: %v", finalErr)
	} else {
		log.Printf("Story Generation Finished Successfully.")
	}
	return finalErr
}

func streamTTS(ctx context.Context, client *texttospeech.Client, wsConn *websocket.Conn, text string) error {
	// Legacy Echo implementation (Omitted for brevity, Story mode is primary)
	return nil
}