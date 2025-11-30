# Project Echo UI Hierarchy

## Screens

### 1. `EchoScreen` (`lib/main.dart`)
*   **Role:** The single-page interface for the Storyteller experience.
*   **Theme:** Supports Light/Dark Mode toggle.
*   **Structure:**
    *   `Scaffold`
        *   `AppBar`
            *   Title: "The Echo Storyteller" (or "The Echo Storyteller: [Story Title]")
            *   Actions: Theme Toggle, Refresh.
        *   `Body` -> `Column`
            1.  **Header Info** (`Wrap`)
                *   **Status Chip:** Connection State + Latency (TTFB).
                *   **Metadata Chips:** Voice Name (Tooltip: Model/Encoding) + Persona (Tooltip: Persona).
            2.  **The Book** (`Expanded` -> `Container` -> `SingleChildScrollView`)
                *   **Story Body:** (`SelectableText.rich`)
                *   **Logic:** Auto-scrolls to bottom on new text.
                *   **Style:**
                    *   *Current Sentence:* Georgia Font, Large, High Contrast.
                    *   *Past Sentences:* Dimmed/Grey.
            3.  **Input Area** (`Row`)
                *   **Story Input:** `TextField` (Rounded, Themed Fill).
                *   **Voice Selector:** `DropdownButton` (Puck, Zephyr, etc.).
                *   **Model Selector:** `DropdownButton` (Flash, Lite, Pro).
                *   **Send Button:** `FloatingActionButton` (Auto-Awesome Icon).
            4.  **Suggestion Chips** (`Wrap` -> `ActionChip`)
                *   Quick-start prompts ("A cyberpunk detective...").

## State Management

### `_EchoScreenState`
*   **`_transcript` (`List<String>`):** Accumulates sentences received from the backend.
*   **`_status` (`String`):** UI-facing status text.
*   **`_ttfb` (`int?`):** Time to First Byte metric (ms).
*   **`_selectedVoice` (`String`):** The currently selected voice (default: "Puck").
*   **`_themeMode` (`ThemeMode`):** Toggles between Light/Dark.

### `PcmPlayer` (`lib/audio/pcm_player.dart`)
*   **Role:** Encapsulates the **Web Audio API** logic.
*   **Streams:**
    *   `currentTextStream`: Emits the subtitle text exactly when its audio buffer is scheduled to start.
    *   `isPlayingStream`: Emits true/false based on the internal buffer queue status.
