# Contributing to TransManga

## Development Environment

- **OS**: macOS 13.0+ (Apple Silicon recommended)
- **Tools**: Xcode 15+ / Swift 5.9+, Swift Package Manager, Git
- **Local LLM Backend**: [Ollama](https://ollama.com/) (`qwen2.5:7b` or `qwen2.5:14b`)

## Editor & Terminal Workflow

1. **Edit Swift files in Xcode**:
   Open `Package.swift` in Xcode (`xed .`) to edit files inside `Sources/TransMangaCore/`, `Sources/TransMangaApp/`, and `Tests/TransMangaTests/`.
2. **Build, run, and test in Terminal**:

       swift build
       swift test
       swift run

## Branching & Commit Conventions

- Keep `main` clean, buildable, and passing `swift test` at all times.
- Create a short-lived branch per feature or fix:
  - `2k3s/<feature-name>` (e.g., `2k3s/auto-start-ollama`, `2k3s/snapshot-export`)
  - `fix/<issue-name>`
- Use clear [Conventional Commits](https://www.conventionalcommits.org/):
  - `feat: ...` for new features
  - `fix: ...` for bug fixes
  - `refactor: ...` for structural improvements without behavior changes
  - `test: ...` for unit test additions
  - `docs: ...` for documentation updates
- Always run `swift build && swift test && git status -sb` before committing and merging back into `main`.
