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
//
// THREADING
// All access to `pipe` happens on the main actor (EngineManager is
// @MainActor, and WhisperKitTranscriber is only ever constructed and
// used by it). The previous NSLock is no longer needed — there is no
// shared mutable state across actor boundaries. WhisperKit's own
// inference runs on its internal thread pool, released to us via
// `await`.

import Foundation
import WhisperKit

final class WhisperKitTranscriber: Transcriber, @unchecked Sendable {

    let name = "WhisperKit"

    /// Currently loaded WhisperKit pipeline. nil until loadModel() is called.
    private var pipe: WhisperKit?

    /// Last successfully loaded model variant, e.g. "small". Used to
    /// short-circuit transcribe() when the user hasn't changed models.
    private var loadedModelName: String?

    /// Build a WhisperKitConfig tuned for fast first-record and short
    /// dictation clips.
    ///
    /// Settings that matter:
    /// - `prewarm: true`              — pre-compile Metal kernels after
    ///   load. Pays ~1-2s once at load time to make the first inference
    ///   1-2s faster. The trade-off is worth it for dictation (the first
    ///   record after launch is the most important UX moment).
    /// - `useBackgroundDownloadSession: true` — first-time model
    ///   download uses NSURLSession background config. Doesn't block
    ///   the calling actor; we can show progress in the UI. For
    ///   subsequent loads the model is already cached.
    /// - `load: true`                 — actually instantiate the pipeline.
    private func makeConfig(_ resolved: String) -> WhisperKitConfig {
        WhisperKitConfig(
            model: resolved,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: true,
            useBackgroundDownloadSession: true
        )
    }

    func loadModel(_ modelName: String) async throws {
        let resolved = resolveModelVariant(modelName)
        NSLog("MyWhi.WhisperKitTranscriber: loadModel(\(modelName) → \(resolved)) starting")

        let config = makeConfig(resolved)
        do {
            let newPipe = try await WhisperKit(config)
            NSLog("MyWhi.WhisperKitTranscriber: WhisperKit() init succeeded for \(resolved)")
            self.pipe = newPipe
            self.loadedModelName = resolved
        } catch {
            NSLog("MyWhi.WhisperKitTranscriber: WhisperKit() init FAILED for \(resolved): \(error)")
            throw error
        }
    }

    func transcribe(audioPath: String, model: String, language: String) async throws -> String {
        // Ensure the requested model is loaded. If the user is transcribing
        // with a different model than we have cached, reload.
        let resolved = resolveModelVariant(model)
        if loadedModelName != resolved {
            try await loadModel(resolved)
        }

        guard let pipe else {
            throw NSError(
                domain: "MyWhi.WhisperKitTranscriber",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Model not loaded. Call loadModel() first."]
            )
        }

        // Build decoding options. Language is "ru"/"en"/"auto".
        //
        // Tuned for short dictation clips (typical 5-60s). Key choices:
        //   - skipSpecialTokens = false  → keep punctuation (default in
        //                                  WhisperKit; we set it explicitly
        //                                  so a refactor doesn't reintroduce
        //                                  a "wall of text" bug).
        //   - chunkingStrategy = nil     → disable VAD chunking. Short
        //                                  dictation clips don't need it;
        //                                  chunking can split a sentence
        //                                  mid-word and force hallucinated
        //                                  filler text in each chunk.
        //   - temperature 0.0 with        → greedy decode: faster, more
        //     fallbackCount = 5             deterministic. If compression
        //                                  ratio trips the fallback (2.4),
        //                                  the temperature bumps by 0.2
        //                                  and we retry up to 5 times —
        //                                  usually enough to escape a
        //                                  hallucination loop on noisy input.
        //   - promptTokens                → DEFERRED. WhisperKit's
        //                                  DecodingOptions takes
        //                                  `promptTokens: [Int]?`, not a
        //                                  string. Implementing voice
        //                                  commands ("new line" → \n,
        //                                  "period" → ".") requires
        //                                  tokenizing the prompt through
        //                                  the model-specific tokenizer,
        //                                  which is doable but adds
        //                                  coupling. Tracking as
        //                                  Phase 8.3-extra.
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
            skipSpecialTokens: false,        // ← keep punctuation
            withoutTimestamps: true,
            wordTimestamps: false,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            firstTokenLogProbThreshold: -1.5,
            noSpeechThreshold: 0.6,
            chunkingStrategy: nil            // ← disable VAD chunking
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

    // MARK: - Voice-command prompt (Phase 8.3 — DEFERRED)
    //
    // WhisperKit's DecodingOptions accepts `promptTokens: [Int]?`, not a
    // raw string. To bias the decoder toward voice commands like "new
    // line" → \n, "period" → ".", we would need to tokenize the prompt
    // through the model's tokenizer at runtime. That's straightforward
    // but adds coupling (tokenizer API varies across Whisper models).
    //
    // For now, voice commands are not implemented. Punctuation is still
    // correct because we keep `skipSpecialTokens: false` and disable VAD
    // chunking (which was the main source of punctuation collapse in v1).
    //
    // When implementing: cache token IDs for a known set of
    // multi-language prompts ("Period.", "New line.", "Comma,", etc.)
    // and pass them via `options.promptTokens`.
}