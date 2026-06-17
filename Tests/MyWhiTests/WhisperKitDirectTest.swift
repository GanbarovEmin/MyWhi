import Foundation
import WhisperKit
import XCTest

final class WhisperKitDirectTest: XCTestCase {

    func testTranscribeRussianAudio() async throws {
        let audioPath = "/tmp/mywhi-test.wav"
        let modelName = "medium"

        print("[Test] Loading WhisperKit model \(modelName)…")
        let startTime = Date()

        let config = WhisperKitConfig(
            model: modelName,
            verbose: true,
            logLevel: .info,
            prewarm: false,
            load: true,
            download: true,
            useBackgroundDownloadSession: false
        )
        let pipe = try await WhisperKit(config)
        let loadElapsed = Date().timeIntervalSince(startTime)
        print("[Test] Model loaded in \(String(format: "%.2f", loadElapsed))s")
        XCTAssertNotNil(pipe, "WhisperKit pipeline should not be nil after init")

        print("[Test] Transcribing \(audioPath)…")
        let transcribeStart = Date()
        let options = DecodingOptions(
            task: .transcribe,
            language: "ru",
            temperature: 0.0,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        let results = await pipe.transcribe(audioPaths: [audioPath], decodeOptions: options)
        let transcribeElapsed = Date().timeIntervalSince(transcribeStart)
        print("[Test] Transcription done in \(String(format: "%.2f", transcribeElapsed))s")

        guard let fileResults = results.first, let fileResults else {
            XCTFail("No results returned"); return
        }
        for (i, r) in fileResults.enumerated() {
            print("[Test] Segment[\(i)]: \(r.text)")
        }
        let combined = fileResults.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        print("[Test] Combined: \(combined)")
        XCTAssertFalse(combined.isEmpty, "Transcription should not be empty")
        XCTAssertGreaterThan(combined.count, 5, "Transcription should have meaningful content")
    }
}
