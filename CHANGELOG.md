# Changelog

All notable changes to **TransManga** are documented in this file.

## [1.3.0] - 2026-10-30

### Added
- **Testable Multi-Target Package Architecture**: Split `Package.swift` into `TransMangaCore` (library), `TransManga` (executable entry point), and `TransMangaTests` (`XCTest` target).
- **Snapshot Export (`📷`)**: Added `MangaSnapshotExporter` (`SnapshotExporting`) and a `📷` button in the expanding top-right overlay menu to export composite PNG snapshots of the manga region with translated bubbles rendered in place.
- **Task Cancellation & Generation Guard**: Added `activeTranslationTask` and `captureGeneration` in `TransMangaModel` so scrolling in Auto-Watch or toggling the overlay off immediately cancels stale OCR/Ollama requests.
- **Actor-Isolated Ollama Daemon Manager**: Converted `OllamaDaemonManager` to a Swift `actor` conforming to `OllamaDaemonManaging` to prevent process-spawn race conditions.
- **Typed Error Domain (`TranslationError`)**: Added structured error handling for unreachable local server, missing model tag, request timeout, HTTP status codes, and malformed responses.
- **Unit Test Suite & CI**: Added 12 deterministic unit tests in `Tests/TransMangaTests/TransMangaSmokeTests.swift` and a GitHub Actions workflow (`.github/workflows/ci.yml`) running `swift build` and `swift test` on `macos-14`.

## [1.2.0] - 2026-10-29

### Added
- **SOLID 9-File Architecture**: Separated monolithic source into `DomainModels.swift`, `ThemePalette.swift`, `ScreenCaptureService.swift`, `MangaOCRService.swift`, `OllamaTranslationService.swift`, `TransMangaModel.swift`, `OverlayWindowController.swift`, `ContentView.swift`, and `AppLifecycle.swift`.
- **3-Tab Liquid Glass Control Window**: Added **Home**, **Log**, and **Glossary** tabs with reactive Liquid Glass bottom bar and gliding mascot animation.
- **Inside Top-Right Expanding Overlay Menu**: Replaced external floating toolbar with a compact inside `...` capsule (`✏️`, `Auto - あ`, `あ`, `🔒`).
- **Kanji-Adjacent Furigana Filter & Panel Gutter Detection**: Improved vertical Japanese OCR accuracy and right-to-left manga reading order.
- **Self-Excluding Window Capture**: Updated `CoreGraphicsScreenCaptureService` to capture `.optionOnScreenBelowWindow` using the overlay panel's `CGWindowID` so Auto-Watch never re-captures its own English overlay cards.
