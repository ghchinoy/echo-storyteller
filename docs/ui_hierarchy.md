# Project Echo UI Hierarchy

## Screens

### 1. `EchoScreen` (`lib/main.dart`)
*   **Role:** The single-page interface for the Storyteller experience.
*   **Theme:** Supports Light/Dark Mode toggle.
*   **Structure:**
    *   `Scaffold`
        *   `AppBar`
            *   Title: "**The Infinite Storyteller**" (or "The Infinite Storyteller: [Story Title]")
            *   Actions: Theme Toggle, Refresh.
        *   `Body` -> `LayoutBuilder`
            *   **Desktop (>800px):** `Row`
                *   `AnimatedContainer` (**Main Content**) - *Animates width (100% -> 50%).*
                *   `AnimatedContainer` (**Visual Panel**) - *Animates width (0% -> 50%).*
            *   **Mobile:** `Main Content`
            
    *   **Main Content** (`Padding` -> `Column`)
        1.  **Header Info** (`Wrap`)
            *   **Status Chip:** Connection State + Latency (TTFB).
            *   **Metadata Chips:** Voice Name (Tooltip: Model/Encoding) + Persona (Tooltip: Persona).
        2.  **The Book** (`Expanded` -> `Container` -> `SingleChildScrollView`)
            *   **Content:** `Column` of **Chapters**.
            *   **Chapter Structure (`_ChapterView`):**
                *   **Title:** (`Text` - H1 Style).
                *   **Image (Mobile Only):** (`AnimatedSize` -> `Image.memory`) - *Inline.*
                *   **Body Text:** (`SelectableText` - Georgia Font, ~16-18pt).
                *   **Divider:** Visual separation between chapters.
        3.  **Plot Suggestions** (`AnimatedSize` -> `Column`)
            *   *Condition:* Visible when suggestions are available (Fixed between Book and Input).
            *   *Label:* "What happens next?"
            *   *Action:* "End Story" chip to reset context.
        4.  **Input Area** (`Row`)
            *   `TextField`, `Voice/Model Selectors`, `FAB`.
        5.  **Quick Start Suggestions** (`Wrap` -> `ActionChip`)
            *   *Condition:* Only shown when story is empty (fresh state).
            *   *Action:* "Refresh" button (AI Prompt Gen).

    *   **Visual Panel (Desktop Only)** (`AnimatedContainer`)
        *   **Background:** Black.
        *   **Content:** `Center` -> `GestureDetector` -> `AnimatedSwitcher` -> `Image.memory` (Latest Image).
        *   **Interaction:** Tap to open Lightbox Dialog.
        *   **Placeholder:** Icon + Text ("Visuals will appear here") if no image yet.

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
