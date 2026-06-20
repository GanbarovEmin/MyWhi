// HDThemeTests.swift
// Phase 7 — unit tests for the theme provider. The theme must produce
// sensible light + dark palettes and the EnvironmentValues hook must
// resolve to .light by default.

import XCTest
import SwiftUI
@testable import MyWhi

final class HDThemeTests: XCTestCase {

    /// Phase 7: light theme has the expected key values.
    func testLightThemeBasics() {
        let theme = HDTheme.light
        XCTAssertEqual(theme.canvas.description, HDColor.canvas.description)
        XCTAssertEqual(theme.ink.description, HDColor.ink.description)
        XCTAssertEqual(theme.deepGreen.description, HDColor.deepGreen.description)
    }

    /// Phase 7: dark theme uses the dedicated darkCanvas / darkInk
    /// tokens rather than the light defaults. The theme may apply
    /// small contrast tweaks (Phase 21) but the core darkCanvas /
    /// darkInk / darkDeepGreen family must remain the reference.
    func testDarkThemeBasics() {
        let theme = HDTheme.dark
        XCTAssertEqual(theme.canvas.description, HDColor.darkCanvas.description)
        XCTAssertEqual(theme.ink.description, HDColor.darkInk.description)
        XCTAssertEqual(theme.deepGreen.description, HDColor.darkDeepGreen.description)
        // Phase 21 audit: dark theme surfaces must be visibly
        // distinct from the canvas so cards/popovers don't blend
        // into the background.
        XCTAssertNotEqual(theme.surface.description, theme.canvas.description,
                          "Dark surface must be distinguishable from canvas")
        XCTAssertNotEqual(theme.surfaceStone.description, theme.canvas.description,
                          "Dark surfaceStone must be distinguishable from canvas")
    }

    /// Phase 7: semantic aliases should resolve to the same color as
    /// the underlying token (catches accidental miswiring).
    func testSemanticAliases() {
        let light = HDTheme.light
        XCTAssertEqual(light.textPrimary.description, light.ink.description)
        XCTAssertEqual(light.textMuted.description, light.muted.description)
        XCTAssertEqual(light.ctaBackground.description, light.primary.description)
    }

    /// Phase 7: default EnvironmentValues.hdTheme is .light so that
    /// views that don't have a HDThemeRoot wrapper don't crash.
    func testDefaultEnvironmentTheme() {
        let env = EnvironmentValues()
        XCTAssertEqual(env.hdTheme.canvas.description, HDTheme.light.canvas.description)
    }

    /// Phase 7: setting an explicit theme via the environment override
    /// makes the change visible to @Environment(\.hdTheme) consumers.
    @MainActor
    func testEnvironmentOverride() {
        var env = EnvironmentValues()
        env.hdTheme = .dark
        XCTAssertEqual(env.hdTheme.canvas.description, HDTheme.dark.canvas.description)
    }
}