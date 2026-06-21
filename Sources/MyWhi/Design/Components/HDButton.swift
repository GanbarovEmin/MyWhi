// HDButton.swift
// Cohere-style buttons with tactile macOS interaction states.
// Primary (pill, near-black), Secondary (text only), PillOutline, Coral chip.
//
// Phase 7: focus rings for keyboard-only users (`.focused()` +
// `.focusEffectDisabled(false)` + custom visible border on focus).
// Theme-aware so dark mode renders correctly.

import SwiftUI

private struct HDPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .opacity(configuration.isPressed ? 0.86 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - HDButtonPrimary

/// Pill-shaped near-black CTA. The dominant primary action on any surface.
struct HDButtonPrimary: View {
    @Environment(\.hdTheme) private var theme
    @FocusState private var isFocused: Bool

    let title: String
    var icon: String? = nil
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: HDSpacing.sm.rawValue) {
                if let icon {
                    Image(systemName: icon)
                        .font(HDFont.iconSmall)
                }
                Text(LocalizedStringKey(title))
                    .font(HDFont.button)
            }
            .padding(.horizontal, HDSpacing.xl.rawValue)
            .padding(.vertical, HDSpacing.md.rawValue)
            .foregroundStyle(theme.onPrimary)
            .background(
                Capsule()
                    .fill(isEnabled
                          ? (isHovering ? theme.primary.opacity(0.92) : theme.primary)
                          : theme.muted)
            )
            .overlay(
                Capsule()
                    .stroke(isFocused ? theme.focusBlue : Color.clear, lineWidth: 2)
                    .padding(-2)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(HDPressableButtonStyle())
        .disabled(!isEnabled)
        .focused($isFocused)
        .onHover { isHovering = $0 }
    }
}

// MARK: - HDButtonSecondary

/// Text-only action. For lightweight actions where a filled CTA would be noisy.
struct HDButtonSecondary: View {
    @Environment(\.hdTheme) private var theme
    @FocusState private var isFocused: Bool

    let title: String
    var icon: String? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: HDSpacing.xs.rawValue) {
                if let icon {
                    Image(systemName: icon)
                        .font(HDFont.iconSmall)
                }
                Text(LocalizedStringKey(title))
                    .font(HDFont.body)
                    .underline(isHovering || isFocused)
            }
            .foregroundStyle(isHovering || isFocused ? theme.primary : theme.ink)
            .padding(.horizontal, HDSpacing.xs.rawValue)
            .padding(.vertical, HDSpacing.sm.rawValue)
            .background(
                RoundedRectangle(cornerRadius: HDRadius.xs.rawValue, style: .continuous)
                    .fill(isHovering || isFocused
                          ? theme.surfaceStone.opacity(0.65)
                          : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(HDPressableButtonStyle())
        .focused($isFocused)
        .onHover { isHovering = $0 }
    }
}

// MARK: - HDButtonPillOutline

/// 30px-radius pill with transparent fill and 1px dark border.
/// For research filters, taxonomy chips, lightweight tags.
struct HDButtonPillOutline: View {
    @Environment(\.hdTheme) private var theme
    @FocusState private var isFocused: Bool

    let title: String
    var icon: String? = nil
    var isSelected: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: HDSpacing.xs.rawValue) {
                if let icon {
                    Image(systemName: icon)
                        .font(HDFont.iconTiny)
                }
                Text(LocalizedStringKey(title))
                    .font(HDFont.button)
            }
            .padding(.horizontal, HDSpacing.md.rawValue)
            .padding(.vertical, HDSpacing.xs.rawValue)
            .foregroundStyle(isSelected ? theme.onPrimary : theme.primary)
            .background(
                Capsule()
                    .fill(isSelected
                          ? theme.primary
                          : (isHovering ? theme.surfaceStone : Color.clear))
            )
            .overlay(
                Capsule()
                    .stroke(
                        isFocused
                            ? theme.focusBlue
                            : (isSelected || isHovering ? theme.primary : theme.primary.opacity(0.72)),
                        lineWidth: isFocused ? 2 : 1
                    )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(HDPressableButtonStyle())
        .focused($isFocused)
        .onHover { isHovering = $0 }
    }
}

// MARK: - HDButtonCoral (taxonomy chip)

/// Coral chip for taxonomy/filter UI. Use sparingly — never as primary CTA.
struct HDButtonCoral: View {
    @Environment(\.hdTheme) private var theme
    @FocusState private var isFocused: Bool

    let title: String
    var isSelected: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(title))
                .font(HDFont.cardHeading)
                .foregroundStyle(isSelected ? theme.ink : theme.coral)
                .padding(.horizontal, HDSpacing.md.rawValue + 2)
                .padding(.vertical, HDSpacing.sm.rawValue)
                .background(
                    RoundedRectangle(cornerRadius: HDRadius.sm.rawValue, style: .continuous)
                        .fill(isSelected
                              ? theme.coral
                              : (isHovering ? theme.coralSoft.opacity(0.22) : Color.clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: HDRadius.sm.rawValue, style: .continuous)
                        .stroke(
                            isFocused
                                ? theme.focusBlue
                                : (isSelected || isHovering ? theme.coral : theme.coral.opacity(0.75)),
                            lineWidth: isFocused ? 2 : 1
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: HDRadius.sm.rawValue, style: .continuous))
        }
        .buttonStyle(HDPressableButtonStyle())
        .focused($isFocused)
        .onHover { isHovering = $0 }
    }
}
