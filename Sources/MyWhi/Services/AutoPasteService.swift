// AutoPasteService.swift
// Simulates Cmd+V into the previously-active application after a
// successful transcription. Opt-in via Settings.autoPaste.
//
// Requires Accessibility permission in System Settings → Privacy & Security
// → Accessibility. If not granted, the CGEvent post silently no-ops.

import AppKit
import ApplicationServices

@MainActor
enum AutoPasteService {

    /// Simulate Cmd+V. Safe to call repeatedly — AXIsProcessTrustedWithOptions
    /// is checked on every call so a freshly-granted permission takes effect
    /// without restarting the app.
    static func pasteFromClipboard() {
        let trusted = AXIsProcessTrustedWithOptions(nil)
        guard trusted else {
            NSLog("MyWhi.AutoPaste: Accessibility permission required; Cmd+V not simulated.")
            return
        }

        // Slight delay so the source app regains focus after the
        // popover/window dismisses. 80ms is enough for Finder, TextEdit,
        // browsers, etc.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            postCmdV()
        }
    }

    private static func postCmdV() {
        // Key code 9 = 'v' on US layout. If the user has a different
        // keyboard layout the V might land elsewhere, but for the common
        // case (RU/EN) this is correct.
        let vKeyCode: CGKeyCode = 9

        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true) else { return }
        down.flags = .maskCommand

        guard let up = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) else { return }
        up.flags = .maskCommand

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Synchronous variant used by tests.
    static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrustedWithOptions(nil)
    }
}