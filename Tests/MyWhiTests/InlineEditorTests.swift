// InlineEditorTests.swift
// Phase 11 — unit tests for the inline editor setting + the
// promoteLastTranscript() helper on AppState.
//
// We can't easily exercise SwiftUI binding semantics from a unit
// test, but we CAN verify the AppSettings defaults + the
// round-trip through Codable, and we CAN verify that
// promoteLastTranscript correctly mutates lastTranscript.

import XCTest
@testable import MyWhi

final class InlineEditorTests: XCTestCase {

    /// Phase 11: default value must be `false` so existing users see
    /// no behavior change after upgrade.
    func testDefaultInlineEditorModeIsOff() {
        let settings = AppSettings()
        XCTAssertFalse(
            settings.inlineEditorMode,
            "inlineEditorMode must default to false for backward compatibility"
        )
    }

    /// Phase 11: a settings.json file written before v3.0.0 must decode
    /// without crashing AND come out with inlineEditorMode == false.
    /// This is the most important migration guarantee — old files don't
    /// have the new key.
    func testLegacySettingsDecodeWithDefaultFalse() throws {
        // Construct a JSON blob that matches the pre-Phase-11 shape.
        let json = """
        {
          "modelSize": "small",
          "language": "ru",
          "autoCopy": true,
          "saveHistory": true,
          "autoPaste": false,
          "useDarkMode": false,
          "hotkeyModifiers": 2560,
          "hotkeyKeyCode": 2,
          "liveStreamingEnabled": true,
          "soundFeedbackEnabled": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertFalse(
            decoded.inlineEditorMode,
            "Legacy settings.json without inlineEditorMode must decode as false"
        )
        XCTAssertEqual(decoded.modelSize, "small")
        XCTAssertEqual(decoded.language, "ru")
        XCTAssertTrue(decoded.liveStreamingEnabled)
    }

    /// Phase 11: round-trip — set true, encode, decode, must stay true.
    func testRoundTripPreservesInlineEditorMode() throws {
        let settings = AppSettings()
        let copy = settings
        copy.inlineEditorMode = true

        let encoder = JSONEncoder()
        let data = try encoder.encode(copy)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertTrue(decoded.inlineEditorMode)
    }

    /// Phase 11: promoteLastTranscript is the public API for the
    /// inline editor to commit edits back to AppState. It should
    /// (a) trim whitespace, (b) reject empty input, (c) propagate
    /// the new value via @Published.
    @MainActor
    func testPromoteLastTranscriptTrimsAndUpdates() async {
        let state = AppState()
        let expectation = expectation(description: "lastTranscript updated")

        // Subscribe to changes; we'll resolve when the value flips.
        let cancellable = state.$lastTranscript
            .dropFirst()
            .sink { newValue in
                if newValue == "hello world" {
                    expectation.fulfill()
                }
            }

        // promoteLastTranscript trims and assigns.
        state.promoteLastTranscript("  hello world  ")

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(state.lastTranscript, "hello world")
        cancellable.cancel()
    }

    /// Phase 11: promoteLastTranscript on empty input must be a no-op
    /// (not blank out the existing transcript).
    @MainActor
    func testPromoteLastTranscriptRejectsEmpty() {
        let state = AppState()
        state.promoteLastTranscript("existing text")
        XCTAssertEqual(state.lastTranscript, "existing text")
        state.promoteLastTranscript("   ")
        XCTAssertEqual(state.lastTranscript, "existing text")
        state.promoteLastTranscript("")
        XCTAssertEqual(state.lastTranscript, "existing text")
    }
}
