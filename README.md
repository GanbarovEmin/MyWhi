# MyWhi

A native macOS dictation app. Local-only, on-device Whisper inference, Markdown-vault history. No cloud, no telemetry, no Electron.

> **v2.0-alpha** — full desktop app with sidebar, Markdown vault, GitHub-style Insights, drag-and-drop import, global hotkey. See `.hermes/plans/2026-06-17_135054-mywhi-v2.md` for the design doc.

## What it does

- **Menu bar** — click the mic icon, speak, click again. Text lands in your clipboard.
- **Desktop window** — sidebar with Запись / Scratchpad / Insights / Настройки. Open via menu bar right-click → "Open MyWhi", or `Cmd+Option+D` from anywhere.
- **WhisperKit** primary engine (on-device, 2-5× faster than Python); **faster-whisper** auto-fallback if WhisperKit fails.
- **Markdown vault** — every transcript lives as a real `.md` file in `~/Library/Application Support/MyWhi/vault/YYYY/MM/`.
- **Insights** — total words / chars, current streak, longest streak, GitHub-style 26-week heatmap, 30-day trend line, language breakdown.
- **Drag-and-drop** — drop a `.wav` or `.m4a` file onto the Home tab to transcribe it.
- **Obsidian** — Settings → "Open in Obsidian" opens the vault as an Obsidian vault.

## Quick start

```bash
cd ~/Documents/MyWhi
./build.sh          # builds dist/MyWhi.app (uses existing venv for fallback)
./install.sh        # copies to /Applications/MyWhi.app
open /Applications/MyWhi.app
```

First launch:

1. macOS will ask for **Microphone** permission — allow.
2. Right-click the menu bar icon → **"Open MyWhi"** for the desktop window.
3. (Optional) System Settings → Privacy & Security → **Accessibility** — needed for auto-paste.
4. Press `Cmd+Option+D` from anywhere to start recording.

## Project layout

```
~/Documents/MyWhi/
├── Package.swift               # SwiftPM executable, target MyWhi, macOS 14+
├── Info.plist                  # Bundle metadata (mic, no Dock by default)
├── transcribe.py               # faster-whisper wrapper (fallback engine)
├── build.sh                    # venv + swift build + .app wrap + ad-hoc sign
├── install.sh                  # cp to /Applications/MyWhi.app
├── uninstall.sh                # Remove app + data dir
├── Sources/MyWhi/              # Swift source (44 files)
│   ├── AppContainer.swift           # singleton bridge SwiftUI ↔ AppKit
│   ├── AppState.swift               # @MainActor source of truth
│   ├── AppSceneRouter.swift         # .menuBar ↔ .desktop activation policy
│   ├── AppStatus.swift              # idle|recording|transcribing|copied|error
│   ├── AudioRecorder.swift          # AVAudioRecorder → WAV 16kHz mono
│   ├── ClipboardService.swift       # NSPasteboard
│   ├── HistoryStore.swift           # legacy JSON (one-shot migration)
│   ├── Settings.swift               # AppSettings ObservableObject
│   ├── MainPopoverView.swift        # menu bar popover (380×540)
│   ├── MyWhiApp.swift               # @main, scenes, AppDelegate
│   ├── Notifications.swift          # Notification.Name catalog
│   ├── Design/                      # Cohere-style design system
│   │   ├── HDColor.swift, HDTokens.swift, HDFont.swift
│   │   ├── Components/ (HDButton, HDCard, HDRecordButton,
│   │   │   HDStatTile, HDSidebarItem)
│   │   └── DesignSystemPreview.swift + DesignPreviewWindow.swift
│   ├── Engine/                      # Transcription backends
│   │   ├── Transcriber.swift        # protocol
│   │   ├── WhisperKitTranscriber.swift
│   │   ├── PythonTranscriber.swift  # fallback
│   │   └── EngineManager.swift      # engine chooser + auto-fallback
│   ├── Vault/                       # Markdown vault + index
│   │   ├── VaultPaths.swift, VaultStore.swift, VaultIndex.swift
│   │   ├── TranscriptFrontmatter.swift, TranscriptNote.swift
│   │   └── AggregateStats.swift
│   ├── Stats/                       # Streak + observer
│   │   ├── StreakCalculator.swift
│   │   └── StatsObserver.swift
│   ├── Services/                    # Cross-cutting
│   │   ├── GlobalHotKey.swift       # Carbon Cmd+Option+D
│   │   ├── AutoPasteService.swift   # CGEvent Cmd+V (opt-in)
│   │   └── HapticFeedback.swift     # NSHapticFeedbackManager
│   └── Desktop/                     # Desktop window views
│       ├── DesktopRootView.swift     # NavigationSplitView shell
│       ├── Home/HomeView.swift + OnboardingCard.swift
│       ├── Scratchpad/ScratchpadListView + ScratchpadDetailView +
│       │              ScratchpadSearchField
│       ├── Insights/InsightsView.swift  # heatmap + trend + breakdown
│       └── Settings/SettingsViewDesktop.swift
├── Tests/MyWhiTests/             # 28 tests
│   ├── StreakCalculatorTests.swift
│   ├── VaultStoreTests.swift
│   └── VaultIndexTests.swift
├── Resources/                  # AppIcon.icns
├── venv/                       # Python venv (fallback engine only)
└── dist/MyWhi.app              # Built bundle
```

## Settings

In **Settings** (sidebar of the desktop app):

- **Engine** — WhisperKit (default) / faster-whisper
- **Model** — tiny / base / small / medium / large-v3-turbo / large-v3
- **Language** — Russian / English / Auto-detect
- **Auto copy to clipboard** — ON by default
- **Save to vault** — ON by default
- **Auto-paste into active app** — OFF by default; needs Accessibility permission

Settings persist in `~/Library/Application Support/MyWhi/settings.json`.

## Vault format

```
~/Library/Application Support/MyWhi/vault/
└── 2026/
    └── 06/
        └── 2026-06-17-145812-privet-mir-kak-dela.md
            ---
            id: 8A1B2C3D-...
            created_at: 2026-06-17T14:58:12Z
            language: ru
            model: small
            engine: whisperkit
            duration_seconds: 12.5
            chars: 482
            words: 78
            audio: recording-1721234598.wav
            ---
            Привет мир, как дела...
```

Open in Obsidian, vim, TextEdit, anything that reads Markdown.

## Global hotkey

`Cmd+Option+D` toggles recording from anywhere in macOS.

If it doesn't work, check System Settings → Privacy & Security → Accessibility — MyWhi may need to be added (the first keystroke triggers macOS's normal TCC prompt).

## Migration from v1

If you're upgrading from `Hermes Dictate` v1, the existing `history.json` is migrated automatically on first launch. Each entry becomes a `.md` file in the vault, and `history.json` is backed up as `history.json.migrated-<timestamp>`.

## Privacy

- All audio stays on your Mac.
- WhisperKit inference runs on-device via Core ML / Metal on Apple Silicon.
- Audio is written to `/tmp/hermes-dictate/recording-<timestamp>.wav` during recording.
- The Python venv at `~/Documents/MyWhi/venv/` is **only** used as a fallback engine.
- Microphone access is requested once via macOS's standard TCC prompt.
- Accessibility permission is requested only if you enable auto-paste.

## Known limits

- WhisperKit model download on first use (~250MB for `small`, ~750MB for `medium`).
- Vault index is in-memory; very large vaults (>1000 notes) may benefit from a SQLite FTS5 backend (deferred — current performance is fine for dozens to hundreds of notes).
- `duration_seconds` in frontmatter is currently `0` — Phase 3 will populate it from `AVAudioRecorder`'s recorded duration.
- Live transcription (streaming) is not implemented — recordings are transcribed in batch after stop.

## Uninstall

```bash
./uninstall.sh
```

Removes `/Applications/MyWhi.app` and optionally purges
`~/Library/Application Support/MyWhi/` (settings + vault).

## Development

```bash
swift build -c release           # build
swift test                       # 28 tests
./build.sh                       # build + package + sign
```

The `Sources/MyWhi/Design/DesignPreviewWindow` opens via the right-click menu → "Open Design Preview" — a catalog of every component.