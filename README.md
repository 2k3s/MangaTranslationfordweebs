# TransManga (MangaTranslationfordweebs)

A macOS app I made to translate raw Japanese manga directly on my screen. It uses Apple's built-in Live Text (`VisionKit`) for vertical Japanese OCR and a local [Ollama](https://ollama.com/) model (`qwen2.5:7b` or `qwen2.5:14b`) for translation, so everything runs offline on your Mac without needing paid API keys.

Basically you turn the overlay box on, position it over whatever manga page you're reading in your browser or reader app, and it places the English text right over the original speech bubbles.

## Features

* **In-place bubble overlay**: Covers the original Japanese text (matching the bubble's paper/grey color and tilt angle) and fits the English translation inside the bubble.
* **Auto-start local Ollama**: Automatically detects and launches `ollama serve` in the background on startup if it isn't already running, and cleanly stops it when you quit if TransManga started it.
* **Auto-translate on scroll (`Auto - あ`)**: Watches the region beneath the overlay window and automatically translates new pages when you scroll or flip the page.
* **Manual box tool (`✏️`)**: If the OCR misses a stylized bubble or background text, drag a box over it manually, or click `×` on any bubble to hide it.
* **Snapshot export (`📷`)**: Save a composite PNG of the manga page with the translated English speech bubbles rendered in place (`NSSavePanel`).
* **Glossary & Log tabs**: Save character names (like `星架 -> Seika`) so the model keeps spellings consistent, edit translations live in the log, or click **Breakdown** to see what individual Japanese words mean.
* **Menu bar controls**: Switch between installed local Ollama models or toggle the overlay from the icon in the top menu bar.

## Setup

You'll need a Mac running **macOS 13+** (Apple Silicon recommended) and [Ollama](https://ollama.com/) installed.

1. **Install Ollama and pull a Japanese-capable model**:

       brew install ollama
       ollama pull qwen2.5:7b

   *(Optional: if your Mac has 16GB+ unified memory, `ollama pull qwen2.5:14b` gives even more natural manga dialogue.)*

2. **Run the app**:

   * **Easiest way**: Download `TransManga-macOS.zip` from [Releases](https://github.com/2k3s/MangaTranslationfordweebs/releases), unzip it, and move `TransManga.app` to `/Applications`.
   * **Build and run from source**:

         git clone https://github.com/2k3s/MangaTranslationfordweebs.git
         cd MangaTranslationfordweebs
         swift build && swift run

   * **Run the unit test suite**:

         swift test

   * **Bundle into a standalone `.app`**:

         ./bundle_app.bash 1.3.0

3. **Screen Recording permission**:
   macOS will ask for Screen Recording permission the first time you translate a page (**System Settings → Privacy & Security → Screen Recording**). Turn it on and restart the app.

## Shortcuts & Overlay Controls

Use the expanding `...` pill in the top-right corner of the overlay box (`[ ✏️ | Auto - あ | あ | 📷 | 🔒 ]`) or global hotkeys:

| Shortcut | Action |
| --- | --- |
| `⌃ ⌥ M` | Translate the current box (`あ`) |
| `⌃ ⌥ O` | Lock / unlock click-through mode (`🔒`) so you can scroll your browser through the box |
| `⌃ ⌥ W` | Turn auto-translate on or off (`Auto - あ`) |
| `⌃ ⌥ H` | Hide / show the English bubbles to peek at the original Japanese |

## Project Documentation

* [Architecture Overview](docs/architecture.md)
* [Project Status & Roadmap](docs/PROJECT_STATUS.md)
* [Contributing & Git Workflow](CONTRIBUTING.md)
* [Changelog](CHANGELOG.md)
