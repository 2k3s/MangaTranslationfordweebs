<img src="AppIcon.png" width="110" /> 

# Manga Translation for Dweebs / TransManga

I wanted something where I could just open a manga page in my browser, put a selection box over it, and have English translations pop up right over the speech bubbles locally on my Mac.

## How it works

1. Captures the screen with a resizable selection box
2. Uses ImageAnalyzer to read Japanese texts, and translates them through Ollama (🤓 qwen2.5:7b to be exact)
3. Renders English texts over the original text bubbles

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `⌃ ⌥ O` | Toggle **Click-Through / Reading Mode** (lets you click and scroll your browser right through the overlay and hides the blue tint/handles) |
| `⌃ ⌥ M` | Manually capture & translate the selected region |
| `⌃ ⌥ W` | Toggle **Auto-Watch Mode** (automatically hides cards on scroll and translates new pages when they settle) |
| `⌃ ⌥ H` | **Peek Original** (temporarily hides/shows the English cards so you can see the raw Japanese underneath) |

## das it for now :p 
