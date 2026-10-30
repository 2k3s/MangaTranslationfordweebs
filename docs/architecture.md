# TransManga Architecture

## 1. Target Structure (`Package.swift`)

TransManga uses a 3-target Swift Package Manager layout to keep core logic decoupled from the executable entry point and directly testable via `XCTest`:

1. **`TransMangaCore` (Library Target — `Sources/TransMangaCore/`)**:
   Contains all domain models, protocols, services, view models, AppKit window controllers, and SwiftUI views.
2. **`TransManga` (Executable Target — `Sources/TransMangaApp/main.swift`)**:
   Lightweight `@main` entry point that imports `TransMangaCore` and launches the macOS `Settings` window and `MenuBarExtra`.
3. **`TransMangaTests` (Test Target — `Tests/TransMangaTests/`)**:
   Deterministic `XCTest` unit tests verifying OCR sanitization, panel band detection, prompt building, response parsing, and domain error models.

## 2. Module Responsibilities (`Sources/TransMangaCore/`)

| File | Responsibility |
| --- | --- |
| `DomainModels.swift` | Value types (`AppTab`, `OrientedLineMask`, `OverlayTranslationBox`, `RecognizedBlock`, `GlossaryEntry`), `TranslationError`, and `Notification.Name` constants. |
| `ThemePalette.swift` | Brand colors (`MascotPalette`), icon loader (`MascotIconLoader`), and reusable Liquid Glass SwiftUI surfaces and controls. |
| `ScreenCaptureService.swift` | `ScreenCapturing` (`CoreGraphicsScreenCaptureService` using `.optionOnScreenBelowWindow` to exclude the overlay panel, 16×16 perceptual fingerprinting, and bubble luminance sampling) and `SnapshotExporting` (`MangaSnapshotExporter`). |
| `MangaOCRService.swift` | `OCRRecognizing` (`VisionKitMangaOCRService`), `QuadGeometryCalculator`, `MangaTextSanitizer` (furigana filtering & vertical `一` -> `ー` normalization), `PanelBandDetector`, and `BubbleClusterer` (right-to-left within panel rows, top-to-bottom across panels). |
| `OllamaTranslationService.swift` | `OllamaDaemonManaging` (`actor OllamaDaemonManager` for safe background `ollama serve` lifecycle), `MangaPromptBuilding`, `TranslationResponseParsing`, and `MangaTranslating` (`OllamaTranslationService`). |
| `TransMangaModel.swift` | `@MainActor` coordinator managing translation state, task cancellation (`activeTranslationTask` & `captureGeneration`), in-memory `bubbleCache`, Auto-Watch timer (`0.35s`), manual region cropping, and `UserDefaults` glossary persistence. |
| `OverlayWindowController.swift` | `OverlaySelectionStore`, transparent floating `NSPanel` (`OverlayWindowController`), global Carbon hotkeys, interactive overlay bubbles (`SelectionOverlayView`), and the inside top-right expanding menu (`ExpandingTopRightOverlayMenu`). |
| `ContentView.swift` | 3-tab main control window (**Home**, **Log**, **Glossary**) with gliding mascot transition, live bubble editing, and on-demand Japanese word breakdown. |
| `AppLifecycle.swift` | `AppDelegate` lifecycle hooks (bootstrapping Ollama on launch, stopping managed daemon on terminate) and `MenuBarControlView`. |

## 3. Data Flow & Concurrency Model

1. **Screen Capture**: `TransMangaModel` computes the current screen-space rectangle of the overlay selection and calls `ScreenCapturing.captureRegion(_:excludingWindowID:)` passing `store.overlayWindowID`.
2. **Task Cancellation & Generation Guard**: Starting a new translation or toggling the overlay off calls `cancelActiveTranslation()`, which increments `captureGeneration` and cancels `activeTranslationTask`. Each async suspension point (`recognizeBubbleClusters`, `translateBubbles`) checks `Task.isCancelled` and `generation == captureGeneration` before mutating UI state.
3. **OCR & Clustering**: `VisionKitMangaOCRService` runs `ImageAnalyzer` (with `VNRecognizeTextRequest` fallback), filters non-Japanese punctuation noise and Kanji-adjacent furigana, detects horizontal panel gutters (`PanelBandDetector`), and groups vertical columns into speech bubbles sorted right-to-left per panel band (`BubbleClusterer`).
4. **Local LLM Translation**: Uncached bubbles are sent to `http://127.0.0.1:11434/api/chat` with user glossary terms and recent context lines. Responses are parsed by `[n]` index (`TranslationResponseParser`), stripped of residual CJK characters, cached in `bubbleCache`, and rendered inside rotated, color-matched `OverlayTranslationBox` views.
