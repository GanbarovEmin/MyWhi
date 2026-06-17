# Hermes Dictate

A tiny macOS menu bar app for voice dictation. Local-only. No cloud, no telemetry, no Electron.

- Click the menu bar icon → **Start Recording** → speak Russian/English → **Stop Recording** → text goes to your clipboard.
- Powered by [Faster-Whisper](https://github.com/SYSTRAN/faster-whisper) running locally in a Python venv.
- Last 10 transcripts are saved in `~/Library/Application Support/HermesDictate/history.json`.

## Project layout

```
~/Documents/Hermes.Dictate/
├── Package.swift               # Swift Package Manager manifest
├── Info.plist                  # App bundle metadata (mic usage, no Dock icon)
├── transcribe.py               # Python wrapper around faster-whisper
├── build.sh                    # Build .app into dist/
├── install.sh                  # Copy dist/Hermes Dictate.app to /Applications
├── uninstall.sh                # Remove from /Applications and clean up
├── Sources/HermesDictate/      # Swift source files
├── Resources/                  # (reserved)
├── venv/                       # Python venv (created by build.sh on first run)
└── dist/Hermes Dictate.app/    # Built app bundle
```

## Build

```bash
cd ~/Documents/Hermes.Dictate
./build.sh
```

First run will:
1. Create `venv/` and install `faster-whisper` (1-2 min).
2. Pre-download the `medium` model to `~/.cache/huggingface/hub/` (~1.5 GB).

Subsequent builds are seconds.

## Install

```bash
./install.sh
```

Copies `dist/Hermes Dictate.app` to `/Applications/Hermes Dictate.app`.

The first time you launch it, **right-click → Open** (or approve the Gatekeeper prompt). After that, double-click works.

## Run

- Launch `/Applications/Hermes Dictate.app` (or via Spotlight: "Hermes Dictate").
- The app appears **only in the menu bar** — no Dock icon, no main window.
- Click the menu bar icon (mic) → popover opens with all controls.
- On first recording, macOS will ask for Microphone permission. Allow it.

## Manual CLI test (no app needed)

```bash
~/Documents/Hermes.Dictate/venv/bin/python3 \
  ~/Documents/Hermes.Dictate/transcribe.py \
  /tmp/test.wav --model medium --language ru
```

Or with a synthetic Russian sample:

```bash
say -v Milena -o /tmp/hermes-test.aiff "Привет, это тестовая запись для проверки транскрибации."
afconvert /tmp/hermes-test.aiff /tmp/hermes-test.wav -f WAVE -d LEI16@16000
~/Documents/Hermes.Dictate/venv/bin/python3 \
  ~/Documents/Hermes.Dictate/transcribe.py \
  /tmp/hermes-test.wav --model medium --language ru
```

## Settings

Editable from the popover's **Settings** disclosure:

- **Model** — `small` / `medium` (default) / `large-v3-turbo` / `large-v3`
- **Language** — `ru` (default) / `en` / `auto`
- **Auto copy to clipboard** — ON by default
- **Save history** — ON by default

Settings persist in `~/Library/Application Support/HermesDictate/settings.json`.

## Auto-start at login

The app does **not** register itself as a login item (we avoid touching system launchd without explicit ask). To enable:

1. Open **System Settings → General → Login Items**.
2. Click **+** under "Open at Login".
3. Pick **Hermes Dictate** from `/Applications`.

## Uninstall

```bash
./uninstall.sh
```

Removes `/Applications/Hermes Dictate.app` and optionally purges
`~/Library/Application Support/HermesDictate/` (settings + history).

## Privacy

- All audio stays on your Mac.
- Audio is written to `/tmp/hermes-dictate/recording-<timestamp>.wav` during recording.
- The Python venv is at `~/Documents/Hermes.Dictate/venv/`. We do not touch
  the system Python or any other faster-whisper install on the system.
- Microphone access is requested once via macOS's standard TCC prompt.

## Known limits (MVP)

- No auto-paste into the active app. Use **Cmd+V** after transcription.
- No global hotkey. The app is opened from the menu bar.
- No live waveform during recording.
- No re-transcription UI — the history copies text only.
