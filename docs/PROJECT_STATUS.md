# Project Status & Roadmap

## Current Status: v1.3.0 (Stable)

### Working & Verified Capabilities
- **Target Architecture**: Multi-target Swift Package (`TransMangaCore`, `TransManga`, `TransMangaTests`) building and passing tests on macOS 14+ (Apple Silicon).
- **Offline Japanese Manga OCR**: Vertical and horizontal Japanese speech bubble detection via `VisionKit` (`ImageAnalyzer`) with `Vision` (`VNRecognizeTextRequest`) fallback, Kanji-adjacent furigana filtering, vertical long-vowel (`一` -> `ー`) cleanup, and horizontal panel band ordering.
- **Local Ollama Translation & Lifecycle**: Actor-isolated `OllamaDaemonManager` automatically launches `ollama serve` when needed and terminates it cleanly on app exit if spawned by TransManga.
- **Self-Excluding Overlay & Auto-Watch**: Transparent `NSPanel` overlay excluded from screen capture via `.optionOnScreenBelowWindow`, preventing feedback loops during `0.35s` Auto-Watch polling.
- **Interactive Overlay Tools**: Inside top-right expanding menu (`...`) with manual box draw (`✏️`), Auto-Watch (`Auto - あ`), one-shot translate (`あ`), composite PNG Snapshot Export (`📷`), and click-through lock (`🔒`).
- **3-Tab Control Window**: **Home**, **Log** (live English bubble editing + word-by-word Japanese Breakdown), and **Glossary** (persistent character name/term dictionary).
- **Automated Testing & CI**: 12 unit tests in `TransMangaTests` and `.github/workflows/ci.yml` for GitHub Actions.

## Known Limitations
- **Curved / Double-Balloon Speech Bubbles**: Highly irregular or double-lobed speech bubbles sharing tight horizontal spacing may occasionally merge into one cluster; the manual draw tool (`✏️`) and per-bubble dismiss button (`×`) provide an immediate override.
- **Heavy Vertical Stylization / Sound Effects (SFX)**: Hand-drawn decorative katakana SFX outside speech bubbles are intentionally ignored unless selected manually with `✏️`.
- **Ad-Hoc Code Signing**: `bundle_app.bash` uses local ad-hoc signing (`codesign --sign -`), so macOS Gatekeeper requires right-clicking `Open` on another Mac unless signed with an Apple Developer ID certificate.

## Next Priorities
1. **In-App Model Pull Progress**: Add an optional download progress indicator in **Home** if `ollama list` shows no models installed yet.
2. **Customizable Global Shortcuts**: Allow rebinding `⌃⌥M`, `⌃⌥O`, `⌃⌥W`, and `⌃⌥H` from the UI.
3. **Export Formats**: Support copying the composite snapshot directly to the macOS clipboard (`NSPasteboard`) alongside saving to PNG.
