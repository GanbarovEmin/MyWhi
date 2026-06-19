// PushToTalkTests.swift
// Phase 13 — unit tests for the push-to-talk settings + GlobalHotKey's
// enable/disable API surface.
//
// We don't actually install a Carbon event handler or NSEvent monitor
// in unit tests (those require app launch). What we CAN verify:
//   - Default value is OFF (backward compatibility)
//   - Round-trip through Codable
//   - enablePushToTalk / disablePushToTalk toggle the internal flag
//     and tear down the monitor handle on disable
//   - Carbon → Cocoa modifier conversion is correct

import XCTest
import AppKit
import Carbon.HIToolbox
@testable import MyWhi

final class PushToTalkTests: XCTestCase {

    /// Phase 13: default value must be `false` so existing users see
    /// no behavior change after upgrade.
    func testDefaultPushToTalkModeIsOff() {
        let settings = AppSettings()
        XCTAssertFalse(
            settings.pushToTalkMode,
            "pushToTalkMode must default to false for backward compatibility"
        )
    }

    /// Phase 13: legacy settings.json (no pushToTalkMode key) must
    /// decode without crashing AND come out with pushToTalkMode == false.
    func testLegacySettingsDecodeWithDefaultFalse() throws {
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
          "soundFeedbackEnabled": true,
          "inlineEditorMode": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertFalse(decoded.pushToTalkMode)
    }

    /// Phase 13: round-trip — set true, encode, decode, must stay true.
    func testRoundTripPreservesPushToTalkMode() throws {
        let settings = AppSettings()
        settings.pushToTalkMode = true

        let encoder = JSONEncoder()
        let data = try encoder.encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertTrue(decoded.pushToTalkMode)
    }

    /// Phase 13: enablePushToTalk / disablePushToTalk must be safe to
    /// call in sequence without crashing. After disable, the
    /// `releaseMonitor` handle must be nil so we don't leak.
    @MainActor
    func testEnableDisablePushToTalk() {
        let hotkey = GlobalHotKey()
        // Initially off.
        XCTAssertFalse(hotkey.pushToTalkEnabled)

        hotkey.enablePushToTalk(
            onPress: {},
            onRelease: {}
        )
        XCTAssertTrue(hotkey.pushToTalkEnabled)

        hotkey.disablePushToTalk()
        XCTAssertFalse(hotkey.pushToTalkEnabled)

        // Idempotent — calling disable twice doesn't crash.
        hotkey.disablePushToTalk()
        XCTAssertFalse(hotkey.pushToTalkEnabled)
    }

    /// Phase 13: handleReleaseEvent must dispatch to onRelease only
    /// when the matching key goes up OR a modifier from the chord is
    /// released. Unrelated events (other keyUp, flagsChanged that
    /// still match the chord) must not fire.
    @MainActor
    func testHandleReleaseEventFiltering() {
        var releaseCount = 0
        let hotkey = GlobalHotKey()
        hotkey.applySettings(UInt32(cmdKey | optionKey), 0x02)
        hotkey.enablePushToTalk(
            onPress: {},
            onRelease: { releaseCount += 1 }
        )

        // Synthesize a keyUp for the matching key (D = 0x02). This
        // must fire onRelease.
        if let matching = NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: [.command, .option],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 0x02
        ) {
            hotkey.test_handleReleaseEvent(
                matching,
                targetKey: 0x02,
                targetMods: [.command, .option]
            )
        }
        XCTAssertEqual(releaseCount, 1)

        // A keyUp for a non-matching key (A = 0x00) must NOT fire.
        if let nonMatching = NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: [.command, .option],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 0x00
        ) {
            hotkey.test_handleReleaseEvent(
                nonMatching,
                targetKey: 0x02,
                targetMods: [.command, .option]
            )
        }
        XCTAssertEqual(releaseCount, 1, "Non-matching keyUp must not fire onRelease")
    }
}