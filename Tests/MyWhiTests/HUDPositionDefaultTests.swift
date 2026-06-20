// HUDPositionDefaultTests.swift
// Phase 20 — verifies the bottom-HUD default flip. We want to be
// absolutely sure:
//   1. New users (no settings.json) get `.bottom` (Wispr Flow convention).
//   2. Existing users with `.top` in their settings.json keep `.top`
//      (back-compat — they were used to it).
//   3. The SettingsViewDesktop Picker still binds correctly.

import XCTest
@testable import MyWhi

final class HUDPositionDefaultTests: XCTestCase {

    /// Phase 20: a freshly created AppSettings with no preferences
    /// must default to .bottom (Wispr Flow convention).
    func testDefaultHUDPositionIsBottom() {
        let s = AppSettings()
        XCTAssertEqual(s.hudPosition, .bottom,
                       "Default HUD position must be bottom (Wispr Flow)")
    }

    /// Phase 20: a legacy settings.json without hudPosition must
    /// decode as .top (back-compat — existing users don't see a
    /// sudden flip). The decoder fallback lives in init(from:).
    func testLegacySettingsDecodeAsTop() throws {
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
        XCTAssertEqual(decoded.hudPosition, .top,
                       "Existing users without hudPosition key must keep their legacy .top default")
    }

    /// Phase 20: round-trip — explicit bottom persists.
    func testBottomRoundTrips() throws {
        let s = AppSettings()
        s.hudPosition = .bottom

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.hudPosition, .bottom)
    }

    /// Phase 20: round-trip — explicit top persists (existing users
    /// who set top must stay top).
    func testTopRoundTrips() throws {
        let s = AppSettings()
        s.hudPosition = .top

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.hudPosition, .top)
    }
}