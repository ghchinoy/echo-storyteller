# The Infinite Storyteller Architecture

## Overview

The Infinite Storyteller is a "GenMedia" application that creates interactive, never-ending audio stories using Generative AI. It employs a **Client-Server** architecture where a Go backend orchestrates the generation process (Text, Image, Audio) and serves a Flutter Web frontend.

## Components

### 1. The Portal (Frontend)
*   **Technology:** Flutter Web (Dart)
*   **Responsibility:**
    *   User Interface for the "Infinite Scroll" story book.
    *   **Audio Engine:** Custom `PcmPlayer` for low-latency raw audio playback.
    *   **State Management:** Tracks chapters, images, and narrative context.
*   **Deployment:** Compiled to static HTML/JS/WASM and served by the Go backend.

### 2. The Orchestrator (Backend)
*   **Technology:** Go 1.25+
*   **Responsibility:**
    *   **WebSocket Server:** bidirectional real-time communication.
    *   **Producer (Brain):** 
        *   Generates text using **Gemini 3 Pro**.
        *   Generates images using **Gemini 3 Pro Image**.
        *   Summarizes context using **Gemini 2.5 Flash**.
    *   **Consumer (Voice):** 
        *   Feeds text to **Cloud TTS** (Gemini Voices).
        *   Manages stream re-initialization to bypass context limits.
*   **Deployment:** Containerized via Docker and deployed to Google Cloud Run.

## Data Flow

1.  **User** enters a topic or selects a suggestion.
2.  **Frontend** sends `WS Message` to Backend.
3.  **Backend (Producer)**:
    *   Calls **Gemini 3 Pro** for text stream.
    *   Calls **Gemini 3 Pro Image** for visualization (parallel).
4.  **Backend (Consumer)**:
    *    buffers sentences.
    *   Calls **Cloud TTS** (`StreamingSynthesize`) for each sentence.
5.  **Backend** pushes `JSON` messages (`title`, `image`, `sentence`, `suggestions`) and `Binary` audio chunks to Frontend.
6.  **Frontend**:
    *   Displays text/images immediately.
    *   Queues audio in `AudioContext`.
    *   Updates context for next turn.

## Infrastructure

*   **Google Cloud Run:** Hosts the containerized application.
*   **Vertex AI:** Provides the Generative AI models (Text & Image).
*   **Cloud Text-to-Speech:** Provides the Gemini voices.
