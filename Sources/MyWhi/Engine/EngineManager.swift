// EngineManager.swift
// Owns the active Transcriber. Caches engines by (name, model) so we
// don't pay the 6-7s model-init cost on every recording — the cache
// only reloads when the user actually changes engine or model size.
//
// Also handles the WhisperKit → faster-whisper fallback when the
// primary engine fails to load.

import Foundation
import Combine

@MainActor
final class EngineManager: ObservableObject {

    /// Currently active engine. Re-created only when (name, model) change.
    private(set) var active: Transcriber

    /// Raw engine code for the active engine, e.g. "whisperkit".
    @Published private(set) var activeEngineName: String

    /// Model name currently loaded into the active engine, e.g. "small".
    @Published private(set) var activeModel: String

    /// Human-readable name shown in the UI, e.g. "WhisperKit".
    @Published private(set) var displayName: String

    /// True when we fell back from WhisperKit → faster-whisper after
    /// a load error. Surfaces a warning in the UI.
    @Published private(set) var didFallback: Bool = false

    /// True while a model is being loaded (downloaded, compiled, warmed).
    /// Settings can use this to show a progress bar.
    @Published private(set) var isLoading: Bool = false

    private let pythonPath: String

    /// Factory closure: given an engine code, return a fresh Transcriber.
    /// Default builds WhisperKitTranscriber / PythonTranscriber. Tests
    /// override this to inject fakes.
    var makeEngine: (String) -> Transcriber

    init(pythonPath: String) {
        self.pythonPath = pythonPath
        self.makeEngine = { code in
            switch code {
            case "whisperkit":    return WhisperKitTranscriber()
            case "faster-whisper": return PythonTranscriber(pythonPath: pythonPath)
            default:
                return UnloadedTranscriber()
            }
        }
        // No engine preloaded — setEngine() will be called by preload.
        // A no-op stub so `active.transcribe(...)` doesn't crash if a
        // recording races the preload (it'll just throw, the caller
        // catches it).
        self.active = UnloadedTranscriber()
        self.activeEngineName = ""
        self.activeModel = ""
        self.displayName = "Loading…"
    }

    /// Swap to a different engine (WhisperKit or Python) and load the model.
    /// No-op if the requested (name, model) pair matches the active one AND
    /// we didn't previously fall back.
    func setEngine(_ name: String, model: String) async throws {
        let startTime = Date()
        NSLog("MyWhi.EngineManager: setEngine(name=\(name), model=\(model)) — active=\(activeEngineName)/\(activeModel)")

        // Cache hit: same engine + same model, and we didn't fall back
        // (fallback is one-shot — next call should retry the primary).
        if name == activeEngineName && model == activeModel && !didFallback && !(active is UnloadedTranscriber) {
            NSLog("MyWhi.EngineManager: cache hit, skip reload")
            return
        }

        isLoading = true
        defer { isLoading = false }

        let newEngine = makeEngine(name)
        if newEngine is UnloadedTranscriber {
            throw NSError(
                domain: "MyWhi.EngineManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unknown engine: \(name)"]
            )
        }

        // Try loading on the new engine; if it fails AND we were on WhisperKit,
        // fall back to Python.
        do {
            NSLog("MyWhi.EngineManager: calling loadModel on \(newEngine.name)…")
            try await newEngine.loadModel(model)
            NSLog("MyWhi.EngineManager: loadModel succeeded in \(String(format: "%.2f", Date().timeIntervalSince(startTime)))s")
        } catch {
            NSLog("MyWhi.EngineManager: loadModel FAILED on \(newEngine.name): \(error)")
            if name == "whisperkit" {
                NSLog("MyWhi.EngineManager: WhisperKit load failed, falling back to faster-whisper.")
                let fallback = makeEngine("faster-whisper")
                try await fallback.loadModel(model)
                self.active = fallback
                self.activeEngineName = fallback.name
                self.activeModel = model
                self.displayName = fallback.name
                self.didFallback = true
                return
            }
            throw error
        }

        self.active = newEngine
        self.activeEngineName = newEngine.name
        self.activeModel = model
        self.displayName = newEngine.name
        self.didFallback = false
    }

    /// Run transcription with the active engine.
    func transcribe(audioPath: String, model: String, language: String) async throws -> String {
        try await active.transcribe(audioPath: audioPath, model: model, language: language)
    }

    static let availableEngines: [(code: String, label: String)] = [
        ("whisperkit",    "WhisperKit (on-device)"),
        ("faster-whisper", "faster-whisper (Python)"),
    ]
}

/// Placeholder used until the first setEngine() call completes. Lets
/// the UI start up without crashing even if a recording happens before
/// preload finishes (extremely rare but possible if the user is fast).
private final class UnloadedTranscriber: Transcriber, @unchecked Sendable {
    let name = "unloaded"
    func loadModel(_ modelName: String) async throws {
        throw NSError(
            domain: "MyWhi.UnloadedTranscriber",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Engine not yet loaded. Try again in a moment."]
        )
    }
    func transcribe(audioPath: String, model: String, language: String) async throws -> String {
        throw NSError(
            domain: "MyWhi.UnloadedTranscriber",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Engine not yet loaded. Try again in a moment."]
        )
    }
}