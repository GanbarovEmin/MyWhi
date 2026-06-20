// TranscriptPolisherTests.swift
// Phase 18 — verifies the polish() pipeline plus a couple of edge
// cases that came up while auditing the file (the old code had a
// no-op `.replacingOccurrences(of: "", with: "")` chained in with
// the BOM strip — fixed in Phase 18).

import XCTest
@testable import MyWhi

final class TranscriptPolisherTests: XCTestCase {

    /// Phase 18: BOM at the start of the raw transcript must be
    /// stripped. Some upstream tools write the UTF-8 BOM and it
    /// leaks through WhisperKit's text field.
    func testStripsBOM() {
        XCTAssertEqual(
            TranscriptPolisher.polish("\u{FEFF}привет мир"),
            "Привет мир"
        )
    }

    /// Phase 18: the empty-string `replacingOccurrences` chain that
    /// was in the old polish() must NOT cause infinite loop or
    /// unexpected removal of content. (It was a no-op but stylistically
    /// wrong.)
    func testEmptyReplacementDoesNotMutate() {
        let input = "привет мир"
        XCTAssertEqual(
            TranscriptPolisher.polish(input),
            "Привет мир"
        )
    }

    /// Phase 18: WhisperKit's "[BLANK_AUDIO]" / "[MUSIC]" markers
    /// must be stripped (they're model annotations, not user speech).
    func testStripsBLANK_AUDIO() {
        XCTAssertEqual(
            TranscriptPolisher.polish("[BLANK_AUDIO] привет как дела"),
            "Привет как дела"
        )
        XCTAssertEqual(
            TranscriptPolisher.polish("[music] тут была музыка"),
            "Тут была музыка",
            "Music marker is case-insensitive"
        )
    }

    /// Phase 18: dictionary replacements work case-insensitively
    /// and diacritic-insensitively.
    func testDictionaryReplacement() {
        let dict = [
            DictionaryReplacement(from: "ашбис", to: "ASBIS"),
            DictionaryReplacement(from: "айспейс", to: "iSpace")
        ]
        XCTAssertEqual(
            TranscriptPolisher.polish("работаем с ашбис и айспейс", dictionary: dict),
            "Работаем с ASBIS и iSpace"
        )
    }

    /// Phase 18: dictionary replacement is case-insensitive
    /// ("Ашбис" → "ASBIS" too).
    func testDictionaryReplacementCaseInsensitive() {
        let dict = [
            DictionaryReplacement(from: "ашбис", to: "ASBIS")
        ]
        XCTAssertEqual(
            TranscriptPolisher.polish("АШБИС работает", dictionary: dict),
            "ASBIS работает"
        )
    }

    /// Phase 18: punctuation spacing fixes. Whisper sometimes emits
    /// "word ," or "word ." — the polisher strips the leading space.
    func testPunctuationSpacing() {
        XCTAssertEqual(
            TranscriptPolisher.polish("привет , как дела ."),
            "Привет, как дела."
        )
    }

    /// Phase 18: repeated punctuation collapses. "word..." → "word."
    func testRepeatedPunctuationCollapses() {
        XCTAssertEqual(
            TranscriptPolisher.polish("что???"),
            "Что?"
        )
        XCTAssertEqual(
            TranscriptPolisher.polish("ага!!!"),
            "Ага!"
        )
    }

    /// Phase 18: whitespace collapsing.
    func testWhitespaceCollapsing() {
        XCTAssertEqual(
            TranscriptPolisher.polish("привет    как\tдела\nмир"),
            "Привет как дела мир"
        )
    }

    /// Phase 18: first letter is capitalized (Russian uppercase).
    func testFirstLetterCapitalized() {
        XCTAssertEqual(
            TranscriptPolisher.polish("привет"),
            "Привет"
        )
    }

    /// Phase 18: empty input → empty output.
    func testEmptyInput() {
        XCTAssertEqual(TranscriptPolisher.polish(""), "")
    }

    /// Phase 18: only-whitespace input → empty output.
    func testWhitespaceOnlyInput() {
        XCTAssertEqual(TranscriptPolisher.polish("   \n\t  "), "")
    }

    /// Phase 18: empty dictionary in API still works (no crash).
    func testEmptyDictionaryNoOp() {
        XCTAssertEqual(
            TranscriptPolisher.polish("привет мир", dictionary: []),
            "Привет мир"
        )
    }

    /// Phase 18: dictionary entry with empty `from` is skipped
    /// (defensive — would otherwise be a no-op replacement of empty).
    func testDictionaryEntryWithEmptyFromIsSkipped() {
        let dict = [
            DictionaryReplacement(from: "", to: "X"),  // should be skipped
            DictionaryReplacement(from: "мир", to: "world")
        ]
        XCTAssertEqual(
            TranscriptPolisher.polish("привет мир", dictionary: dict),
            "Привет world"
        )
    }
}