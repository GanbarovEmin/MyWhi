// EngineManager.swift
// Owns the active Transcriber. Caches engines by (name, model) so we
// don't pay the 6-7s model-init cost on every recording — the cache
// only reloads when the user actually changes engine or model size.
//
// v2.0: faster-whisper removed. WhisperKit is the only engine.
// The fallback path and Python subprocess plumbing are gone —
// the app is now single-engine, single-process.

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

    /// True while a model is being loaded (downloaded, compiled, warmed).
    /// Settings can use this to show a progress bar.
    @Published private(set) var isLoading: Bool = false

    /// v2.0: no fallback engine, so didFallback is always false.
    /// Kept as a @Published for API stability with the UI (the
    /// sidebar footer still observes it but never shows anything).
    @Published private(set) var didFallback: Bool = false

    /// Factory closure: given an engine code, return a fresh Transcriber.
    /// Default builds WhisperKitTranscriber. Tests override this to
    /// inject fakes.
    nonisolated(unsafe) var makeEngine: (String) -> Transcriber

    /// Phase 17: live AppSettings reference. Passed to newly-created
    /// transcriber instances via `setAppSettings(_:)` so they can read
    /// voice-commands / future per-engine settings without threading
    /// AppSettings through every call site.
    weak var appSettings: AppSettings?

    init() {
        // Default factory: only WhisperKit is supported.
        self.makeEngine = { code in
            switch code {
            case "whisperkit":    return WhisperKitTranscriber()
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

    /// Swap to a different engine and load the model. No-op if the
    /// requested (name, model) pair matches the active one.
    func setEngine(_ name: String, model: String) async throws {
        let startTime = Date()
        NSLog("MyWhi.EngineManager: setEngine(name=\(name), model=\(model)) — active=\(activeEngineName)/\(activeModel)")

        // Cache hit: same engine + same model → skip reload.
        if name == activeEngineName && model == activeModel && !(active is UnloadedTranscriber) {
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

        // Phase 22: unload the previous engine's model before the new
        // one is created. We do this on the *outgoing* engine (not the
        // incoming one) so the new engine's loadModel() can take its
        // time without us holding a heavy Core ML/Metal pipeline
        // alongside it. WhisperKitTranscriber overrides unloadModel()
        // to nil out its `pipe`; other backends get the protocol
        // default no-op.
        if let outgoing = self.active as? WhisperKitTranscriber {
            outgoing.unloadModel()
        } else {
            self.active.unloadModel()
        }

        // Phase 17: hand the new engine the live AppSettings reference
        // so it can read voice-commands / future per-engine settings.
        if let whisper = newEngine as? WhisperKitTranscriber, let settings = appSettings {
            whisper.setAppSettings(settings)
        }

        do {
            NSLog("MyWhi.EngineManager: calling loadModel on \(newEngine.name)…")
            try await newEngine.loadModel(model)
            NSLog("MyWhi.EngineManager: loadModel succeeded in \(String(format: "%.2f", Date().timeIntervalSince(startTime)))s")
        } catch {
            NSLog("MyWhi.EngineManager: loadModel FAILED on \(newEngine.name): \(error)")
            // No fallback engine in v2.0 — propagate the error so the
            // user can see it in the UI.
            throw error
        }

        self.active = newEngine
        self.activeEngineName = newEngine.name
        self.activeModel = model
        self.displayName = newEngine.name
    }

    /// Run transcription with the active engine.
    func transcribe(audioPath: String, model: String, language: String) async throws -> String {
        try await active.transcribe(audioPath: audioPath, model: model, language: language)
    }

    /// Called from LiveTranscriber when auto-detect detects a language
    /// from partial text. Notifies the active WhisperKitTranscriber to
    /// re-tokenize promptTokens for the new language (Wispr Flow parity).
    func notifyLanguageDetected(_ language: String) {
        if let whisper = active as? WhisperKitTranscriber {
            whisper.updatePromptTokensForLanguage(language)
        }
    }
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