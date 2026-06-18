// EngineDisplayNameTests.swift
// Pins the display name `WhisperKitTranscriber.name` returns. The
// frontmatter persists this exact string and the UI compares against
// it (ScratchpadDetailView), so any future change to it must fail
// a test instead of silently showing the wrong engine label.

import XCTest
@testable import MyWhi

final class EngineDisplayNameTests: XCTestCase {

    /// The display name WhisperKitTranscriber returns. The frontmatter
    /// records this exact string. UI pill labels depend on it.
    func testWhisperKitTranscriberName() {
        let t = WhisperKitTranscriber()
        XCTAssertEqual(t.name, "WhisperKit",
                       "WhisperKitTranscriber.name must stay 'WhisperKit' (with capital W/K). "
                       + "Changing it changes every existing vault file's engine frontmatter label.")
    }

    /// Round-trips through a real TranscriptFrontmatter to make
    /// sure the strings the UI compares against are exactly what
    /// the transcriber emits.
    func testFrontmatterPreservesEngineDisplayName() throws {
        let fmatter = TranscriptFrontmatter(
            id: UUID(),
            createdAt: Date(),
            language: "ru",
            model: "medium",
            engine: "WhisperKit",  // as emitted by WhisperKitTranscriber.name
            durationSeconds: 5,
            chars: 100,
            words: 20,
            audio: nil
        )
        let rendered = fmatter.renderYAML()
        XCTAssertTrue(rendered.contains("engine: WhisperKit"),
                      "Frontmatter render must preserve the exact 'WhisperKit' display name")

        // Re-parse to confirm the round trip.
        let parsed = try XCTUnwrap(TranscriptFrontmatter.parse(from: rendered + "body text"))
        XCTAssertEqual(parsed.frontmatter.engine, "WhisperKit")
    }
}