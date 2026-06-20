// UndoService.swift
// Phase 23: global "undo last paste" hotkey. When the user dictates
// something and it's pasted into the active editor, Cmd+Shift+Z (or
// the configured chord) restores the previous clipboard content.
//
// The clipboard already has the dictated text — restoring it is one
// pasteboard write. The user can then re-paste with Cmd+V if they
// want the text back at the cursor, or just leave the old text.
//
// We deliberately do NOT try to "remove" the pasted text from the
// active app. That's a much harder problem (apps track their own
// undo stacks, cursor positions, etc.) and our restoration of the
// clipboard means the user can hit Cmd+Z in the target app for
// proper text-level undo.
//
// PERSISTENCE
// Only the most recent paste is remembered. If the user pastes
// twice, only the second can be undone. This matches the "undo last
// action" mental model and keeps the storage trivial.
//
// TESTING
// The snapshot/undo APIs are public so unit tests can drive the
// service without going through the clipboard. The clipboard write
// path is the only side effect.

import AppKit

@MainActor
final class UndoService {

    static let shared = UndoService()

    private init() {}

    /// Snapshot of the previous clipboard content. nil means "nothing
    /// to undo". Set by `snapshot()`; cleared by `undo()`.
    private(set) var lastSnapshot: String?

    /// Record the current clipboard content. Idempotent — calling
    /// twice in a row replaces the first snapshot with the new
    /// (current) value.
    func snapshot() {
        let current = ClipboardService().currentText() ?? ""
        // Avoid snapshotting an empty clipboard — that's the
        // common case on first launch and snapshotting it would
        // let the user "undo" into nothing.
        guard !current.isEmpty else { return }
        lastSnapshot = current
    }

    /// Restore the snapshotted clipboard content. Returns true if
    /// a restore happened, false if there was nothing to undo.
    /// One-shot: a second call returns false (no double-undo).
    @discardableResult
    func undo() -> Bool {
        guard let snapshot = lastSnapshot else { return false }
        ClipboardService().copy(snapshot)
        lastSnapshot = nil
        return true
    }

    /// True if there's a snapshot to restore.
    var canUndo: Bool { lastSnapshot != nil }

    /// Test-only hook: seed the snapshot directly without going
    /// through the clipboard. Used by UndoServiceTests to assert
    /// canUndo / undo() behavior in isolation.
    func _testSetSnapshot(_ value: String?) {
        lastSnapshot = value
    }
}
