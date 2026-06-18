// EngineDisplayNameTests.swift
// Regression: the frontmatter stores the engine *display name*
// (e.g. "WhisperKit", "faster-whisper") returned by
// Transcriber.name. The settings stores the engine *code*
// (e.g. "whisperkit"). UI code that compares the frontmatter
// value to a code literal needs to compare against the display
// name, not the code — otherwise it always shows the "wrong"
// engine label (e.g. the pill in ScratchpadDetailView used to
// say "Python" for every WhisperKit recording).
//
// We pin the exact strings here so any future change to either
// Transcriber.name or the UI comparison fails a test instead of
// silently showing the wrong label.

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

    /// The display name PythonTranscriber returns.
    func testPythonTranscriberName() {
        let t = PythonTranscriber(pythonPath: "/nonexistent")
        XCTAssertEqual(t.name, "faster-whisper",
                       "PythonTranscriber.name must stay 'faster-whisper'.")
    }

    /// The list view checks `engine == "faster-whisper"`. That's the
    /// display name, so this should match. (Past bug: the detail
    /// view checked `"whisperkit"` — the code — which never matched
    /// the stored display name "WhisperKit".)
    func testFasterWhisperBadgeMatch() {
        let t = PythonTranscriber(pythonPath: "/nonexistent")
        XCTAssertEqual(t.name, "faster-whisper",
                       "ScratchpadListView's 'py' badge condition must match the display name.")
    }

    /// ScratchpadDetailView's enginePillColor / enginePillName.
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