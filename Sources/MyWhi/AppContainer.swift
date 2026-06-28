// AppContainer.swift
// Single source of truth for SwiftUI scene access. AppDelegate owns the
// concrete instance; scenes read it via @EnvironmentObject after MyWhiApp
// injects it at the WindowGroup root.
//
// Singleton because we have exactly one app instance, exactly one NSApp,
// and SwiftUI scenes + AppKit delegate both need access to the same
// AppState (for state) and AppSceneRouter (for policy).

import SwiftUI
import Combine

@MainActor
final class AppContainer: ObservableObject {

    static let shared = AppContainer()

    let appState: AppState
    let sceneRouter: AppSceneRouter
    let globalHotKey: GlobalHotKey
    let updateController: UpdateController
    private var undoMonitor: Any?
    private var commandOptionGlobalMonitor: Any?
    private var commandOptionLocalMonitor: Any?
    private var commandOptionChordDown = false
    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.sceneRouter = AppSceneRouter.shared
        self.updateController = UpdateController()
        self.appState = AppState()
        self.appState.sceneRouter = sceneRouter

        self.globalHotKey = GlobalHotKey()
        // Apply user's saved hotkey to the manager before first register.
        globalHotKey.applySettings(appState.settings.hotkeyModifiers,
                                   appState.settings.hotkeyKeyCode)

        // Do not warm up the microphone on launch. macOS surfaces the
        // permission prompt from recorder.prepare(), so the recorder is
        // prepared lazily from AppState.startRecording() after an
        // explicit user action.

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
        configurePushToTalk(appState.settings.pushToTalkMode)
        appState.settings.$pushToTalkMode
            .removeDuplicates()
            .sink { [weak self] enabled in
                Task { @MainActor [weak self] in
                    self?.configurePushToTalk(enabled)
                }
            }
            .store(in: &cancellables)

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

        // Phase 23: global Cmd+Shift+Z = undo last paste. Uses
        // NSEvent.addGlobalMonitorForEvents (same pattern as the
        // push-to-talk release monitor in GlobalHotKey). Fires
        // UndoService.undo() which restores the snapshotted
        // clipboard content. We do this on the main actor since
        // UndoService is @MainActor.
        undoMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            // Cmd+Shift+Z — keyCode 6 is 'z' on US layout.
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isCmdShift = flags.contains(.command) && flags.contains(.shift)
            guard isCmdShift, event.keyCode == 6 else { return }
            Task { @MainActor in
                _ = UndoService.shared.undo()
            }
        }

        installCommandOptionFallbackHotkey()
    }

    private func configurePushToTalk(_ enabled: Bool) {
        guard enabled else {
            globalHotKey.disablePushToTalk()
            return
        }
        globalHotKey.enablePushToTalk(
            onPress: {},
            onRelease: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.appState.status == .recording {
                        self.appState.stopRecording()
                    }
                }
            }
        )
    }

    private func installCommandOptionFallbackHotkey() {
        commandOptionGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleCommandOptionFallback(event.modifierFlags)
            }
        }

        commandOptionLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleCommandOptionFallback(event.modifierFlags)
            }
            return event
        }
    }

    private func handleCommandOptionFallback(_ flags: NSEvent.ModifierFlags) {
        let isDown = GlobalHotKey.isCommandOptionOnly(flags)
        guard isDown != commandOptionChordDown else { return }
        commandOptionChordDown = isDown

        if isDown {
            if appState.settings.pushToTalkMode {
                if appState.status != .recording {
                    appState.startRecording()
                }
            } else {
                appState.toggleRecording()
            }
        } else if appState.settings.pushToTalkMode, appState.status == .recording {
            appState.stopRecording()
        }
    }

    deinit {
        if let undoMonitor {
            NSEvent.removeMonitor(undoMonitor)
        }
        if let commandOptionGlobalMonitor {
            NSEvent.removeMonitor(commandOptionGlobalMonitor)
        }
        if let commandOptionLocalMonitor {
            NSEvent.removeMonitor(commandOptionLocalMonitor)
        }
    }
}
