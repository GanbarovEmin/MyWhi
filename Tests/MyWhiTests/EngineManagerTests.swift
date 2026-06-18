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
    let lock = NSLock()

    init(name: String) { self.name = name }

    func loadModel(_ modelName: String) async throws {
        lock.lock(); defer { lock.unlock() }
        loadCount += 1
        lastModelRequested = modelName
        if let loadError { throw loadError }
    }

    func transcribe(audioPath: String, model: String, language: String) async throws -> String {
        lock.lock(); defer { lock.unlock() }
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
            "faster-whisper": FakeTranscriber(name: "faster-whisper"),
        ]
        let mgr = EngineManager(pythonPath: "/nonexistent")
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
        fakes["whisperkit"]!.loadCount = 0

        // Different engine → reload on the new engine.
        try await mgr.setEngine("faster-whisper", model: "medium")
        XCTAssertEqual(fakes["faster-whisper"]!.loadCount, 1, "Engine change should trigger reload on the new engine")
        XCTAssertEqual(fakes["whisperkit"]!.loadCount, 0, "Old engine should not be reloaded")
    }

    // MARK: - Fallback flag invalidates cache

    func testSetEngineRetriesAfterFallback() async throws {
        let (mgr, fakes) = makeManager()
        // Seed: first load of whisperkit fails → fallback to faster-whisper.
        fakes["whisperkit"]!.loadError = NSError(domain: "fake", code: 42)
        try await mgr.setEngine("whisperkit", model: "small")
        XCTAssertTrue(mgr.didFallback)
        XCTAssertEqual(fakes["faster-whisper"]!.loadCount, 1, "Fallback should load faster-whisper")
        fakes["faster-whisper"]!.loadCount = 0

        // Now whisperkit can load successfully.
        fakes["whisperkit"]!.loadError = nil

        // Same (faster-whisper, small) with didFallback=true → retry primary.
        try await mgr.setEngine("faster-whisper", model: "small")
        // The retry path is: setEngine("whisperkit"...) but we called
        // with "faster-whisper", so cache check is "fast-w, small" vs
        // "fast-w, small" with didFallback=true → falls through, tries
        // to reload faster-whisper.
        // Wait — that's not quite right. Let me re-read the code.
        //
        // The cache check is:
        //   if name == activeEngineName && model == activeModel && !didFallback
        // So with didFallback=true, the check fails (we WANT to retry).
        // Then it calls makeEngine(name) = makeEngine("faster-whisper")
        // = fakes["faster-whisper"]! and loads it.
        XCTAssertEqual(fakes["faster-whisper"]!.loadCount, 1,
                       "After fallback flag set, next call should reload")
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

    // MARK: - Fallback path

    func testWhisperKitFailureFallsBackToPython() async throws {
        let (mgr, fakes) = makeManager()
        fakes["whisperkit"]!.loadError = NSError(domain: "fake", code: 42)
        fakes["whisperkit"]!.loadCount = 0
        fakes["faster-whisper"]!.loadCount = 0

        try await mgr.setEngine("whisperkit", model: "small")

        XCTAssertTrue(mgr.didFallback, "didFallback should be true after WhisperKit failure")
        XCTAssertGreaterThanOrEqual(fakes["whisperkit"]!.loadCount, 1, "WhisperKit should have been tried")
        XCTAssertEqual(fakes["faster-whisper"]!.loadCount, 1, "Fallback should load faster-whisper")
    }

    func testPythonFailure_doesNotDoubleFallback() async throws {
        let (mgr, fakes) = makeManager()
        fakes["whisperkit"]!.loadError = NSError(domain: "fake", code: 1)
        fakes["faster-whisper"]!.loadError = NSError(domain: "fake", code: 2)

        do {
            try await mgr.setEngine("faster-whisper", model: "small")
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected — Python failed and we can't fall back further.
        }
        XCTAssertFalse(mgr.didFallback, "didFallback should not be set when both engines fail")
    }

    // MARK: - transcribe delegates to active

    func testTranscribeUsesActiveEngine() async throws {
        let (mgr, fakes) = makeManager()
        try await mgr.setEngine("whisperkit", model: "small")
        let text = try await mgr.transcribe(audioPath: "/tmp/fake.wav", model: "small", language: "ru")
        XCTAssertEqual(text, "fake-transcript-whisperkit-small")
        XCTAssertEqual(fakes["whisperkit"]!.transcribeCount, 1)
    }
}