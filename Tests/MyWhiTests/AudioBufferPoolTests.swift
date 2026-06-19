// AudioBufferPoolTests.swift
// Phase 12 — verifies that AudioRecorder's pool semantics work:
//   1. dropBufferPool() is safe to call before any recording starts.
//   2. resetLiveBuffer() is idempotent (safe to call repeatedly).
//
// We don't run a real recording here (that would need a microphone
// permission dance), but we exercise the public API surface that
// the pool sits behind.

import XCTest
@testable import MyWhi

final class AudioBufferPoolTests: XCTestCase {

    /// Phase 12: dropBufferPool must be safe to call multiple times
    /// and on a recorder that never recorded. It only nils out the
    /// pool — no side effects beyond that.
    @MainActor
    func testDropBufferPoolIsIdempotent() async {
        let recorder = AudioRecorder()
        // No prepare, no recording, no pool — just call drop.
        recorder.dropBufferPool()

        // Wait briefly for the async dropBufferPool to run on fileQueue.
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Call again. Still no crash.
        recorder.dropBufferPool()
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    /// Phase 12: the public pool API matches the lazy-allocation
    /// contract — `resetLiveBuffer` is safe pre-record and idempotent.
    @MainActor
    func testResetLiveBufferIsIdempotent() {
        let recorder = AudioRecorder()
        recorder.resetLiveBuffer()
        recorder.resetLiveBuffer()
        // No crash, no assertion — purely a no-op twice in a row.
        XCTAssertTrue(true)
    }

    /// Phase 12: takeLiveSnapshot on a recorder that hasn't recorded
    /// must return an empty buffer (not crash, not return stale data).
    @MainActor
    func testTakeLiveSnapshotBeforeRecording() {
        let recorder = AudioRecorder()
        let snap = recorder.takeLiveSnapshot()
        XCTAssertTrue(snap.samples.isEmpty)
        XCTAssertGreaterThan(snap.sampleRate, 0)
    }
}