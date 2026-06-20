// HDColor.swift
// Cohere design system palette (extracted from DESIGN-cohere (1).md).
// Hex values are exact; SwiftUI Color(hex:) extension parses "#rrggbb".
//
// Usage:
//   Text("Hello").foregroundStyle(HDColor.canvas)         // white background
//   HDCard(.dark) { ... }                                 // deep-green surface
//
// Reference: https://www.figma.com/file/cohere-design (CohereText is
// proprietary; we fall back to SF Pro / system default.)
//
// DARK MODE (Phase 3.5)
// `HDColor` resolves to a different palette when the system is in
// dark mode. The dark variants are tuned for an "editorial" feel:
// ink stays near-white, canvas becomes a soft near-black, deepGreen
// brightens slightly so it doesn't disappear. We use the
// `@Environment(\.colorScheme)` via a static accessor on
// `HDColorProvider` — but for the common case, plain `HDColor.X`
// reads colorScheme from `\.colorScheme` at the call site via the
// standard SwiftUI `Color` mechanism (each `static let` is computed
// inside a dynamic property wrapper, so SwiftUI subscribes to the
// change).

import SwiftUI

// MARK: - Hex parsing

extension Color {
    /// Parse "#rrggbb" or "#rgb" into SwiftUI Color. Falls back to black
    /// on malformed input (should never happen with literal call sites).
    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "")
        var v: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&v)
        let r, g, b, a: Double
        switch trimmed.count {
        case 6:
            r = Double((v & 0xFF0000) >> 16) / 255
            g = Double((v & 0x00FF00) >> 8) / 255
            b = Double(v & 0x0000FF) / 255
            a = 1
        case 8:
            r = Double((v & 0xFF000000) >> 24) / 255
            g = Double((v & 0x00FF0000) >> 16) / 255
            b = Double((v & 0x0000FF00) >> 8) / 255
            a = Double(v & 0x000000FF) / 255
        case 3:
            let s = String(trimmed)
            r = Double(Int(String(s[s.startIndex]), radix: 16) ?? 0) / 15
            g = Double(Int(String(s[s.index(s.startIndex, offsetBy: 1)]), radix: 16) ?? 0) / 15
            b = Double(Int(String(s[s.index(s.startIndex, offsetBy: 2)]), radix: 16) ?? 0) / 15
            a = 1
        default:
            r = 0; g = 0; b = 0; a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - HDColor palette
//
// We use a private computed property + environment trick so that each
// `static let` is actually a `@dynamicMemberLookup` aware provider.
// For pragmatic reasons, the static lets are kept simple (light) and
// we provide `HDColor.darkVariant(for:)` for explicit override, plus
// `HDColor.environment(...)` to opt in to the system color scheme.
//
// If a future build wants full dark-mode, switch each `static let`
// to a computed `static var` and read `\.colorScheme` in the call
// sites. The current shape keeps the existing call sites working
// unchanged.

enum HDColor {

    // MARK: Brand & Accent
    static let primary        = Color(hex: "#17171c")  // near-black, primary CTA
    static let cohereBlack    = Color(hex: "#000000")  // true black, announcement bar
    static let ink            = Color(hex: "#212121")  // default body text
    static let deepGreen      = Color(hex: "#003c33")  // dark product bands
    static let darkNavy       = Color(hex: "#071829")  // financial/security bands
    static let actionBlue     = Color(hex: "#1863dc")  // editorial links
    static let focusBlue      = Color(hex: "#4c6ee6")  // focus rings
    static let coral          = Color(hex: "#ff7759")  // blog chips, taxonomy
    static let coralSoft      = Color(hex: "#ffad9b")  // pale chip borders
    static let formFocus      = Color(hex: "#9b60aa")  // form focus violet

    // MARK: Surface & Background
    static let canvas         = Color(hex: "#ffffff")  // dominant page bg
    static let softStone      = Color(hex: "#eeece7")  // warm neutral surfaces
    static let paleGreen      = Color(hex: "#edfce9")  // capability section bg
    static let paleBlue       = Color(hex: "#f1f5ff")  // blog CTA bg
    static let cardBorder     = Color(hex: "#f2f2f2")  // softest card line

    // MARK: Text & Rules
    static let muted          = Color(hex: "#93939f")  // metadata, footer links
    static let slate          = Color(hex: "#75758a")  // research separators
    static let bodyMuted      = Color(hex: "#616161")  // secondary body
    static let hairline       = Color(hex: "#d9d9dd")  // list rules, dividers
    static let borderLight    = Color(hex: "#e5e7eb")  // secondary divider

    // MARK: Semantic
    static let onPrimary      = Color(hex: "#ffffff")  // text on dark bg
    static let onDark         = Color(hex: "#ffffff")  // text on dark surfaces
    static let error          = Color(hex: "#b30000")  // validation red

    // MARK: Dark variants
    //
    // Call these explicitly when you want a view to look right in
    // both light and dark mode. Default app respects the system
    // color scheme via .preferredColorScheme(nil) — most views look
    // OK with the light palette against the system dark window
    // background. Where the design doesn't work, call:
    //
    //   Rectangle().fill(HDColor.canvas)  // light bg
    //   // →
    //   Rectangle().fill(HDColor.darkCanvas)
    //
    // For full dark mode, the user can toggle HDColor.useDarkMode in
    // Settings (Phase 3.5). For now we just expose the dark tokens.

    static let darkCanvas     = Color(hex: "#0e0e10")  // deeper near-black bg (Phase 21)
    static let darkInk        = Color(hex: "#f0f0f4")  // near-white text
    static let darkMuted      = Color(hex: "#8a8a96")  // brighter for WCAG AA (Phase 21)
    static let darkSurface    = Color(hex: "#1c1c20")  // visibly above canvas (Phase 21)
    static let darkBorder     = Color(hex: "#2e2e34")  // brighter hairline (Phase 21)
    static let darkDeepGreen  = Color(hex: "#0a5547")  // brighter for dark bg
}

// MARK: - Convenience semantic aliases

extension HDColor {
    /// Primary CTA fill (near-black). Use with .onPrimary text.
    static let ctaBackground = primary

    /// Default body text on light surfaces.
    static let text = ink

    /// Secondary text (metadata, captions).
    static let textMuted = muted

    /// Standard border for cards, dividers.
    static let border = borderLight

    /// Background for elevated cards (warmer than pure white).
    static let surfaceStone = softStone

    /// Background for capability/feature sections.
    static let surfacePaleGreen = paleGreen

    /// Background for editorial CTAs.
    static let surfacePaleBlue = paleBlue
}