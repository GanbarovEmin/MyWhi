# MyWhi

Local-first macOS dictation powered by WhisperKit. Speak, get text, keep the history as Markdown. No cloud transcription, no Electron, no telemetry.

![MyWhi recording screen](docs/assets/mywhi-record.png)

## Highlights

- Native macOS menu-bar and desktop app.
- On-device WhisperKit transcription through Core ML / Metal.
- Global hotkey: `Command` + `Option` + `D`.
- Markdown vault in `~/Library/Application Support/MyWhi/vault/`.
- Scratchpad, search, insights, streaks, heatmap, and language breakdown.
- Russian / English UI follows the macOS system language.
- Downloaded WhisperKit models stay cached across app reinstalls and are shown as downloaded in Settings.
- Sparkle updates through GitHub Releases.

![MyWhi settings screen](docs/assets/mywhi-settings.png)

## Install

Download the latest DMG from [GitHub Releases](https://github.com/GanbarovEmin/MyWhi/releases).

1. Open `MyWhi-3.9.0.dmg`.
2. Drag `MyWhi.app` to `Applications`.
3. Open MyWhi from `/Applications`.
4. Allow Microphone access when macOS asks.
5. Optional: enable Accessibility permission if you want auto-paste into the active app.

The first public preview is ad-hoc signed, not Developer ID notarized. macOS Gatekeeper may require right-clicking the app and choosing **Open** on first launch.

## Updates

MyWhi uses Sparkle for app updates. Use either:

- right-click the menu-bar icon and choose **Check for Updates...**
- open **Settings** and click **Check for Updates**

Updates are read from the GitHub-hosted `appcast.xml` in this repository and download release DMGs from GitHub Releases.

## Privacy

- Audio stays on this Mac.
- WhisperKit inference runs locally.
- No cloud transcription service is called by MyWhi.
- Recordings are temporary WAV files under `/tmp/mywhi/recordings/`.
- Transcripts are saved as Markdown only when history saving is enabled.
- Accessibility permission is used only for optional paste/typing behavior.

## Build From Source

Requirements:

- macOS 14+
- Xcode command line tools
- Swift Package Manager

```bash
git clone https://github.com/GanbarovEmin/MyWhi.git
cd MyWhi
swift test
./build-dmg.sh --install
open /Applications/MyWhi.app
```

Build outputs:

- app bundle: `dist/MyWhi.app`
- DMG: `dist/MyWhi-3.9.0.dmg`

## Release Workflow

```bash
swift test
./build-dmg.sh --install
codesign --verify --verbose=2 dist/MyWhi.app
hdiutil verify dist/MyWhi-3.9.0.dmg
```

Sparkle appcast signing uses an EdDSA private key stored in the local macOS Keychain. The public key is committed in `Info.plist` as `SUPublicEDKey`; the private key must not be committed.

Public distribution still needs Developer ID signing and notarization for a polished Gatekeeper experience.

## Project Layout

```text
Sources/MyWhi/
  MyWhiApp.swift                 App entrypoint and menu-bar integration
  AppState.swift                 Main app state and recording flow
  Engine/WhisperKitTranscriber   WhisperKit model loading and transcription
  Desktop/                       Desktop shell, Home, Scratchpad, Insights, Settings
  Services/UpdateController.swift Sparkle update controller
Resources/
  AppIcon.icns
  en.lproj, ru.lproj             Localized UI strings
docs/
  assets/                        README screenshots
  releases/                      Release notes
```

## License

MIT. See [LICENSE](LICENSE).
