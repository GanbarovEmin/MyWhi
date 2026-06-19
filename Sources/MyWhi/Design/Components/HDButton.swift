// HDButton.swift
// Cohere-style buttons with tactile macOS interaction states.
// Primary (pill, near-black), Secondary (text only), PillOutline, Coral chip.

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
                        .font(.system(size: 14, weight: .medium))
                }
                Text(title)
                    .font(HDFont.button)
            }
            .padding(.horizontal, HDSpacing.xl.rawValue)
            .padding(.vertical, HDSpacing.md.rawValue)
            .foregroundStyle(HDColor.onPrimary)
            .background(
                Capsule()
                    .fill(isEnabled ? HDColor.primary.opacity(isHovering ? 0.92 : 1.0) : HDColor.muted)
            )
            .overlay(
                Capsule()
                    .stroke(HDColor.onPrimary.opacity(isHovering ? 0.18 : 0), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(HDPressableButtonStyle())
        .disabled(!isEnabled)
        .onHover { isHovering = $0 }
    }
}

// MARK: - HDButtonSecondary

/// Text-only action. For lightweight actions where a filled CTA would be noisy.
struct HDButtonSecondary: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: HDSpacing.xs.rawValue) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .regular))
                }
                Text(title)
                    .font(HDFont.body)
                    .underline(isHovering)
            }
            .foregroundStyle(isHovering ? HDColor.primary : HDColor.ink)
            .padding(.horizontal, HDSpacing.xs.rawValue)
            .padding(.vertical, HDSpacing.sm.rawValue)
            .background(
                RoundedRectangle(cornerRadius: HDRadius.xs.rawValue, style: .continuous)
                    .fill(isHovering ? HDColor.softStone.opacity(0.65) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(HDPressableButtonStyle())
        .onHover { isHovering = $0 }
    }
}

// MARK: - HDButtonPillOutline

/// 30px-radius pill with transparent fill and 1px dark border.
/// For research filters, taxonomy chips, lightweight tags.
struct HDButtonPillOutline: View {
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
                        .font(.system(size: 12, weight: .regular))
                }
                Text(title)
                    .font(HDFont.button)
            }
            .padding(.horizontal, HDSpacing.md.rawValue)
            .padding(.vertical, HDSpacing.xs.rawValue)
            .foregroundStyle(isSelected ? HDColor.onPrimary : HDColor.primary)
            .background(
                Capsule()
                    .fill(isSelected ? HDColor.primary : (isHovering ? HDColor.softStone : Color.clear))
            )
            .overlay(
                Capsule()
                    .stroke(HDColor.primary.opacity(isHovering || isSelected ? 1 : 0.72), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(HDPressableButtonStyle())
        .onHover { isHovering = $0 }
    }
}

// MARK: - HDButtonCoral (taxonomy chip)

/// Coral chip for taxonomy/filter UI. Use sparingly — never as primary CTA.
struct HDButtonCoral: View {
    let title: String
    var isSelected: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(isSelected ? HDColor.ink : HDColor.coral)
                .padding(.horizontal, HDSpacing.md.rawValue + 2)
                .padding(.vertical, HDSpacing.sm.rawValue)
                .background(
                    RoundedRectangle(cornerRadius: HDRadius.sm.rawValue, style: .continuous)
                        .fill(isSelected ? HDColor.coral : (isHovering ? HDColor.coralSoft.opacity(0.22) : Color.clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: HDRadius.sm.rawValue, style: .continuous)
                        .stroke(HDColor.coral.opacity(isHovering || isSelected ? 1 : 0.75), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: HDRadius.sm.rawValue, style: .continuous))
        }
        .buttonStyle(HDPressableButtonStyle())
        .onHover { isHovering = $0 }
    }
}
