<img src="AppIcon.png" width="160">

# TransManga (MangaTranslationfordweebs)

A macOS app I made to translate raw Japanese manga directly on my screen. It uses Apple's built-in Live Text for vertical Japanese OCR and a local [Ollama](https://ollama.com/) model (`qwen2.5:7b`) for the translation, so everything runs offline on your Mac without needing paid API keys.

Basically you just turn the overlay box on, put it over whatever manga page you're reading in your browser, and it places the English text right over the original speech bubbles.

## Features

- **In-place bubble overlay**: Covers the original Japanese text (matching the bubble's paper/grey color and tilt angle) and fits the English translation inside the bubble.
- **Auto-translate on scroll**: Watches the region and automatically translates new pages when you scroll or flip the page.
- **Manual box tool (`✏️`)**: If the OCR misses a bubble or some background text, you can drag a box over it manually, or click `×` on any bubble to hide it.
- **Glossary & Log tabs**: Save character names (like `星架 -> Seika`) so the model doesn't keep changing how it spells them, edit translations in the log, or click **Breakdown** to see what individual Japanese words mean.
- **Menu bar controls**: Switch between local Ollama models or toggle the box from the cat icon in the top menu bar.

## Setup

You'll need a Mac (macOS 13+, Apple Silicon recommended) and [Ollama](https://ollama.com/) installed.

1. **Start Ollama and pull `qwen2.5:7b`**:
   ```bash
   brew install ollama
   ollama serve
   ```
   In another terminal tab:
   ```bash
   ollama pull qwen2.5:7b
   ```

2. **Run the app**:
   - **Easiest way**: Download `TransManga-macOS.zip` from [Releases](https://www.google.com/search?q=https://github.com/2k3s/MangaTranslationfordweebs/releases), unzip it, and move `TransManga.app` to `/Applications`.
   - **Build from source**:
     ```bash
     git clone https://github.com/2k3s/MangaTranslationfordweebs.git
     cd MangaTranslationfordweebs
     swift build && swift run
     ```
     If you want to bundle it into a `.app` yourself, run `./bundle_app.sh`.

3. **Screen Recording permission**:
   macOS will ask for Screen Recording permission the first time you translate a page (**System Settings → Privacy & Security → Screen Recording**). Turn it on and restart the app.

## Shortcuts

You can also use the `...` button in the top-right corner of the overlay box when it's unlocked.

| Shortcut | What it does |
| :--- | :--- |
| `⌃ ⌥ M` | Translate the current box (`あ`) |
| `⌃ ⌥ O` | Lock / unlock click-through mode (`🔒`) so you can scroll your browser through the box |
| `⌃ ⌥ W` | Turn auto-translate on or off (`Auto - あ`) |
| `⌃ ⌥ H` | Hide/show the English bubbles to peek at the original Japanese |
