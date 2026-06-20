// HDTheme.swift
// Theme-aware color resolution. HDColor tokens stay as static light-mode
// defaults; HDTheme bundles both light + dark variants and is read from
// the SwiftUI environment via `@Environment(\.hdTheme)`.
//
// Why a custom theme instead of an Asset catalog?
//   - One source of truth (this file). Adding a new color means adding
//     it here, not generating an asset in two places.
//   - Runtime switching: HDTheme.light/dark can be inspected in code and
//     unit-tested without booting SwiftUI.
//
// Usage:
//   struct MyView: View {
//       @Environment(\.hdTheme) private var theme
//       var body: some View {
//           Text("Hi").foregroundStyle(theme.ink)
//       }
//   }
//
// To opt the whole app into dark mode (from AppState.settings.useDarkMode),
// the root scene wraps content in HDThemeRoot, which reads the system
// colorScheme and injects the matching theme.

import SwiftUI

// MARK: - HDTheme

/// Bundle of all semantic colors for one color scheme.
/// Views read this via `@Environment(\.hdTheme)` — never reach for HDColor
/// directly when theme awareness is needed (the only exception is colors
/// that are theme-invariant, e.g. deepGreen as a brand accent).
struct HDTheme: Equatable {

    // MARK: Surfaces
    var canvas: Color          // primary background
    var surface: Color         // elevated surface (cards, popover)
    var surfaceStone: Color    // warm neutral
    var surfacePaleGreen: Color
    var surfacePaleBlue: Color

    // MARK: Text
    var ink: Color             // primary text
    var muted: Color           // secondary text, metadata
    var bodyMuted: Color       // tertiary
    var slate: Color           // separator text
    var onPrimary: Color       // text on dark CTA
    var onDark: Color          // text on dark surface

    // MARK: Brand & accents
    var primary: Color         // near-black CTA
    var deepGreen: Color       // recording state
    var coral: Color           // taxonomy / accents
    var coralSoft: Color
    var actionBlue: Color
    var focusBlue: Color
    var error: Color

    // MARK: Borders & dividers
    var border: Color          // standard border
    var borderLight: Color
    var hairline: Color
    var cardBorder: Color

    // MARK: Semantic aliases
    var textPrimary: Color { ink }
    var textMuted: Color { muted }
    var textOnDark: Color { onDark }
    var ctaBackground: Color { primary }
}

extension HDTheme {

    /// Light theme — matches the Cohere palette baseline.
    static let light = HDTheme(
        // Surfaces
        canvas:           HDColor.canvas,
        surface:          HDColor.canvas,
        surfaceStone:     HDColor.softStone,
        surfacePaleGreen: HDColor.paleGreen,
        surfacePaleBlue:  HDColor.paleBlue,
        // Text
        ink:              HDColor.ink,
        muted:            HDColor.muted,
        bodyMuted:        HDColor.bodyMuted,
        slate:            HDColor.slate,
        onPrimary:        HDColor.onPrimary,
        onDark:           HDColor.onDark,
        // Brand
        primary:          HDColor.primary,
        deepGreen:        HDColor.deepGreen,
        coral:            HDColor.coral,
        coralSoft:        HDColor.coralSoft,
        actionBlue:       HDColor.actionBlue,
        focusBlue:        HDColor.focusBlue,
        error:            HDColor.error,
        // Borders
        border:           HDColor.borderLight,
        borderLight:      HDColor.borderLight,
        hairline:         HDColor.hairline,
        cardBorder:       HDColor.cardBorder
    )

    /// Dark theme — editorial palette tuned for low-light reading.
    /// Phase 21 audit pass: deeper canvas, brighter elevated surface
    /// for visible separation, more legible muted/bodyMuted on dark bg
    /// (WCAG AA against the canvas). error shifted to a slightly more
    /// saturated red so it doesn't get lost on dark stone surfaces.
    static let dark = HDTheme(
        // Surfaces
        canvas:           HDColor.darkCanvas,
        surface:          HDColor.darkSurface,
        surfaceStone:     Color(hex: "#25252a"),  // warm neutral, distinctly above surface
        surfacePaleGreen: HDColor.darkDeepGreen.opacity(0.30),
        surfacePaleBlue:  Color(hex: "#1a2440"),
        // Text
        ink:              HDColor.darkInk,
        muted:            HDColor.darkMuted,
        bodyMuted:        Color(hex: "#a5a5b0"),
        slate:            Color(hex: "#9595a0"),
        onPrimary:        HDColor.onPrimary,
        onDark:           HDColor.darkInk,
        // Brand — keep accents but tune for dark bg
        primary:          HDColor.darkInk,
        deepGreen:        HDColor.darkDeepGreen,
        coral:            HDColor.coral,
        coralSoft:        HDColor.coralSoft,
        actionBlue:       Color(hex: "#5a8af0"),
        focusBlue:        Color(hex: "#6a8af6"),
        error:            Color(hex: "#ff5252"),
        // Borders
        border:           HDColor.darkBorder,
        borderLight:      HDColor.darkBorder,
        hairline:         HDColor.darkBorder,
        cardBorder:       HDColor.darkBorder
    )
}

// MARK: - Environment

private struct HDThemeKey: EnvironmentKey {
    static let defaultValue: HDTheme = .light
}

extension EnvironmentValues {
    /// Current color theme. Defaults to light; HDThemeRoot overrides based
    /// on the system color scheme (or the user's explicit dark-mode toggle).
    var hdTheme: HDTheme {
        get { self[HDThemeKey.self] }
        set { self[HDThemeKey.self] = newValue }
    }
}

// MARK: - Root provider

/// Wraps a SwiftUI subtree and injects the appropriate HDTheme based on
/// the current color scheme. Use this at the top of every WindowGroup
/// and inside NSHostingController roots for popovers / panels.
///
/// The injection happens via .environment, so children read it through
/// `@Environment(\.hdTheme) var theme`.
struct HDThemeRoot<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .environment(\.hdTheme, colorScheme == .dark ? .dark : .light)
    }
}

// MARK: - Theme reader helper

extension View {
    /// Convenience: read the current theme into a closure. Avoids the
    /// boilerplate of declaring `@Environment(\.hdTheme)` in every view.
    ///
    /// Usage:
    ///   Text("Hi").foregroundStyle(.themed(\.ink))
    func themed<V: ShapeStyle>(_ keyPath: KeyPath<HDTheme, V>) -> some View {
        modifier(HDThemeReader(keyPath: keyPath))
    }

    /// Convenience: when you need a Color (not a ShapeStyle).
    func themedColor(_ keyPath: KeyPath<HDTheme, Color>) -> some View {
        modifier(HDThemeColorReader(keyPath: keyPath))
    }
}

private struct HDThemeReader<V: ShapeStyle>: ViewModifier {
    let keyPath: KeyPath<HDTheme, V>
    @Environment(\.hdTheme) private var theme

    func body(content: Content) -> some View {
        content.foregroundStyle(theme[keyPath: keyPath])
    }
}

private struct HDThemeColorReader: ViewModifier {
    let keyPath: KeyPath<HDTheme, Color>
    @Environment(\.hdTheme) private var theme

    func body(content: Content) -> some View {
        content.foregroundStyle(theme[keyPath: keyPath])
    }
}

// MARK: - HDColor: legacy shim
//
// The static `HDColor.X` tokens remain for callers that don't need theme
// awareness — most importantly SwiftUI controls that don't easily accept
// a closure (e.g. `.background(HDColor.canvas)` in NSHostingController
// roots). New code should prefer `@Environment(\.hdTheme)` and `theme.X`.

extension HDColor {
    /// Use this when a view must opt out of the current theme and always
    /// render the light variant. Almost never needed — prefer the theme.
    static let lightTheme: HDTheme = .light
    static let darkTheme: HDTheme = .dark
}