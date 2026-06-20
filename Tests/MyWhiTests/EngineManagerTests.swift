// EngineManagerTests.swift
// Tests for the (name, model) cache in EngineManager. We inject fake
// Transcribers via the `makeEngine` factory so tests don't depend on
// WhisperKit / Python.

import XCTest
@testable import MyWhi

/// A test Transcriber that counts how many times loadModel was called.
final class FakeTranscriber: Transcriber, @unchecked Sendable {
    let name: String
    var loadCount: Int = 0
    /// If non-nil, loadModel will throw this error.
    var loadError: Error?
    /// If non-nil, transcribe will throw this error.
    var transcribeError: Error?
    var lastModelRequested: String?
    var transcribeCount: Int = 0
    /// Phase 22: how many times unloadModel was called. The real
    /// WhisperKitTranscriber nil's out its `pipe` and model cache;
    /// we mirror that here so EngineManager-level reload tests can
    /// assert the unload was called before the new model was loaded.
    var unloadCount: Int = 0

    init(name: String) { self.name = name }

    func loadModel(_ modelName: String) async throws {
        loadCount += 1
        lastModelRequested = modelName
        if let loadError { throw loadError }
    }

    /// Phase 22: explicit teardown. The real implementation nils out
    /// pipe / loadedModelName / prompt-token caches. The fake just
    /// bumps a counter so tests can verify it was called.
    func unloadModel() {
        unloadCount += 1
    }

    func transcribe(audioPath: String, model: String, language: String) async throws -> String {
        transcribeCount += 1
        if let transcribeError { throw transcribeError }
        return "fake-transcript-\(name)-\(model)"
    }
}

@MainActor
final class EngineManagerTests: XCTestCase {

    /// Build a manager whose `makeEngine` returns Fakes — the same
    /// instance per code, so loadCount accumulates across calls.
    private func makeManager() -> (EngineManager, [String: FakeTranscriber]) {
        let fakes: [String: FakeTranscriber] = [
            "whisperkit":    FakeTranscriber(name: "whisperkit"),
        ]
        let mgr = EngineManager()
        mgr.makeEngine = { code in fakes[code] ?? FakeTranscriber(name: "unknown") }
        return (mgr, fakes)
    }

    // MARK: - Cache hit

    func testSetEngineSameNameAndModel_skipsReload() async throws {
        let (mgr, fakes) = makeManager()
        // Seed the cache so the next "same" call should be a hit.
        try await mgr.setEngine("whisperkit", model: "small")
        XCTAssertEqual(fakes["whisperkit"]!.loadCount, 1)
        fakes["whisperkit"]!.loadCount = 0  // reset for assertion clarity

        // Same (name, model) → no reload.
        try await mgr.setEngine("whisperkit", model: "small")
        XCTAssertEqual(fakes["whisperkit"]!.loadCount, 0, "Cache hit should not call loadModel")

        // Different model → reload.
        try await mgr.setEngine("whisperkit", model: "medium")
        XCTAssertEqual(fakes["whisperkit"]!.loadCount, 1, "Model change should trigger reload")
    }

    // MARK: - Load failure (no fallback in v2.0)

    func testWhisperKitFailurePropagatesError() async throws {
        // v2.0: there's no faster-whisper fallback. If WhisperKit
        // fails to load, the error is surfaced so the UI can show
        // it. (Previously we'd silently fall back to Python.)
        let (mgr, fakes) = makeManager()
        fakes["whisperkit"]!.loadError = NSError(domain: "fake", code: 42)
        fakes["whisperkit"]!.loadCount = 0

        do {
            try await mgr.setEngine("whisperkit", model: "small")
            XCTFail("Expected error to be thrown — no fallback engine exists")
        } catch {
            // Expected.
        }
        XCTAssertGreaterThanOrEqual(fakes["whisperkit"]!.loadCount, 1)
        XCTAssertFalse(mgr.didFallback, "didFallback should never be true (no fallback engine)")
    }

    // MARK: - isLoading state

    func testIsLoadingTransitions() async throws {
        let (mgr, _) = makeManager()
        var observed: [Bool] = [mgr.isLoading]

        let cancellable = mgr.$isLoading.sink { value in
            observed.append(value)
        }
        defer { cancellable.cancel() }

        try await mgr.setEngine("whisperkit", model: "small")

        // Give Combine a moment to flush.
        try? await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertTrue(observed.contains(true), "isLoading should flip to true during reload")
        XCTAssertEqual(observed.last, false, "isLoading should return to false after reload")
    }

    // MARK: - transcribe delegates to active

    func testTranscribeUsesActiveEngine() async throws {
        let (mgr, fakes) = makeManager()
        try await mgr.setEngine("whisperkit", model: "small")
        let text = try await mgr.transcribe(audioPath: "/tmp/fake.wav", model: "small", language: "ru")
        XCTAssertEqual(text, "fake-transcript-whisperkit-small")
        XCTAssertEqual(fakes["whisperkit"]!.transcribeCount, 1)
    }

    // MARK: - Phase 22: unload on model change

    /// Switching from one model to another must unload the previous
    /// engine's model before loading the new one. This is the
    /// memory-leak fix: without it, switching small→medium→small
    /// accumulates Core ML model objects and eventually trips
    /// EXC_RESOURCE.
    func testSetEngineUnloadsPreviousModel() async throws {
        let (mgr, fakes) = makeManager()
        // First load — no unload expected (cache was empty stub).
        try await mgr.setEngine("whisperkit", model: "small")
        XCTAssertEqual(fakes["whisperkit"]!.unloadCount, 0,
                       "First load should not call unload — there's nothing to unload yet")

        // Same model — cache hit, no unload.
        try await mgr.setEngine("whisperkit", model: "small")
        XCTAssertEqual(fakes["whisperkit"]!.unloadCount, 0,
                       "Cache hit should not call unload")

        // Different model — must unload first.
        try await mgr.setEngine("whisperkit", model: "medium")
        XCTAssertEqual(fakes["whisperkit"]!.unloadCount, 1,
                       "Model change must call unloadModel() on the outgoing engine")
    }
}