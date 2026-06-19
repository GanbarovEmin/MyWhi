import XCTest
@testable import MyWhi

final class TranscriptPolisherTests: XCTestCase {

    func testPolish_trimsWhitespaceAndNormalizesPunctuation() {
        let text = TranscriptPolisher.polish("  привет   мир  ,  как дела ?  ")
        XCTAssertEqual(text, "Привет мир, как дела?")
    }

    func testPolish_appliesDictionaryCaseInsensitively() {
        let text = TranscriptPolisher.polish(
            "ашбис и айспейс",
            dictionary: [
                DictionaryReplacement(from: "ашбис", to: "ASBIS"),
                DictionaryReplacement(from: "айспейс", to: "iSpace")
            ]
        )
        XCTAssertEqual(text, "ASBIS и iSpace")
    }

    func testPolish_removesCommonSpecialMarkers() {
        let text = TranscriptPolisher.polish("[BLANK_AUDIO] hello <|endoftext|>")
        XCTAssertEqual(text, "Hello")
    }
}
