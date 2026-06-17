// EngineManager.swift
// Owns the active Transcriber. Picks engine by user settings, supports
// hot-swap, and falls back to the Python engine if the primary fails.

import Foundation
import Combine

@MainActor
final class EngineManager: ObservableObject {

    /// Currently active engine. Re-created when the user switches engines
    /// or when the underlying engine changes its model.
    private(set) var active: Transcriber

    /// Set true when we fell back from WhisperKit → faster-whisper after
    /// an error. Surfaces a warning in the UI.
    @Published private(set) var didFallback: Bool = false

    /// Name of the active engine (for UI display).
    @Published private(set) var activeName: String

    private let pythonPath: String

    init(pythonPath: String) {
        self.pythonPath = pythonPath
        // Default to WhisperKit. Will be replaced when loadEngine() runs.
        self.active = WhisperKitTranscriber()
        self.activeName = "WhisperKit"
    }

    /// Swap to a different engine (WhisperKit or Python). Loads the model.
    func setEngine(_ name: String, model: String) async throws {
        let newEngine: Transcriber
        switch name {
        case "whisperkit":
            newEngine = WhisperKitTranscriber()
        case "faster-whisper":
            newEngine = PythonTranscriber(pythonPath: pythonPath)
        default:
            throw NSError(
                domain: "MyWhi.EngineManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unknown engine: \(name)"]
            )
        }

        // Try loading on the new engine; if it fails AND we were on WhisperKit,
        // fall back to Python.
        do {
            try await newEngine.loadModel(model)
        } catch {
            if name == "whisperkit" {
                NSLog("MyWhi.EngineManager: WhisperKit load failed (\(error)), falling back to faster-whisper.")
                let fallback = PythonTranscriber(pythonPath: pythonPath)
                try await fallback.loadModel(model)
                self.active = fallback
                self.activeName = fallback.name
                self.didFallback = true
                return
            }
            throw error
        }

        self.active = newEngine
        self.activeName = newEngine.name
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