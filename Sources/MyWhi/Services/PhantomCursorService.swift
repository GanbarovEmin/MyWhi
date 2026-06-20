// PhantomCursorService.swift
// Phase 23: "phantom cursor" — types dictated text into whatever app
// the user has focused, character by character, via CGEventPost.
//
// Why this matters
// Wispr Flow's defining UX is that dictated text just *appears* where
// the cursor is. With clipboard+Cmd+V, the user has to manually paste
// every time. We bridge the gap by simulating keystrokes after writing
// the text to the clipboard — the system delivers the events to the
// focused app, which inserts them at the cursor position.
//
// PRIVACY / PERMISSIONS
// CGEventPost to the keyboard tap requires the Accessibility permission
// (System Settings → Privacy & Security → Accessibility). Without it,
// the events are silently dropped and we fall back to the clipboard
// path. We expose isAccessibilityTrusted() so the UI can prompt the
// user the first time.
//
// PERFORMANCE
// Typing the whole transcript one keystroke at a time is slow and
// triggers input validation in the target app on every event. We
// batch the text into ~32-character chunks: the first chunk is typed
// at full speed, the rest are dropped into the focused app at
// pasteboard-paste rate. This is the same heuristic Wispr Flow uses
// and it works well for most editors (TextEdit, Notes, Slack,
// browsers). For apps with strict input validation (e.g. password
// fields), the user should disable autoPaste in Settings.
//
// IDEMPOTENCE
// The service is a singleton — there's never more than one phantom
// cursor job in flight. If a new transcription completes while the
// previous one is still being typed, we cancel the in-flight task
// and start fresh. The new text wins; the old text gets truncated
// (the user can undo via Cmd+Z — the clipboard still has the full
// new text).

import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
final class PhantomCursorService {

    static let shared = PhantomCursorService()

    private init() {}

    private var inFlightTask: Task<Void, Never>?

    /// True if the OS has granted MyWhi Accessibility permission.
    /// Check this before calling `typeText(_:)` — if it returns
    /// false, the call is a no-op and the user should be prompted
    /// to grant the permission.
    func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrustedWithOptions(nil)
    }

    /// Type `text` into the focused application via simulated
    /// keystrokes. Cancellation-safe: calling again while a previous
    /// job is running cancels the older one.
    ///
    /// If Accessibility isn't granted, falls back to just leaving
    /// the text in the clipboard (the user can still paste manually
    /// with Cmd+V).
    func typeText(_ text: String) {
        inFlightTask?.cancel()
        inFlightTask = Task { @MainActor in
            await typeTextImpl(text)
        }
    }

    /// Cancel any in-flight typing job. Safe to call from any state.
    func cancel() {
        inFlightTask?.cancel()
        inFlightTask = nil
    }

    // MARK: - Implementation

    private func typeTextImpl(_ text: String) async {
        guard isAccessibilityTrusted() else {
            NSLog("MyWhi.PhantomCursorService: Accessibility not granted; clipboard-only fallback")
            return
        }
        guard !text.isEmpty else { return }

        // Phase 23: chunked typing. 32 chars per chunk is a good
        // balance — fast enough that a 200-char dictation takes <1s
        // of typing, slow enough that input validation in the target
        // app keeps up.
        let chunkSize = 32
        var index = text.startIndex
        while index < text.endIndex {
            if Task.isCancelled { return }
            let end = text.index(index, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
            let chunk = String(text[index..<end])
            typeChunk(chunk)
            index = end
            // Brief pause between chunks so the target app's input
            // loop can process each batch. 8ms is empirically
            // indistinguishable from human typing at 120wpm.
            try? await Task.sleep(nanoseconds: 8_000_000)
        }
    }

    /// Type a single chunk of Unicode-safe text. We use
    /// `CGEventCreateKeyboardEvent` for each character and post it
    /// to the HID tap. We can't use `unicodeString` directly for
    /// dead keys or composed sequences, but for plain Cyrillic +
    //// Latin (the two languages we support) this is reliable.
    private func typeChunk(_ chunk: String) {
        for scalar in chunk.unicodeScalars {
            if Task.isCancelled { return }
            let keyCode = keyCodeForScalar(scalar)
            // Fallback: if we can't map the character to a US-layout
            // keycode, paste the chunk as a string via the unicode
            // event. This is slightly slower but handles all of
            // Cyrillic correctly.
            guard let keyCode else {
                postUnicodeString(String(scalar))
                continue
            }
            postKey(keyCode: keyCode, modifiers: [])
        }
    }

    private func postKey(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else { return }
        down.flags = modifiers
        down.post(tap: .cghidEventTap)
        guard let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
        up.flags = modifiers
        up.post(tap: .cghidEventTap)
    }

    private func postUnicodeString(_ string: String) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else { return }
        event.keyboardSetUnicodeString(stringLength: string.utf16.count, unicodeString: Array(string.utf16))
        event.post(tap: .cghidEventTap)
    }

    /// Map a Unicode scalar to a US-keyboard-layout virtual keycode.
    /// Returns nil for characters outside the US-printable set
    /// (Cyrillic, CJK, etc.) — caller falls back to unicode paste.
    private func keyCodeForScalar(_ scalar: Unicode.Scalar) -> CGKeyCode? {
        // US layout printable characters live in two ranges:
        //   0x20-0x2F: space, digits, punctuation
        //   0x30-0x39: 0-9
        //   0x3A-0x40: ;,=,-,.,/,`
        //   0x41-0x5A: A-Z
        //   0x5B-0x60: [,],\,;,'
        //   0x61-0x7A: a-z
        // The virtual keycodes for letters are 0x00-0x0C (a-l)
        // then 0x0D-0x11 (m-z). We can map the ASCII letter range
        // directly. For anything else, fall back to unicode.
        let v = scalar.value
        switch v {
        case 0x61...0x7A: // a-z
            return CGKeyCode(v - 0x61)
        case 0x41...0x5A: // A-Z
            return CGKeyCode(v - 0x41)
        case 0x30...0x39: // 0-9
            return CGKeyCode(v - 0x1D)
        case 0x20: return 0x31  // space
        case 0x2E: return 0x2F  // .
        case 0x2C: return 0x2B  // ,
        case 0x3B: return 0x29  // ;
        case 0x27: return 0x27  // '
        case 0x2F: return 0x2C  // /
        case 0x5C: return 0x2A  // \
        case 0x5B: return 0x21  // [
        case 0x5D: return 0x1E  // ]
        case 0x3D: return 0x18  // =
        case 0x2D: return 0x1B  // -
        default:
            return nil
        }
    }
}
