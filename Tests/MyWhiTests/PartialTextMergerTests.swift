// PartialTextMergerTests.swift
// Phase 14 — exhaustive coverage of the partial-text merge logic
// used by the sliding-window live decoder. The merger is pure (no
// audio engine, no SwiftUI), so we can drive it with hand-crafted
// cases that mimic what WhisperKit would produce.

import XCTest
@testable import MyWhi

final class PartialTextMergerTests: XCTestCase {

    /// Phase 14: empty previous + first tick result → return next
    /// verbatim. No merge logic needed.
    func testEmptyPreviousReturnsNext() {
        XCTAssertEqual(
            PartialTextMerger.merge(previous: "", next: "привет мир"),
            "привет мир"
        )
        XCTAssertEqual(
            PartialTextMerger.merge(previous: "  ", next: "привет мир"),
            "привет мир"
        )
    }

    /// Phase 14: empty next (no audio / hallucinated silence) → keep
    /// previous unchanged.
    func testEmptyNextReturnsPrevious() {
        XCTAssertEqual(
            PartialTextMerger.merge(previous: "привет мир", next: ""),
            "привет мир"
        )
        XCTAssertEqual(
            PartialTextMerger.merge(previous: "привет мир", next: "   "),
            "привет мир"
        )
    }

    /// Phase 14: full overlap — next starts with all of previous. We
    /// keep `previous` (which has the new words) and don't concat.
    /// This is the "window slid forward, decode saw everything again"
    /// case.
    func testFullOverlapKeepsPrevious() {
        XCTAssertEqual(
            PartialTextMerger.merge(previous: "привет мир", next: "привет мир как"),
            "привет мир как"
        )
    }

    /// Phase 14: partial overlap — the common case. Next shares some
    /// tail tokens with the head of next. We stitch the non-shared
    /// tail of next onto previous.
    func testPartialOverlapStitchesNewTail() {
        // "как дела" overlap; next adds "хорошо"
        XCTAssertEqual(
            PartialTextMerger.merge(previous: "привет как дела", next: "как дела хорошо"),
            "привет как дела хорошо"
        )
    }

    /// Phase 14: single-token overlap.
    func testSingleTokenOverlap() {
        XCTAssertEqual(
            PartialTextMerger.merge(previous: "hello world foo", next: "foo bar"),
            "hello world foo bar"
        )
    }

    /// Phase 14: no overlap detected → conservative keep previous.
    /// Better to drop a partial decode than to duplicate text.
    func testNoOverlapKeepsPrevious() {
        XCTAssertEqual(
            PartialTextMerger.merge(previous: "привет мир", next: "абсолютно другой текст"),
            "привет мир"
        )
    }

    /// Phase 14: case-insensitive overlap (WhisperKit sometimes
    /// capitalizes the first letter of a continuation).
    func testCaseInsensitiveOverlap() {
        XCTAssertEqual(
            PartialTextMerger.merge(previous: "привет как дела", next: "Как дела хорошо"),
            "привет как дела хорошо"
        )
    }

    /// Phase 14: punctuation doesn't break overlap. WhisperKit adds
    /// punctuation that the previous window may not have.
    func testOverlapIgnoresPunctuation() {
        XCTAssertEqual(
            PartialTextMerger.merge(previous: "привет как дела", next: "привет, как дела хорошо"),
            "привет как дела хорошо"
        )
    }

    /// Phase 14: real Wispr-Flow-style sequence — three ticks that
    /// should merge into a coherent stream.
    func testRealisticThreeTickSequence() {
        // User says: "привет как дела отлично"
        // tick 1 audio range: last 8s — captures "привет как"
        // tick 2 audio range: last 8s — captures "привет как дела"
        // tick 3 audio range: last 8s — captures "привет как дела отлично"
        // But with sliding window, each tick only sees the last 8s:
        // tick 1: "привет как"
        // tick 2: "привет как дела" (overlap with prev: "привет как")
        // tick 3: "как дела отлично" (overlap with prev: tail of "привет как дела")
        let r1 = PartialTextMerger.merge(previous: "", next: "привет как")
        XCTAssertEqual(r1, "привет как")
        let r2 = PartialTextMerger.merge(previous: r1, next: "привет как дела")
        XCTAssertEqual(r2, "привет как дела")
        let r3 = PartialTextMerger.merge(previous: r2, next: "как дела отлично")
        XCTAssertEqual(r3, "привет как дела отлично")
    }

    /// Phase 14: overlap longer than the max token window should
    /// still work because we cap at `maxOverlapTokens`.
    func testOverlapAtBoundary() {
        // 12+1 token overlap — only the matching slice is merged.
        let prev = "a b c d e f g h i j k l m"
        let next = "j k l m n o p"
        let result = PartialTextMerger.merge(previous: prev, next: next)
        XCTAssertEqual(result, "a b c d e f g h i j k l m n o p")
    }

    /// Phase 14: word appearing in `next` that was also in
    /// `previous` but not as a tail token → no overlap detected.
    func testMiddleMatchDoesNotCount() {
        // "мир" appears in both but isn't at the boundary.
        XCTAssertEqual(
            PartialTextMerger.merge(previous: "привет мир пока", next: "мир пока"),
            "привет мир пока"
        )
    }

    /// Phase 14: punctuation-only next (model output "...") returns
    /// previous. Trimming happens before the overlap check.
    func testPunctuationOnlyNext() {
        XCTAssertEqual(
            PartialTextMerger.merge(previous: "привет мир", next: "..."),
            "привет мир"
        )
    }

    /// Phase 14: punctuation-only previous (degenerate input) is
    /// effectively empty after trimming and falls back to next.
    func testPunctuationOnlyPrevious() {
        XCTAssertEqual(
            PartialTextMerger.merge(previous: "...", next: "привет мир"),
            "привет мир"
        )
    }
}