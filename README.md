# MangaLens — macOS prototype

MangaLens is a native SwiftUI macOS starter project for a hotkey-triggered, offline manga translation overlay.

## Current milestone

This prototype provides:
- A native macOS interface
- Global shortcut `Control + Option + M` (⌃ ⌥ M)
- Main-display screenshot capture
- On-device Japanese OCR using Apple's Vision framework
- No network calls or cloud APIs

**Not implemented yet:** local Japanese-to-English translation, text erasure/inpainting, speech-bubble detection, and the transparent replacement overlay. The app intentionally shows OCR output first so the screen-capture and recognition pipeline can be tested independently.

## Requirements

- macOS 13 or later
- Xcode with the macOS SDK
- A Mac with Japanese OCR language support

## Open and run

1. Unzip the project.
2. Open Terminal and `cd` into the `MangaLens` folder.
3. Run `open Package.swift` to open it in Xcode, or open the folder in Xcode.
4. Select the `MangaLens` executable scheme and run it.
5. In **System Settings → Privacy & Security → Screen Recording**, allow MangaLens if macOS requests it. Quit and reopen the app after changing permission.
6. Open a manga page and click **Capture & detect text**, or press **Control + Option + M** while MangaLens is running.

The global keyboard monitor may require **System Settings → Privacy & Security → Accessibility** permission. If the shortcut does not fire, use the button while testing.

## Architecture

- `ContentView.swift` — UI
- `MangaLensModel.swift` — capture and OCR pipeline
- `main.swift` — app entry point and shortcut
- `Package.swift` — Swift Package executable target

## Next milestones

1. Replace the deprecated prototype screenshot API with ScreenCaptureKit.
2. Add a local translation engine behind a `TranslationEngine` protocol. Verify the chosen Japanese-English model and installation flow before bundling it.
3. Use OCR bounding boxes to locate text regions and draw replacement text in a borderless transparent overlay.
4. Add conservative white-bubble cleanup first, then optional local inpainting for textured art.
5. Add an explicit overlay toggle and per-screen/window region selection.

## Privacy

The code in this prototype performs OCR locally and contains no network requests. Screen capture is sensitive: grant permissions only if you trust the app build you are running.
