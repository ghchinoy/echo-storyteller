# Project Echo: Coding Conventions & Architectural Standards

**Project Echo** is a reference implementation for high-performance streaming audio in Flutter Web. These conventions must be strictly followed to maintain its status as a reliable architectural blueprint.

## 1. Architectural Pillars

### The "Golden Path" for Web Audio
*   **Protocol:** **WebSockets** (Binary Mode) are mandatory for raw audio streaming. Do not use SSE or HTTP Chunked Transfer for PCM data due to overhead and browser compatibility issues.
*   **Audio Format:** **Linear16 (PCM)** @ 24kHz (Little Endian). This is the native output of Google TTS `StreamingSynthesize` and offers the lowest latency. Avoid MP3/Ogg for low-latency streaming due to container header complexity in MSE.
*   **Playback Engine:** **Web Audio API** via `package:web`.
    *   **Forbidden:** `just_audio` or `audioplayers` for the *streaming* path on Web. (They are fine for static files).
    *   **Mandatory:** Manual `Int16` -> `Float32` conversion and `AudioContext.createBuffer()`.

## 2. Backend (Go)

*   **Streaming Pipeline:**
    *   Pattern: `Gemini Stream` -> `Sentence Buffer` -> `TTS Stream` -> `WebSocket`.
    *   **Reasoning:** Buffering Gemini tokens into sentences ensures high-quality TTS intonation while maintaining streaming behavior.
*   **Concurrency:**
    *   Use a separate Goroutine for reading from the TTS stream to prevent blocking the text input stream.
    *   Always handle `io.EOF` gracefully.
*   **Configuration:**
    *   Do **not** set `StreamingAudioConfig` explicitly unless overriding the default (PCM).
    *   Use `gemini-2.5-flash-tts` (or newer) models for best performance.
*   **Deployment:**
    *   Use `setup_sa.sh` to provision a dedicated Service Account with `aiplatform.user` and `logging.logWriter`.
    *   Env vars `GOOGLE_CLOUD_PROJECT` and `GOOGLE_CLOUD_LOCATION` are mandatory for Vertex AI.
*   **GenAI & TTS Orchestration:**
    *   **Quantized Streaming:** For Gemini TTS models, you **MUST** re-initialize the `StreamingSynthesize` stream for *each* sentence. This avoids the ~512-byte server-side context limit which causes `INVALID_ARGUMENT` errors on long streams.
    *   **Producer-Consumer:** Use a `Goroutine` (Producer) for Text/Image generation and a main loop (Consumer) for TTS feeding. Connect them with a buffered channel (`sentenceChan`). This prevents head-of-line blocking and allows text/images to appear on the client while audio is still processing.

## 3. Frontend (Flutter)

*   **Audio Engine (`lib/audio/pcm_player.dart`):**
    *   Encapsulate all JS Interop logic here.
    *   **User Gesture:** Always provide an `init()` method that must be called from a button press to unlock the `AudioContext`.
    *   **Scheduling:** Maintain precise `_nextPlayTime` to ensure gapless playback of chunks.
*   **State Management:**
    *   Use `setState` for simple prototypes.
    *   Metrics (TTFB) must be tracked to validate performance.
*   **UI & Animation:**
    *   **Minimalist Material 3:** Stick to the "Storybook" aesthetic.
    *   **Input Layout:** `[TextField] [Controls] [FAB]`. Place suggestion chips *below* this row.
    *   **Entrance Animations:** Use `AnimatedSize` and `AnimatedOpacity` for *all* new content (Images, Titles) entering the stream. Avoid harsh layout jumps.
    *   **Connectivity:** Always show connectivity status ("Connected", "Streaming", "Disconnected").
*   **Environment Awareness:**
    *   Use `kDebugMode` to toggle between `localhost` (Dev) and Relative Paths (Production) for API calls.

## 4. Documentation

*   **Living Documents:** `docs/architecture.md` must be updated if the protocol changes.
*   **UI Hierarchy:** `docs/ui_hierarchy.md` must be updated whenever the Flutter UI layout or widget structure is modified. This ensures accurate reference for future features and debugging.
*   **Project Overview:** `README.md` must be kept up-to-date with the project's technical capabilities, objective, and "How to Use" instructions to serve as the primary entry point for developers.
*   **Diagrams:** Use Mermaid for sequence diagrams to visualize the buffer flow.

## 5. Task Management (`bd`)

We use the `bd` (Beads) tool for all issue tracking.

*   **Project Prefix:** `echo`
*   **Workflow:**
    1.  **Create:** Use `bd create` for every unit of work.
    2.  **Implement:** Do the work.
    3.  **Close:** `bd close <id>` upon completion.
*   **Conventions:**
    *   **Descriptions:** **ALWAYS** include a `--description` explaining the "Why" and "What".
    *   **IDs & Parents:**
        *   Find IDs using `bd list`.
        *   Link child tasks to Epics using `--parent <epic-id>`.
        *   **Note:** If `bd` reports a "prefix mismatch" even when using the correct full ID (e.g., `echo-123`), append the `--force` flag to bypass the check.
    *   **Priorities:**
        *   `P0`: Critical / Blocker.
        *   `P1`: Core Feature.
        *   `P2`: Enhancement / Polish.
    *   **Labels:** `research`, `refactor`, `docs`, `frontend`, `backend`.
