// ClipboardService.swift
// Minimal wrapper around NSPasteboard. We use the general pasteboard so
// the text is available to any app, not just ones bound to a named
// pasteboard.

import AppKit

final class ClipboardService {

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func currentText() -> String? {
        pasteboard.string(forType: .string)
    }
}
