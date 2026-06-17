# MyWhi

A tiny native macOS app for voice dictation. Local-only. No cloud, no telemetry, no Electron.

- **Menu bar** — click the icon → **Start Recording** → speak Russian/English → **Stop Recording** → text goes to your clipboard.
- Powered by **[WhisperKit](https://github.com/argmaxinc/WhisperKit)** (on-device, Apple Silicon optimized) with **Faster-Whisper** as a fallback engine.

> **v2.0 in progress** — full desktop app (sidebar + Insights + Scratchpad) coming per
> `.hermes/plans/2026-06-17_135054-mywhi-v2.md`. Current state is the v1 menu bar MVP.

## Project layout

```
~/Documents/MyWhi/
├── Package.swift               # Swift Package Manager manifest
├── Info.plist                  # App bundle metadata (mic usage, no Dock icon)
├── transcribe.py               # Faster-Whisper wrapper (fallback engine)
├── build.sh                    # Build .app into dist/
├── install.sh                  # Copy dist/MyWhi.app to /Applications
├── uninstall.sh                # Remove from /Applications and clean up
├── Sources/MyWhi/              # Swift source files
├── Resources/                  # AppIcon.icns
├── venv/                       # Python venv (fallback engine only)
└── dist/MyWhi.app/             # Built app bundle
```

## Build

```bash
cd ~/Documents/MyWhi
./build.sh
```

First run will:
1. Create `venv/` and install `faster-whisper` (1-2 min) — used as fallback only.
2. SwiftPM fetches `argmax-oss-swift` (WhisperKit) — first time only, ~1 min.

WhisperKit models are downloaded on first use (the app prompts).

## Install

```bash
./install.sh
```

Copies `dist/MyWhi.app` to `/Applications/MyWhi.app`.

The first time you launch it, **right-click → Open** (or approve the Gatekeeper prompt). After that, double-click works.

## Run

- Launch `/Applications/MyWhi.app` (or via Spotlight: "MyWhi").
- The app appears **only in the menu bar** — no Dock icon (until v2 desktop window is added).
- Click the menu bar icon (mic) → popover opens with all controls.
- On first recording, macOS will ask for Microphone permission. Allow it.

## Manual CLI test (no app needed)

```bash
~/Documents/MyWhi/venv/bin/python3 \
  ~/Documents/MyWhi/transcribe.py \
  /tmp/test.wav --model medium --language ru
```

Or with a synthetic Russian sample:

```bash
say -v Milena -o /tmp/mywhi-test.aiff "Привет, это тестовая запись для проверки транскрибации."
afconvert /tmp/mywhi-test.aiff /tmp/mywhi-test.wav -f WAVE -d LEI16@16000
~/Documents/MyWhi/venv/bin/python3 \
  ~/Documents/MyWhi/transcribe.py \
  /tmp/mywhi-test.wav --model medium --language ru
```

## Settings

Editable from the popover's **Settings** disclosure:

- **Model** — `tiny` / `base` / `small` / `medium` (default) / `large-v3-turbo` / `large-v3`
- **Language** — `ru` (default) / `en` / `auto`
- **Engine** — `whisperkit` (default) / `faster-whisper` (fallback)
- **Auto copy to clipboard** — ON by default
- **Save history** — ON by default

Settings persist in `~/Library/Application Support/MyWhi/settings.json`.

## Privacy

- All audio stays on your Mac.
- Audio is written to `/tmp/hermes-dictate/recording-<timestamp>.wav` during recording.
- The Python venv is at `~/Documents/MyWhi/venv/` and is used **only** as a fallback engine. The primary engine is WhisperKit (on-device Swift).
- Microphone access is requested once via macOS's standard TCC prompt.

## Uninstall

```bash
./uninstall.sh
```

Removes `/Applications/MyWhi.app` and optionally purges
`~/Library/Application Support/MyWhi/` (settings + history).

## Roadmap (v2)

See `.hermes/plans/2026-06-17_135054-mywhi-v2.md`:

- Desktop window with `NavigationSplitView` sidebar (Home / Scratchpad / Insights / Settings)
- Markdown-based vault for transcripts (replace JSON history)
- GitHub-style streak heatmap and word/char stats
- Inline markdown editor
- Global hotkey `Cmd+Option+D`
- Obsidian integration