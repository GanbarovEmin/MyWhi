// AppContainer.swift
// Single source of truth for SwiftUI scene access. AppDelegate owns the
// concrete instance; scenes read it via @EnvironmentObject after MyWhiApp
// injects it at the WindowGroup root.
//
// Singleton because we have exactly one app instance, exactly one NSApp,
// and SwiftUI scenes + AppKit delegate both need access to the same
// AppState (for state) and AppSceneRouter (for policy).

import SwiftUI

@MainActor
final class AppContainer: ObservableObject {

    static let shared = AppContainer()

    let appState: AppState
    let sceneRouter: AppSceneRouter
    let globalHotKey: GlobalHotKey

    private init() {
        self.sceneRouter = AppSceneRouter.shared
        self.appState = AppState()
        self.appState.sceneRouter = sceneRouter

        self.globalHotKey = GlobalHotKey()
        // Apply user's saved hotkey to the manager before first register.
        globalHotKey.applySettings(appState.settings.hotkeyModifiers,
                                   appState.settings.hotkeyKeyCode)

        // Phase 6.1: warm up the audio engine for pre-roll. prepare()
        // is async and idempotent — it triggers the mic permission
        // prompt on first call, which is fine because the user
        // expects it when they first try to record.
        Task { @MainActor [weak self] in
            await self?.appState.recorder.prepare()
        }

        // App-menu commands (Phase 5.2) — observers are stored so they
        // don't get deallocated. We forward to the same handlers the
        // global hotkey and the menu bar popover use.
        NotificationCenter.default.addObserver(
            forName: .mywhiToggleRecording,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.appState.toggleRecording()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .mywhiDiscardRecording,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.appState.discardRecording()
            }
        }

        // Wire hot key → toggle recording. We re-register with the
        // current default chord; users can change it later.
        NotificationCenter.default.addObserver(
            forName: .mywhiHotKeyPressed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Phase 13: push-to-talk mode. The Carbon press event
                // is always a "start" signal in this mode; the
                // release monitor in GlobalHotKey fires the stop.
                if self.appState.settings.pushToTalkMode {
                    // Don't double-start if the user accidentally
                    // taps the key without holding.
                    if self.appState.status != .recording {
                        self.appState.startRecording()
                    }
                } else {
                    self.appState.toggleRecording()
                }
            }
        }
        globalHotKey.register { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.appState.settings.pushToTalkMode {
                    if self.appState.status != .recording {
                        self.appState.startRecording()
                    }
                } else {
                    self.appState.toggleRecording()
                }
            }
        }

        // Phase 13: in push-to-talk mode, install the release monitor
        // that fires `stopRecording` when the user releases the chord.
        // The release handler is idempotent — if the recorder was
        // already stopped (e.g. due to Esc), it stays stopped.
        globalHotKey.enablePushToTalk(
            onPress: { [weak self] in
                // Press is handled above via the .mywhiHotKeyPressed
                // notification path, so this is a no-op. We keep the
                // signature so the API matches; a future implementation
                // could route the press here directly instead of via a
                // notification.
            },
            onRelease: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.appState.status == .recording {
                        self.appState.stopRecording()
                    }
                }
            }
        )
        if !appState.settings.pushToTalkMode {
            globalHotKey.disablePushToTalk()
        }

        // Observe hotkey settings changes and re-register the hotkey
        // with the new chord. Combines the existing settings.publisher
        // chain in AppState — we add ours on top.
        NotificationCenter.default.addObserver(
            forName: .mywhiHotkeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let info = note.userInfo,
                  let mods = info["modifiers"] as? UInt32,
                  let key = info["keyCode"] as? UInt32
            else { return }
            Task { @MainActor [weak self] in
                self?.globalHotKey.reregister(modifiers: mods, keyCode: key)
            }
        }
    }
}