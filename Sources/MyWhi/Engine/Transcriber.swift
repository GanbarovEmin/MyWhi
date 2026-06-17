// Transcriber.swift
// Protocol that abstracts the transcription backend. Two implementations:
//
//   - WhisperKitTranscriber  (primary, native Apple Silicon, fast)
//   - PythonTranscriber      (fallback, faster-whisper via Python venv)
//
// EngineManager picks the active one based on user settings.

import Foundation

protocol Transcriber: AnyObject, Sendable {
    /// Human-readable engine name (e.g. "WhisperKit", "faster-whisper").
    var name: String { get }

    /// Load the chosen model. Long-running; called once per model change.
    /// Throws on failure (model missing, network error, etc.).
    func loadModel(_ modelName: String) async throws

    /// Run transcription on a local audio file. Returns the full text.
    /// `language` is "ru"/"en"/"auto" (auto = let model detect).
    func transcribe(audioPath: String, model: String, language: String) async throws -> String
}