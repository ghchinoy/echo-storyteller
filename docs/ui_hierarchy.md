# Project Echo UI Hierarchy

## Screens

### 1. `EchoScreen` (`lib/main.dart`)
*   **Role:** The single-page interface for the Storyteller experience.
*   **Theme:** Supports Light/Dark Mode toggle.
*   **Structure:**
    *   `Scaffold`
        *   `AppBar`
            *   Title: "The Echo Storyteller"
            *   Actions: Theme Toggle, Refresh.
        *   `Body` -> `Column`
            1.  **Header Info** (`Wrap`)
                *   **Status Chip:** Connection State + Latency (TTFB).
                *   **Metadata Chips:** Voice Name (Tooltip: Model/Encoding) + Persona (Tooltip: System Prompt).
            2.  **The Book** (`Expanded` -> `Container` -> `SingleChildScrollView`)
                *   **Widget:** `SelectableText.rich`
                *   **Logic:** Auto-scrolls to bottom on new text.
                *   **Style:**
                    *   *Current Sentence:* Georgia Font, Large, High Contrast.
                    *   *Past Sentences:* Dimmed/Grey.
            3.  **Suggestion Chips** (`Wrap` -> `ActionChip`)
                *   Quick-start prompts ("A cyberpunk detective...").
            4.  **Input Area** (`Row`)
                *   `TextField` (Rounded, Themed Fill).
                *   `FloatingActionButton` (Send / Auto-Awesome Icon).

## State Management

### `_EchoScreenState`
*   **`_transcript` (`List<String>`):** Accumulates sentences received from the backend.
*   **`_status` (`String`):** UI-facing status text.
*   **`_ttfb` (`int?`):** Time to First Byte metric (ms).
*   **`_pendingSubtitle` (`String?`):** Holds the latest text message from WS, waiting for the corresponding binary audio chunk to arrive.
*   **`_themeMode` (`ThemeMode`):** Toggles between Light/Dark.

### `PcmPlayer` (`lib/audio/pcm_player.dart`)
*   **Role:** Encapsulates the **Web Audio API** logic.
*   **Streams:**
    *   `currentTextStream`: Emits the subtitle text exactly when its audio buffer is scheduled to start.
    *   `isPlayingStream`: Emits true/false based on the internal buffer queue status.