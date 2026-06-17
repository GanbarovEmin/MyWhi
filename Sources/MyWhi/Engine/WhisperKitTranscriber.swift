// WhisperKitTranscriber.swift
// Primary engine — Argmax WhisperKit, on-device Core ML/Metal inference.
// 2-5x faster than faster-whisper on Apple Silicon.
//
// Models are downloaded from HuggingFace on first use and cached at
// ~/Library/Caches/argmax/whisperkit/models/ (managed by WhisperKit).
//
// Available model sizes (smaller = faster, lower accuracy):
//   - tiny     (~40 MB, fast, lower quality)
//   - base     (~75 MB)
//   - small    (~250 MB, recommended for dictation)
//   - medium   (~750 MB, high quality)
//   - large    (~1.5 GB, best)
//   - largev2  / largev3  (newest large variants)

import Foundation
import WhisperKit

final class WhisperKitTranscriber: Transcriber, @unchecked Sendable {

    let name = "WhisperKit"

    /// Currently loaded WhisperKit pipeline. nil until loadModel() is called.
    private var pipe: WhisperKit?

    /// Lock to serialise reads/writes of `pipe` (init is async).
    private let pipeLock = NSLock()

    func loadModel(_ modelName: String) async throws {
        let resolved = resolveModelVariant(modelName)
        NSLog("MyWhi.WhisperKitTranscriber: loadModel(\(modelName) → \(resolved)) starting")

        let config = WhisperKitConfig(
            model: resolved,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: true,
            useBackgroundDownloadSession: false
        )

        do {
            let pipe = try await WhisperKit(config)
            NSLog("MyWhi.WhisperKitTranscriber: WhisperKit() init succeeded for \(resolved)")

            pipeLock.lock()
            self.pipe = pipe
            pipeLock.unlock()
        } catch {
            NSLog("MyWhi.WhisperKitTranscriber: WhisperKit() init FAILED for \(resolved): \(error)")
            throw error
        }
    }

    func transcribe(audioPath: String, model: String, language: String) async throws -> String {
        // If the requested model differs from what's loaded, reload.
        try await ensureModelLoaded(model)

        pipeLock.lock()
        let pipe = self.pipe
        pipeLock.unlock()

        guard let pipe else {
            throw NSError(
                domain: "MyWhi.WhisperKitTranscriber",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Model not loaded. Call loadModel() first."]
            )
        }

        // Build decoding options. Language is "ru"/"en"/"auto".
        let langArg: String? = (language == "auto" || language.isEmpty) ? nil : language
        let options = DecodingOptions(
            task: .transcribe,
            language: langArg,
            temperature: 0.0,
            temperatureIncrementOnFallback: 0.2,
            temperatureFallbackCount: 5,
            sampleLength: 224,
            topK: 5,
            usePrefillPrompt: true,
            detectLanguage: langArg == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            wordTimestamps: false,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            firstTokenLogProbThreshold: -1.5,
            noSpeechThreshold: 0.6
        )

        let results = await pipe.transcribe(
            audioPaths: [audioPath],
            decodeOptions: options
        )

        // results is [[TranscriptionResult]?]; we passed 1 file → outer [0]
        guard let fileResults = results.first, let fileResults else {
            throw NSError(
                domain: "MyWhi.WhisperKitTranscriber",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No transcription result returned for \(audioPath)"]
            )
        }

        // Concatenate segments.
        let combined = fileResults
            .map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return combined
    }

    // MARK: - Private

    private var loadedModelName: String?

    private func ensureModelLoaded(_ modelName: String) async throws {
        let resolved = resolveModelVariant(modelName)
        if loadedModelName == resolved { return }
        try await loadModel(resolved)
        loadedModelName = resolved
    }

    /// Map legacy / fuzzy model names to WhisperKit's ModelVariant strings.
    /// WhisperKit accepts the variant name as String ("tiny", "small", etc.).
    private func resolveModelVariant(_ name: String) -> String {
        switch name {
        case "tiny", "tiny.en":                  return "tiny"
        case "base", "base.en":                  return "base"
        case "small", "small.en":                return "small"
        case "medium", "medium.en":              return "medium"
        case "large", "large-v2", "largev2":     return "largev2"
        case "large-v3", "largev3":             return "largev3"
        case "large-v3-turbo", "largev3_turbo": return "largev3_turbo"
        default:                                  return "small"  // safe default
        }
    }
}