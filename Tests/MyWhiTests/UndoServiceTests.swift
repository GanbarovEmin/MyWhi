// UndoServiceTests.swift
// Phase 23 — exercises the one-shot undo behavior: snapshot, restore,
// no double-undo, empty-input no-op.

import XCTest
@testable import MyWhi

@MainActor
final class UndoServiceTests: XCTestCase {

    /// Reset the service between tests so state doesn't leak.
    override func setUp() async throws {
        UndoService.shared._testSetSnapshot(nil)
    }

    /// Basic flow: snapshot, copy something else, undo restores.
    func testSnapshotAndUndoRoundTrip() {
        let svc = UndoService.shared
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("old-text", forType: .string)

        svc.snapshot()  // captures "old-text"
        pasteboard.setString("new-text", forType: .string)

        let restored = svc.undo()
        XCTAssertTrue(restored)
        XCTAssertEqual(pasteboard.string(forType: .string), "old-text",
                       "undo() should restore the snapshotted clipboard content")
    }

    /// Double-undo: only restores once. Second call is a no-op.
    func testDoubleUndoOnlyRestoresOnce() {
        let svc = UndoService.shared
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("first", forType: .string)

        svc.snapshot()
        pasteboard.setString("second", forType: .string)

        XCTAssertTrue(svc.undo())
        XCTAssertEqual(pasteboard.string(forType: .string), "first")

        // Second undo: snapshot is cleared → returns false, no
        // clipboard mutation.
        XCTAssertFalse(svc.undo(),
                       "Double-undo should be a no-op; snapshot is one-shot")
        XCTAssertEqual(pasteboard.string(forType: .string), "first",
                       "Second undo must not clobber the clipboard")
    }

    /// Empty clipboard: snapshot is a no-op. The user can still
    /// dictate but has nothing to roll back to.
    func testSnapshotOnEmptyClipboardIsNoOp() {
        let svc = UndoService.shared
        svc._testSetSnapshot(nil)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        svc.snapshot()
        XCTAssertNil(svc.lastSnapshot,
                     "Empty clipboard must not be snapshotted — there's nothing to restore to")
    }

    /// canUndo reflects snapshot state.
    func testCanUndoReflectsSnapshotState() {
        let svc = UndoService.shared
        svc._testSetSnapshot(nil)
        XCTAssertFalse(svc.canUndo)

        svc._testSetSnapshot("anything")
        XCTAssertTrue(svc.canUndo)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        _ = svc.undo()
        XCTAssertFalse(svc.canUndo, "canUndo must flip false after a successful undo")
    }
}
