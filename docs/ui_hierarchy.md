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
                *   **Content:** `Column` of **Chapters**.
                *   **Chapter Structure:**
                    *   **Title:** (`Text` - H1 Style) - *If available for this chapter.*
                    *   **Image:** (`AnimatedSize` -> `Image.memory`) - *Smooth entrance.*
                    *   **Body Text:** (`SelectableText` - Georgia Font).
                    *   **Divider:** (`Divider`) - Visual separation between chapters.
            3.  **Plot Suggestions** (`Column` -> `Wrap` -> `ActionChip`)
                *   *Condition:* Visible when story pauses (not streaming) and suggestions are available.
                *   *Label:* "What happens next?"
            4.  **Input Area** (`Row`)
                *   **Story Input:** `TextField` (Rounded, Themed Fill).
                *   **Voice Selector:** `DropdownButton` (Puck, Zephyr, etc.).
                *   **Model Selector:** `DropdownButton` (Flash, Lite, Pro).
                *   **Send Button:** `FloatingActionButton` (Auto-Awesome Icon).
            5.  **Quick Start Suggestions** (`Wrap` -> `ActionChip`)
                *   *Condition:* Only shown when story is empty (fresh state).

## State Management

### `_EchoScreenState`
*   **`_chapters` (`List<Chapter>`):** The source of truth for the story. Each chapter contains:
    *   `title` (String?)
    *   `image` (Uint8List?)
    *   `text` (StringBuffer)
*   **`_context` (`String?`):** The rolling summary of the story so far, sent to/from backend.
*   **`_plotSuggestions` (`List<String>`):** Active continuation options.
*   **`_status` (`String`):** UI-facing status text.
*   **`_ttfb` (`int?`):** Time to First Byte metric (ms).
*   **`_selectedVoice` (`String`):** The currently selected voice.
*   **`_themeMode` (`ThemeMode`):** Toggles between Light/Dark.

### `PcmPlayer` (`lib/audio/pcm_player.dart`)
*   **Role:** Encapsulates the **Web Audio API** logic.
*   **Streams:**
    *   `currentTextStream`: Emits the subtitle text exactly when its audio buffer is scheduled to start.
    *   `isPlayingStream`: Emits true/false based on the internal buffer queue status.
