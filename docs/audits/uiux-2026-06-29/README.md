# MyWhi UI/UX Audit - 2026-06-29

## Scope

Audited the installed desktop app primary daily surfaces:

1. Home / dictation start screen
2. Persistent bottom dictation pill
3. Meeting Mode structure from source and current release behavior
4. Settings structure from source and recent screenshot evidence

Screenshot evidence saved locally in this audit folder and intentionally kept out of the GitHub diff:

- `01-current-window.png`
- `03-after-home-compact.png`
- `05-after-meeting-click.png`

## User Goal

Make MyWhi feel like a daily-use macOS dictation tool: fast to start, calm during recording, clear about what will happen next, and strong enough for meeting transcription without turning the main flow into a settings-heavy control panel.

## Strengths

- The app has a stable sidebar-detail shell that fits macOS.
- The central record button is clear and low-friction.
- The persistent bottom pill makes dictation available outside the Home tab.
- Soniqo and Meeting Mode are now present as separate concepts instead of being hidden inside WhisperKit settings.

## UX Risks Found

- The empty Home state still read like first-run onboarding, even when the app is intended for daily use.
- The bottom dictation pill could visually collide with long scroll content.
- The Home and sidebar model labels used WhisperKit-era assumptions and could show stale model names when Soniqo is active.
- Meeting Mode presented the pipeline as a form rather than a live meeting cockpit.
- Status and recovery cues were scattered: engine, model, audio source, system audio, and processing state were not visible together.

## Accessibility Risks

- Long scroll surfaces need enough bottom inset so keyboard and pointer users can reach final controls without the floating pill covering them.
- Pipeline toggles need short labels plus supporting text; otherwise VoiceOver and scan reading make the Meeting Mode setup harder to understand.
- State changes during recording and processing should stay visible in text, not only color or waveform motion.

## Changes Applied

- Removed first-run-style Home guidance from the daily default screen.
- Added Home workflow chips for dictation shortcut, insertion mode, and active engine/model.
- Replaced the oversized import button with a compact outline control.
- Updated Home/sidebar/bottom pill copy to show the active backend model and the new Option+Command shortcut.
- Added bottom padding to Home, Meeting Mode, and Settings scroll views.
- Redesigned Meeting Mode as a dark cockpit card with headline state, timer, waveform, audio-source tiles, and compact pipeline controls.
- Kept Settings as the deeper configuration area instead of making the main flow settings-heavy.

## Remaining Manual QA

- Test real microphone permission prompts on a fresh macOS TCC state.
- Test Screen Recording/System Audio permission flow on the first Meeting Mode run.
- Test Option+Command in at least Notes, Safari, Slack/Telegram, and a browser text field.
- Test Meeting Mode with a real video-call app to confirm system audio capture behavior.
