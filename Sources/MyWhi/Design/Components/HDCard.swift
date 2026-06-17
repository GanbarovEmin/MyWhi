// HDCard.swift
// Cohere-style cards. Three variants match the design system:
//   .canvas  — white surface, hairline border (default card)
//   .stone   — soft-stone warm neutral surface
//   .dark    — deep-green product band, white text
//
// Reference: DESIGN-cohere (1).md "Components" — `product-card`,
// `hero-photo-card`, `contact-form-card`, `dark-feature-band`.

import SwiftUI

enum HDCardVariant {
    case canvas  // white surface, 1px borderLight
    case stone   // soft-stone warm neutral
    case dark    // deep-green, white text
}

struct HDCard<Content: View>: View {
    let variant: HDCardVariant
    var cornerRadius: HDRadius = .lg
    var padding: HDSpacing = .xl
    let content: () -> Content

    init(
        _ variant: HDCardVariant = .canvas,
        cornerRadius: HDRadius = .lg,
        padding: HDSpacing = .xl,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.variant = variant
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content
    }

    private var backgroundColor: Color {
        switch variant {
        case .canvas: return HDColor.canvas
        case .stone:  return HDColor.softStone
        case .dark:   return HDColor.deepGreen
        }
    }

    private var borderColor: Color {
        switch variant {
        case .canvas: return HDColor.borderLight
        case .stone:  return Color.clear
        case .dark:   return Color.white.opacity(0.08)
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .dark: return HDColor.onDark
        default:    return HDColor.ink
        }
    }

    var body: some View {
        content()
            .padding(padding.rawValue)
            .foregroundStyle(foregroundColor)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius.rawValue, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius.rawValue, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
    }
}

// MARK: - Section band (full-width dark)

/// Full-width dark green band. Used in Insights for hero stats and in
/// feature blocks. The Cohere `dark-feature-band` token.
struct HDSectionBand<Content: View>: View {
    var cornerRadius: HDRadius = .lg
    var padding: HDSpacing = .section
    let content: () -> Content

    init(
        cornerRadius: HDRadius = .lg,
        padding: HDSpacing = .section,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding.rawValue)
            .foregroundStyle(HDColor.onDark)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius.rawValue, style: .continuous)
                    .fill(HDColor.deepGreen)
            )
    }
}