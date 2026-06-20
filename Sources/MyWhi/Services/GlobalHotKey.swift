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
//
// Phase 13 — push-to-talk mode
// When `pushToTalkMode` is enabled in AppSettings, the Carbon press
// handler starts recording (instead of toggling). A global NSEvent
// monitor watches for the corresponding key release and stops the
// recorder. The monitor only fires for events NOT consumed by the
// focused app — meaning MyWhi's own TextEditor (e.g. the inline
// editor) can still receive keystrokes for editing without
// accidentally ending the recording session.

import Foundation
import AppKit
import Carbon.HIToolbox

@MainActor
final class GlobalHotKey {

    /// Currently-registered hot key reference. nil if not registered.
    private var hotKeyRef: EventHotKeyRef?

    /// Carbon event handler installed once for this manager. Re-registering
    /// the hotkey must not stack duplicate handlers.
    private var eventHandlerRef: EventHandlerRef?

    /// Callback fired when the hot key is pressed.
    private var onPress: (() -> Void)?

    /// Callback fired when the hot key is released (push-to-talk only).
    private var onRelease: (() -> Void)?

    /// The hot key ID — arbitrary, but must be unique within the app.
    private static let hotKeyID: UInt32 = 0x4D57_684B  // "MWhK"

    /// Current registered modifier flags.
    private(set) var currentModifiers: UInt32 = UInt32(cmdKey | optionKey)

    /// Current registered virtual key code.
    private(set) var currentKeyCode: UInt32 = 0x02   // kVK_ANSI_D

    /// nonisolated so it can be used as a default parameter value.
    nonisolated static let defaultModifiers: UInt32 = UInt32(cmdKey | optionKey)
    nonisolated static let defaultKeyCode: UInt32 = 0x02

    /// Phase 13: when true, the press handler calls `onPress` (start
    /// recording) and the release monitor calls `onRelease` (stop).
    /// When false, both callbacks fire on press (toggle behavior).
    private(set) var pushToTalkEnabled: Bool = false

    /// Phase 13: handle into the NSEvent global monitor installed
    /// when push-to-talk is active. nil when push-to-talk is off.
    private var releaseMonitor: Any?

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
        unregisterHotKey()
        removeReleaseMonitor()

        self.onPress = onPress
        self.currentModifiers = modifiers
        self.currentKeyCode = keyCode

        guard installEventHandlerIfNeeded() else { return }

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
        // Re-apply push-to-talk if it's still on.
        if pushToTalkEnabled {
            installReleaseMonitorIfNeeded()
        }
    }

    func unregister() {
        unregisterHotKey()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        onPress = nil
        onRelease = nil
        pushToTalkEnabled = false
        removeReleaseMonitor()
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installEventHandlerIfNeeded() -> Bool {
        if eventHandlerRef != nil { return true }

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
            guard hotKeyID.signature == OSType(GlobalHotKey.hotKeyID) else {
                return OSStatus(eventNotHandledErr)
            }

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .mywhiHotKeyPressed, object: nil)
            }
            return noErr
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        var installedHandler: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            handler,
            1,
            &eventType,
            nil,
            &installedHandler
        )

        guard installStatus == noErr, let installedHandler else {
            NSLog("MyWhi.GlobalHotKey: InstallEventHandler failed (\(installStatus))")
            return false
        }
        eventHandlerRef = installedHandler
        return true
    }

    // MARK: - Push-to-talk (Phase 13)

    /// Enable push-to-talk semantics. The press callback will be
    /// called on key-down (instead of toggle) and `onRelease` will be
    /// called when the corresponding key is released.
    ///
    /// `onRelease` is invoked when:
    ///   - The matching key goes up (anywhere in the system), OR
    ///   - The modifier mask no longer matches (user lifted Cmd or
    ///     Option while still holding D).
    ///
    /// Either way, the user's intent is "I'm done dictating", so we
    /// stop the recorder.
    func enablePushToTalk(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        self.pushToTalkEnabled = true
        self.onPress = onPress
        self.onRelease = onRelease
        installReleaseMonitorIfNeeded()
    }

    /// Disable push-to-talk semantics. Falls back to toggle.
    func disablePushToTalk() {
        self.pushToTalkEnabled = false
        self.onRelease = nil
        removeReleaseMonitor()
    }

    /// Install an NSEvent global monitor that fires `onRelease` when
    /// the registered chord is released. Global monitor only sees
    /// events NOT consumed by the focused app, so this is safe even
    /// with a text editor focused.
    private func installReleaseMonitorIfNeeded() {
        // Tear down any existing monitor first.
        removeReleaseMonitor()

        let targetKey = currentKeyCode
        let targetMods = carbonToCocoaModifiers(currentModifiers)

        // NSEvent mask for our key-down + modifier-up events.
        let mask: NSEvent.EventTypeMask = [.keyUp, .flagsChanged]
        releaseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                self.handleReleaseEvent(event, targetKey: targetKey, targetMods: targetMods)
            }
        }
        NSLog("MyWhi.GlobalHotKey: push-to-talk release monitor installed")
    }

    private func removeReleaseMonitor() {
        if let monitor = releaseMonitor {
            NSEvent.removeMonitor(monitor)
            releaseMonitor = nil
        }
    }

    /// Inspect the event; if it represents the registered chord being
    /// released, fire `onRelease`.
    func handleReleaseEvent(_ event: NSEvent, targetKey: UInt32, targetMods: NSEvent.ModifierFlags) {
        switch event.type {
        case .keyUp:
            // Direct key-up for our hotkey's keyCode.
            if event.keyCode == targetKey {
                onRelease?()
            }
        case .flagsChanged:
            // Modifier flag change. If the user lifted a modifier that
            // was part of our chord (Cmd or Option), they effectively
            // released the hotkey.
            let currentMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if currentMods.intersection(targetMods) != targetMods {
                // User no longer holds the full chord → stop recording.
                onRelease?()
            }
        default:
            break
        }
    }

    /// Test-only hook so unit tests can exercise the event filter
    /// without going through a real NSEvent monitor.
    func test_handleReleaseEvent(_ event: NSEvent, targetKey: UInt32, targetMods: NSEvent.ModifierFlags) {
        handleReleaseEvent(event, targetKey: targetKey, targetMods: targetMods)
    }

    /// Convert Carbon modifier flags to NSEvent.ModifierFlags. Carbon
    /// uses cmdKey/optionKey/shiftKey/controlKey bits; Cocoa uses a
    /// separate OptionSet.
    private func carbonToCocoaModifiers(_ carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbon & UInt32(cmdKey) != 0     { flags.insert(.command) }
        if carbon & UInt32(optionKey) != 0  { flags.insert(.option) }
        if carbon & UInt32(shiftKey) != 0   { flags.insert(.shift) }
        if carbon & UInt32(controlKey) != 0  { flags.insert(.control) }
        return flags
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
