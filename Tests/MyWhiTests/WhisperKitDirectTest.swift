// WhisperKitDirectTest.swift
// Direct end-to-end test of WhisperKit + regression for the punctuation
// regression: DecodingOptions.skipSpecialTokens must remain `false`,
// otherwise Whisper strips punctuation entirely and you get a wall
// of unpunctuated text.

import Foundation
import WhisperKit
import XCTest

final class WhisperKitDirectTest: XCTestCase {

    /// Pre-generated audio at /tmp/mywhi-test.wav containing Russian text
    /// "Привет, это тестовая запись для проверки транскрибации WhisperKit на маке."
    /// Created via:
    ///   say -v Milena -o /tmp/mywhi-test.aiff "<text>"
    ///   afconvert /tmp/mywhi-test.aiff /tmp/mywhi-test.wav -f WAVE -d LEI16@16000
    private let russianAudioPath = "/tmp/mywhi-test.wav"

    /// Pre-generated English audio at /tmp/mywhi-punct.wav containing
    /// "Hello, world! How are you? I am fine. Thanks - really."
    /// Created via:
    ///   say -v Yuri -o /tmp/mywhi-punct.aiff "<text>"
    ///   afconvert /tmp/mywhi-punct.aiff /tmp/mywhi-punct.wav -f WAVE -d LEI16@16000
    private let englishAudioPath = "/tmp/mywhi-punct.wav"

    private func loadModel(_ modelName: String) async throws -> WhisperKit {
        let config = WhisperKitConfig(
            model: modelName,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: true,
            useBackgroundDownloadSession: false
        )
        return try await WhisperKit(config)
    }

    private func transcribe(
        pipe: WhisperKit,
        audioPath: String,
        language: String? = "ru",
        skipSpecialTokens: Bool = false
    ) async -> String {
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0.0,
            temperatureIncrementOnFallback: 0.2,
            temperatureFallbackCount: 5,
            sampleLength: 224,
            topK: 5,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: skipSpecialTokens,
            withoutTimestamps: true,
            wordTimestamps: false,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            firstTokenLogProbThreshold: -1.5,
            noSpeechThreshold: 0.6,
            chunkingStrategy: nil
        )
        let results = await pipe.transcribe(audioPaths: [audioPath], decodeOptions: options)
        guard let fileResults = results.first, let fileResults else { return "" }
        return fileResults.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testRussianTranscription() async throws {
        let pipe = try await loadModel("medium")
        let text = await transcribe(pipe: pipe, audioPath: russianAudioPath, language: "ru")
        print("[Test] Russian transcription: \(text)")
        XCTAssertFalse(text.isEmpty, "Transcription should not be empty")
        XCTAssertGreaterThan(text.count, 5, "Transcription should have meaningful content")
    }

    /// Regression: skipSpecialTokens must remain `false`. This test
    /// documents WhisperKit's actual behavior on a punctuation-rich
    /// English clip. The "true" run shows what changes when punctuation
    /// tokens are stripped (typically: sentence-final markers like
    /// `!`/`?` get cleaned up, but commas survive). The "false" run is
    /// what production uses — it must include at least one of the
    /// marker characters from the source text.
    func testPunctuationPreservedWithSkipSpecialTokensFalse() async throws {
        let pipe = try await loadModel("medium")

        let noPunctText = await transcribe(
            pipe: pipe, audioPath: englishAudioPath, language: "en",
            skipSpecialTokens: true
        )
        print("[Test] skipSpecialTokens=true:  \(noPunctText)")

        let punctText = await transcribe(
            pipe: pipe, audioPath: englishAudioPath, language: "en",
            skipSpecialTokens: false
        )
        print("[Test] skipSpecialTokens=false: \(punctText)")

        // Production uses skipSpecialTokens=false. It must include at
        // least one of the markers from the source text: !, ?, ., -.
        let markers: [Character] = ["!", "?", ".", "-"]
        let foundMarker = markers.contains { punctText.contains($0) }
        XCTAssertTrue(foundMarker,
                      "skipSpecialTokens=false must preserve at least one punctuation marker (! ? . -); got: \(punctText)")

        // The non-production ("true") run must still have SOME text and
        // not crash, so we don't regress to a silent failure.
        XCTAssertFalse(noPunctText.isEmpty,
                       "skipSpecialTokens=true must still produce text")
    }
}