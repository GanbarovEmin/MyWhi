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

    /// Phase 17: cached token IDs for the voice-command prompt. We
    /// tokenize once after WhisperKit init (via `pipe.tokenizer`) and
    /// reuse the result for every subsequent `transcribe()` call.
    /// Tokenization requires the tokenizer to be loaded, so we
    /// cannot do it at app startup; we do it lazily on first use.
    /// Nil means "not yet computed" or "voice commands disabled".
    private var cachedPromptTokens: [Int]?
    /// Last language we tokenized for. If the user switches language
    /// in Settings, we re-tokenize.
    private var cachedPromptLanguage: String?
    /// Voice commands toggle — read fresh from settings on every
    /// transcribe() call so Settings UI changes take effect immediately.
    private weak var appSettings: AppSettings?

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
        //   - promptTokens                → Phase 17 voice commands.
        //                                  We tokenize a small
        //                                  punctuation-vocabulary prompt
        //                                  ("Period. Comma, New line.")
        //                                  through the model-specific
        //                                  tokenizer at WhisperKit init,
        //                                  cache the token IDs, and pass
        //                                  them on every decode. This
        //                                  teaches the decoder to render
        //                                  spoken voice commands as their
        //                                  punctuation characters.
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
            promptTokens: currentPromptTokens(for: language),  // Phase 17
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

    // MARK: - Voice-command prompt tokens (Phase 17)
    //
    // Whisper's `prompt` parameter (here `DecodingOptions.promptTokens`)
    // biases the decoder toward a particular style / vocabulary. By
    // pre-tokenizing a small punctuation-vocabulary prompt ("Period.
    // Comma, New line. Question mark?") we teach the decoder that
    // when the user says those phrases, the appropriate token to emit
    // is the punctuation character itself.
    //
    // Token IDs are model-specific (multilingual models use a different
    // BPE vocab than English-only). We tokenize through the live
    // `pipe.tokenizer` after WhisperKit init and cache the result so
    // we pay the cost once per (model, language) pair.

    /// Build the natural-language voice command prompt for the
    /// user's language. We keep the examples short and concrete so
    /// the model picks up the pattern without biasing regular
    /// dictation.
    private func voiceCommandPrompt(for language: String) -> String {
        switch language {
        case "ru":
            return "Привет, как дела. Сегодня отличный день. Точка. " +
                   "Запятая, ещё текст. Вопрос? Восклицание! Новая строка."
        case "en":
            return "Hello, how are you. Today is a great day. Period. " +
                   "Comma, more text. Question? Exclamation! New line."
        default:
            // Auto-detect: pick English since most users of the
            // default model family speak it. The bias is mild either
            // way.
            return "Hello. Period. Comma, more text. New line."
        }
    }

    /// Returns the cached prompt tokens for the given language, or
    /// nil if voice commands are disabled in Settings. Re-tokenizes
    /// when the language changes.
    ///
    /// Whisper limits `promptTokens` to ~`maxPromptLen` (typically
    /// 224). We cap our prompt well below that to leave headroom.
    private func currentPromptTokens(for language: String) -> [Int]? {
        // Settings-driven opt-out: caller can disable voice commands.
        // We read this lazily because AppSettings isn't injected at
        // init time (it can change at any time via Settings UI).
        if appSettings?.voiceCommandsEnabled == false {
            return nil
        }
        // If we already tokenized for this language, return the cache.
        if cachedPromptLanguage == language, let tokens = cachedPromptTokens {
            return tokens
        }
        // Tokenize. Requires WhisperKit + tokenizer to be initialized.
        guard let tokenizer = pipe?.tokenizer else { return nil }
        let prompt = voiceCommandPrompt(for: language)
        var tokens = tokenizer.encode(text: prompt)
        // Trim to a safe length — WhisperKit's prompt slot is bounded.
        // 200 tokens is well under the typical 224-token cap and
        // gives the decoder room for actual content.
        if tokens.count > 200 {
            tokens = Array(tokens.suffix(200))
        }
        cachedPromptTokens = tokens
        cachedPromptLanguage = language
        NSLog("MyWhi.WhisperKitTranscriber: voice-command prompt tokenized (\(tokens.count) tokens for \(language))")
        return tokens
    }

    /// Hook used by `EngineManager` to inject the live AppSettings
    /// reference. Must be called once after construction so the
    /// voice-commands toggle and any future settings reach the
    /// transcriber without threading AppSettings through every
    /// `transcribe(audioPath:)` call site.
    func setAppSettings(_ settings: AppSettings) {
        self.appSettings = settings
    }
}