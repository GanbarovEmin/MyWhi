import XCTest
@testable import MyWhi

final class SoniqoTranscriberOutputTests: XCTestCase {
    func testCleanTranscriptOutputExtractsResultFromVerboseSpeechCLIOutput() {
        let raw = """
        Loaded 145680 samples (6.07s)
        Found 1 safetensor files
        Loading: model.safetensors
        Applied weights to audio encoder (18 layers, 301 tensors)
        Applied weights to text decoder (28 layers, 704 tensors)
        Transcribing.
        Result: Тестовая запись, тестовая запись, проверка качества транскрибации.
        Time: 0.58s, RTF: 0.095
        """

        XCTAssertEqual(
            SoniqoTranscriber.cleanTranscriptOutput(raw),
            "Тестовая запись, тестовая запись, проверка качества транскрибации."
        )
    }

    func testCleanTranscriptOutputExtractsInlineResultAndDropsTimingSuffix() {
        let raw = """
        Loaded 145680 samples (6.07s) Found 1 safetensor files Loading: model.Safetensors Applied weights to audio encoder (18 layers, 301 tensors) Applied weights to text decoder (28 layers, 704 tensors) Transcribing. Result: Тестовая запись, тестовая запись, проверка качества транскрибации. Time: 0.58s, RTF: 0.095
        """

        XCTAssertEqual(
            SoniqoTranscriber.cleanTranscriptOutput(raw),
            "Тестовая запись, тестовая запись, проверка качества транскрибации."
        )
    }
}
