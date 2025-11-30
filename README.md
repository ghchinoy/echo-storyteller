# Project Echo: Flutter Web Streaming Audio Reference

**Project Echo** is a reference implementation demonstrating **true low-latency audio streaming** from a Go backend to a Flutter Web client, specifically designed for AI Voice / Text-to-Speech (TTS) applications.

It solves the difficult problem of playing a continuous, growing stream of raw audio bytes on the web, where standard libraries often fail due to browser container requirements.

## 🚀 Features

*   **Protocol:** WebSockets (Binary) for low-overhead bidirectional communication.
*   **TTS Engine:** Google Cloud Text-to-Speech (v1) `StreamingSynthesize`.
*   **GenAI Engine:** Vertex AI (Gemini 2.5 Flash) for low-latency text generation.
*   **Audio Format:** Raw PCM (`LINEAR16`) @ 24kHz.
*   **Playback:** Custom **Web Audio API** implementation (`AudioContext`) via Dart JS Interop.
*   **Latency:** Sub-second Time-to-First-Byte (TTFB).

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
    *   Generates Story stream using Gemini (Vertex AI).
    *   Buffers sentences.
    *   Calls `tts.StreamingSynthesize` (LINEAR16).
    *   Forwards raw `AudioContent` bytes to WebSocket.
2.  **Frontend (Flutter):**
    *   Receives `Uint8List` chunks.
    *   Converts `Int16` (PCM) bytes to `Float32` audio data.
    *   Schedules `AudioBuffer` playback precisely using `AudioContext.currentTime`.

## 📦 Tech Stack

*   **Frontend:** Flutter (Web Target)
    *   `package:web` (Modern JS Interop)
    *   `web_socket_channel`
*   **Backend:** Go 1.25+
    *   `github.com/gorilla/websocket`
    *   `cloud.google.com/go/texttospeech/apiv1`
    *   `google.golang.org/genai` (Vertex AI)

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
