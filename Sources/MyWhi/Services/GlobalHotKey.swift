// GlobalHotKey.swift
// System-wide keyboard shortcut for MyWhi. Registers Cmd+Option+D
// (default) to toggle recording from anywhere in macOS.
//
// Implementation: Carbon `RegisterEventHotKey` API — the only public
// way to capture a hotkey globally before App Sandbox and Accessibility
// requirements gate Carbon behind Accessibility permission. For a
// menu-bar dictation app this is the right tradeoff.
//
// Phase 6.3 — runtime configuration
// The hotkey's modifier flags and key code are now stored in
// AppSettings. We register on init, but the user can change the
// chord in Settings. AppContainer calls `reregister(modifiers:
// keyCode:)` after the user saves a new chord.

import Foundation
import Carbon.HIToolbox

@MainActor
final class GlobalHotKey {

    /// Currently-registered hot key reference. nil if not registered.
    private var hotKeyRef: EventHotKeyRef?

    /// Callback fired when the hot key is pressed.
    private var onPress: (() -> Void)?

    /// The hot key ID — arbitrary, but must be unique within the app.
    private static let hotKeyID: UInt32 = 0x4D57_684B  // "MWhK"

    /// Current registered modifier flags.
    private(set) var currentModifiers: UInt32 = UInt32(cmdKey | optionKey)

    /// Current registered virtual key code.
    private(set) var currentKeyCode: UInt32 = 0x02   // kVK_ANSI_D

    /// nonisolated so it can be used as a default parameter value.
    nonisolated static let defaultModifiers: UInt32 = UInt32(cmdKey | optionKey)
    nonisolated static let defaultKeyCode: UInt32 = 0x02

    /// Apply the user's saved settings before the first register() call.
    /// Used at app launch to seed the manager with the persisted chord.
    func applySettings(_ modifiers: UInt32, _ keyCode: UInt32) {
        currentModifiers = modifiers
        currentKeyCode = keyCode
    }

    /// Register the global hotkey with default values. Idempotent.
    func register(onPress: @escaping () -> Void) {
        register(
            modifiers: currentModifiers,
            keyCode: currentKeyCode,
            onPress: onPress
        )
    }

    /// Register the global hotkey with explicit values, or re-register
    /// with new values if already registered. Unregisters any prior
    /// registration first.
    func register(modifiers: UInt32, keyCode: UInt32, onPress: @escaping () -> Void) {
        unregister()

        self.onPress = onPress
        self.currentModifiers = modifiers
        self.currentKeyCode = keyCode

        // Install the Carbon event handler (only once).
        let handler: EventHandlerUPP = { _, eventRef, _ in
            guard let eventRef else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .mywhiHotKeyPressed, object: nil)
            }
            return noErr
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            handler,
            1,
            &eventType,
            nil,
            nil
        )

        guard installStatus == noErr else {
            NSLog("MyWhi.GlobalHotKey: InstallEventHandler failed (\(installStatus))")
            return
        }

        let hotKeyID = EventHotKeyID(signature: OSType(GlobalHotKey.hotKeyID), id: 1)
        let regStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        if regStatus != noErr {
            NSLog("MyWhi.GlobalHotKey: RegisterEventHotKey failed (\(regStatus)) for mods=\(modifiers) key=\(keyCode)")
            hotKeyRef = nil
            return
        }
        NSLog("MyWhi.GlobalHotKey: registered mods=\(modifiers) key=\(keyCode)")
    }

    /// Re-register with new values. Used by Settings when the user
    /// customizes the hotkey.
    func reregister(modifiers: UInt32, keyCode: UInt32) {
        guard let existingOnPress = onPress else {
            NSLog("MyWhi.GlobalHotKey: reregister() called before register(); ignored")
            return
        }
        register(modifiers: modifiers, keyCode: keyCode, onPress: existingOnPress)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        onPress = nil
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }
}

extension Notification.Name {
    /// Posted by GlobalHotKey when the registered chord is pressed.
    /// AppContainer listens and dispatches to AppState.toggleRecording.
    static let mywhiHotKeyPressed = Notification.Name("MyWhi.hotKeyPressed")
}