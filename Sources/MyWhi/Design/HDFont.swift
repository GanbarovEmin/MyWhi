// HDFont.swift
// Cohere typography scale. CohereText / Unica77 / CohereMono are proprietary
// — we fall back to system fonts that approximate the same proportions:
//
//   - display (CohereText)  →  .system design .default (SF Pro Display)
//   - UI/body (Unica77)     →  .system design .default (SF Pro Text)
//   - mono labels           →  .monospacedSystemFont
//
// Use these helpers instead of raw `.font(.system(size: ...))` calls.
//
// Reference: DESIGN-cohere (1).md "Typography" section.

import SwiftUI

/// Cohere typography scale. All members are static `Font` properties so
/// call sites read `.font(HDFont.cardHeading)` without parentheses.
enum HDFont {

    // MARK: Display (CohereText fallback → SF Pro Display)

    /// Hero display, 96px / weight 400 / tracking -1.92px.
    static let heroDisplay = Font.system(size: 96, weight: .regular, design: .default)

    /// Product display, 72px / weight 400 / tracking -1.44px.
    static let productDisplay = Font.system(size: 72, weight: .regular, design: .default)

    /// Section display, 60px / weight 400 / tracking -1.20px.
    static let sectionDisplay = Font.system(size: 60, weight: .regular, design: .default)

    /// Section heading, 48px / weight 400 / tracking -0.48px.
    static let sectionHeading = Font.system(size: 48, weight: .regular, design: .default)

    /// Card heading, 32px / weight 400 / tracking -0.32px.
    static let cardHeading = Font.system(size: 32, weight: .regular, design: .default)

    /// Feature heading, 24px / weight 400.
    static let featureHeading = Font.system(size: 24, weight: .regular, design: .default)

    // MARK: UI / Body (Unica77 fallback → SF Pro Text)

    /// Body large, 18px / weight 400 / line-height 1.40.
    static let bodyLarge = Font.system(size: 18, weight: .regular, design: .default)

    /// Body, 16px / weight 400 / line-height 1.50.
    static let body = Font.system(size: 16, weight: .regular, design: .default)

    /// Button label, 14px / weight 500 / line-height 1.71.
    static let button = Font.system(size: 14, weight: .medium, design: .default)

    /// Caption, 14px / weight 400.
    static let caption = Font.system(size: 14, weight: .regular, design: .default)

    /// Micro, 12px / weight 400.
    static let micro = Font.system(size: 12, weight: .regular, design: .default)

    // MARK: Mono (CohereMono fallback → SF Mono)

    /// Mono label, 14px / tracking 0.28px. For uppercase technical tags.
    static let monoLabel = Font.system(size: 14, weight: .regular, design: .monospaced)

    /// Mono label at a custom size.
    static func monoLabel(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Tracking helpers

extension View {
    /// Apply tracking like Cohere's display headlines.
    /// Note: SwiftUI kerning is positive-only; pass absolute tracking value
    /// and the renderer will use it. For negative Cohere tracking, callers
    /// can omit this modifier (SwiftUI uses default tracking per font).
    func hdTracking(_ points: CGFloat) -> some View {
        self.kerning(points)
    }
}