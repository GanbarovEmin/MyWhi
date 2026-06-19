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
// Phase 7 additions: every UI-facing font size is now a token here. The
// previous scale only covered a handful of sizes (10/12/14/16/18/24/32/…)
// and views were reaching for raw `.system(size: X, weight: Y)` for all
// the in-between sizes. New tokens cover the full UI surface and include
// semantic names (`actionLabel`, `noteTitle`, `hotkeyTitle`, …) so the
// design intent survives a font swap.
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

    /// 18pt semibold — for the MyWhi brand title in desktop sidebar.
    static let brandTitle = Font.system(size: 18, weight: .semibold, design: .default)

    /// 10pt medium — for the engine indicator footer icon.
    static let engineIcon = Font.system(size: 10, weight: .medium, design: .default)

    /// 56pt ultralight — for empty state hero icons.
    static let emptyHero = Font.system(size: 56, weight: .ultraLight, design: .default)

    /// 44pt ultralight — for inline empty state icons.
    static let emptyInline = Font.system(size: 44, weight: .ultraLight, design: .default)

    /// 14pt semibold — for the HUD title (e.g. "Слушаю").
    static let hudTitle = Font.system(size: 14, weight: .semibold, design: .default)

    /// 18pt semibold — for the HUD status glyph icon.
    static let hudGlyph = Font.system(size: 18, weight: .semibold, design: .default)

    /// 11pt semibold — for the HUD close (xmark) button.
    static let hudIconClose = Font.system(size: 11, weight: .semibold, design: .default)

    /// 12pt semibold — for the HUD stop (stop.fill) button.
    static let hudIconStop = Font.system(size: 12, weight: .semibold, design: .default)

    /// 13pt regular — for the HUD live partial transcript (Phase 8).
    static let hudLiveText = Font.system(size: 13, weight: .regular, design: .default)

    /// 12pt medium — for filter chip buttons (Phase 10).
    static let filterChip = Font.system(size: 12, weight: .medium, design: .default)

    /// 13pt regular — for form row labels in Settings.
    static let bodySmall = Font.system(size: 13, weight: .regular, design: .default)

    /// 13pt medium/regular — for Scratchpad row titles (weight toggled via .fontWeight).
    static let scratchpadTitle = Font.system(size: 13, weight: .regular, design: .default)

    /// 11pt regular — for Scratchpad row metadata.
    static let scratchpadMeta = Font.system(size: 11, weight: .regular, design: .default)

    /// 18pt regular — for the wave icon in OnboardingCard.
    static let waveIcon = Font.system(size: 18, weight: .regular, design: .default)

    /// 16pt regular — for sidebar row icons.
    static let sidebarIcon = Font.system(size: 16, weight: .regular, design: .default)

    /// 11pt medium — for stat-tile delta arrow icon.
    static let statDeltaIcon = Font.system(size: 11, weight: .medium, design: .default)

    /// 13pt regular — for stat-tile delta text.
    static let statDelta = Font.system(size: 13, weight: .regular, design: .default)

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

    // MARK: Semantic UI tokens (Phase 7)
    //
    // These tokens name a specific role in the UI so future design tweaks
    // (e.g. "all hotkey subtitles go from 10 to 11 px") happen in one
    // place. Call sites read `.font(HDFont.noteTitle)` instead of
    // `.font(.system(size: 12, weight: .regular))`.

    /// 22pt semibold — for status glyph in popover header.
    static let titleGlyph = Font.system(size: 22, weight: .semibold, design: .default)

    /// 13pt medium — for the primary action label next to the record button.
    static let actionLabel = Font.system(size: 13, weight: .medium, design: .default)

    /// 12pt medium — for the "Отменить" / discard link button.
    static let discardLabel = Font.system(size: 12, weight: .medium, design: .default)

    /// 13pt regular — for last-transcript preview body.
    static let cardBody = Font.system(size: 13, weight: .regular, design: .default)

    /// 12pt regular — for note titles in recent lists.
    static let noteTitle = Font.system(size: 12, weight: .regular, design: .default)

    /// 10pt regular — for note metadata (time, word count).
    static let noteMeta = Font.system(size: 10, weight: .regular, design: .default)

    /// 11pt medium — for hotkey hint title.
    static let hotkeyTitle = Font.system(size: 11, weight: .medium, design: .default)

    /// 10pt regular — for hotkey hint subtitle.
    static let hotkeySub = Font.system(size: 10, weight: .regular, design: .default)

    /// 14pt medium — for SF Symbols used as button icons.
    static let iconSmall = Font.system(size: 14, weight: .medium, design: .default)

    /// 12pt regular — for SF Symbols used as list icons / tiny badges.
    static let iconTiny = Font.system(size: 12, weight: .regular, design: .default)

    /// 11pt medium — for sidebar labels / nav items (legacy).
    static let navLabel = Font.system(size: 11, weight: .medium, design: .default)

    /// 18pt semibold — for hero stat values.
    static let statValue = Font.system(size: 18, weight: .semibold, design: .default)

    /// 13pt medium — for stat labels / form labels.
    static let formLabel = Font.system(size: 13, weight: .medium, design: .default)

    /// 16pt medium — for status headline in Home view.
    static let statusHeadline = Font.system(size: 16, weight: .medium, design: .default)

    /// 14pt regular — for empty state headlines.
    static let emptyHeadline = Font.system(size: 14, weight: .regular, design: .default)

    /// 14pt monospaced — for the Scratchpad editor body.
    static let editorBody = Font.system(size: 14, weight: .regular, design: .monospaced)

    /// 10pt medium — for small badges / engine pills.
    static let badge = Font.system(size: 10, weight: .medium, design: .default)

    /// 11pt medium — for inline code labels in toolbar.
    static let toolbarLabel = Font.system(size: 11, weight: .medium, design: .default)

    /// 18pt regular — for Settings card headings.
    static let settingsCardTitle = Font.system(size: 18, weight: .regular, design: .default)
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