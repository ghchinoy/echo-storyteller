# The Echo Storyteller: Interactive AI Audio Experiences

**The Echo Storyteller** is a reference implementation for building **immersive, low-latency AI voice applications** on the web. It demonstrates how to combine advanced Generative AI models with real-time streaming audio to create a fluid "Choose Your Own Adventure" experience.

## 🎯 Objective
This project highlights the power of the Google Cloud AI stack for building next-generation web experiences:
*   **Interactive Storytelling:** Uses **Gemini 3 Pro** (Preview) to generate creative narratives that adapt to user choices.
*   **Real-Time Voice:** Uses **Google Cloud TTS (Gemini Voices)** with `StreamingSynthesize` to speak the story as it is being written, with near-instant latency.
    *   **Visual Context:** Uses **Gemini 3 Pro Image** to generate cinematic illustrations for every chapter on the fly.
    *   **Adaptive UI:** Features a responsive layout that transitions between a linear mobile feed and a side-by-side "Book & Illustration" desktop view.
    *   **True Web Streaming:** Demonstrates a robust **WebSocket + Web Audio API** architecture that bypasses standard browser media limitations for gapless, low-latency PCM streaming.
## 🎮 How to Use

1.  **Start a Story:**
    *   Open the app and select a **Voice** (e.g., Puck, Zephyr) and **TTS Model** (Flash, Lite, Pro).
    *   Type a topic (e.g., "A cyberpunk detective finding a lost cat") or click the **Refresh** button to get AI-generated ideas.
    *   Click **Go** (Auto-Awesome).

2.  **Listen & Watch:**
    *   The story begins immediately. Text streams in, audio plays in sync, and a unique illustration fades in.
    *   The app handles "Infinite Scrolling" so you can read back through previous chapters.

3.  **Choose Your Path:**
    *   At the end of a chapter, the AI suggests 3 **"What happens next?"** options.
    *   Click one to continue the story seamlessly, or type your own custom action.
    *   The story context is preserved, creating a coherent multi-chapter narrative.

4.  **Reset:**
    *   Click the **"End Story"** chip to clear the context and start a fresh adventure.

## 🚀 Tech Stack Highlights

*   **Frontend:** Flutter Web (WASM ready).
    *   **Audio Engine:** Custom `PcmPlayer` using `dart:js_interop` and the **Web Audio API** (`AudioContext`) for raw PCM playback. Standard audio players cannot handle this low-latency stream.
    *   **State:** "Rolling Summary" context management for infinite story depth.
*   **Backend:** Go (Golang) 1.25+.
    *   **Orchestration:** A **Producer-Consumer** concurrent pipeline handles Text Generation, Image Generation, and Audio Synthesis in parallel to minimize TTFB (Time To First Byte).
    *   **Gemini 3 Pro:** Powering the core narrative and image generation.
    *   **Gemini 2.5 Flash:** Powering the high-speed summarization and option generation.
    *   **Quantized Streaming:** Implements a robust re-connection strategy for Gemini TTS to bypass server-side context limits while maintaining a continuous stream.

## 🛠️ The Architecture

### The Problem
Flutter's standard audio packages (`just_audio`, `audioplayers`) rely on the browser's `<audio>` tag or Media Source Extensions (MSE).
1.  **MSE** requires valid container headers (MP4/WebM). Google TTS streams raw frames or Ogg pages that often fail MSE validation in Chrome/Safari.
2.  **Standard Playback** (HTTP) requires a valid file structure.
3.  **Raw PCM** cannot be played by `<audio>` tags directly.

### The Solution
Project Echo bypasses the browser's media demuxer entirely by using the **Web Audio API**.

1.  **Backend (Go):**
    *   Receives Text Topic.
    *   **Producer:** Generates Story (Gemini 3 Pro) & Image (Gemini 3 Image) concurrently.
    *   **Consumer:** buffers sentences and calls `tts.StreamingSynthesize` (LINEAR16) for each sentence to ensure stable prosody.
    *   Forwards raw `AudioContent` bytes to WebSocket.
2.  **Frontend (Flutter):**
    *   Receives `Uint8List` chunks.
    *   Converts `Int16` (PCM) bytes to `Float32` audio data.
    *   Schedules `AudioBuffer` playback precisely using `AudioContext.currentTime`.

## 🚦 Quick Start

### 1. Prerequisites
*   Go 1.25+
*   Flutter 3.x
*   Google Cloud Project with Billing enabled.
*   `gcloud` CLI installed and configured.

### 2. Infrastructure Setup
Use the provided script to enable APIs and create a dedicated Service Account:
```bash
./setup_sa.sh
```
This will create a Service Account with `Vertex AI User` and `Logging Writer` roles.

### 3. Configuration
Create a `.env` file in the root directory:
```env
GOOGLE_CLOUD_PROJECT=your-project-id
GOOGLE_CLOUD_LOCATION=us-central1
```

### 4. Run Locally
```bash
./dev.sh
```
This script builds the Flutter web app and starts the Go server on port `8080`.
*   Open `http://localhost:8080`.
*   Click the **Play** icon (Initializes Audio Context).
*   Type a topic and hit Send.

### 5. Deploy to Cloud Run
```bash
./deploy.sh
```
*   Make sure to uncomment the Service Account line in `deploy.sh` (or rely on the script's auto-detection) to use the secure identity created in step 2.

## 📂 Project Structure

*   `backend/`: Go server implementation.
*   `frontend/`: Flutter application.
    *   `lib/audio/pcm_player.dart`: **Core Logic**. The custom Web Audio API player.
*   `docs/`: Detailed architectural findings and decision logs.
