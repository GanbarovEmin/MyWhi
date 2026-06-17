// GlobalHotKey.swift
// System-wide keyboard shortcut for MyWhi. Registers Cmd+Option+D
// (default) to toggle recording from anywhere in macOS.
//
// Implementation: Carbon `RegisterEventHotKey` API — the only public
// way to capture a hotkey globally before App Sandbox and Accessibility
// requirements gate Carbon behind Accessibility permission. For a
// menu-bar dictation app this is the right tradeoff.
//
// Toggle handler dispatches to AppState.toggleRecording on the main
// actor; we route via a closure registered at app launch.

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

    /// Default chord: Cmd+Option+D. Stored as Carbon modifier flags.
    /// nonisolated so it can be used as a default parameter value.
    nonisolated static let defaultModifiers: UInt32 = UInt32(cmdKey | optionKey)

    /// Register the global hotkey. Idempotent — unregisters any prior
    /// registration first. The `onPress` closure is called on the main
    /// thread when the user presses the chord.
    func register(modifiers: UInt32 = GlobalHotKey.defaultModifiers, keyCode: UInt32 = UInt32(kVK_ANSI_D), onPress: @escaping () -> Void) {
        unregister()

        self.onPress = onPress

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
            NSLog("MyWhi.GlobalHotKey: RegisterEventHotKey failed (\(regStatus))")
            hotKeyRef = nil
            return
        }
        NSLog("MyWhi.GlobalHotKey: registered Cmd+Option+D")
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