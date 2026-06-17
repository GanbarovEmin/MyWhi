// HDButton.swift
// Cohere-style buttons: Primary (pill, near-black), Secondary (text only),
// PillOutline (transparent + 1px dark border).
//
// Usage:
//   HDButtonPrimary(title: "Submit") { submit() }
//   HDButtonSecondary(title: "Cancel") { cancel() }
//   HDButtonPillOutline(title: "Filter") { filter() }
//
// Optional SF Symbol icon:
//   HDButtonPrimary(title: "Save", icon: "tray.and.arrow.down") { ... }

import SwiftUI

// MARK: - HDButtonPrimary

/// Pill-shaped near-black CTA. The dominant primary action on any surface.
struct HDButtonPrimary: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

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
                    .fill(isEnabled ? HDColor.primary : HDColor.muted)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

// MARK: - HDButtonSecondary

/// Text-only action with underline. For "Explore", "Try", "Learn more" etc.
struct HDButtonSecondary: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: HDSpacing.xs.rawValue) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .regular))
                }
                Text(title)
                    .font(HDFont.body)
                    .underline()
            }
            .foregroundStyle(HDColor.ink)
            .padding(.horizontal, 0)
            .padding(.vertical, HDSpacing.sm.rawValue)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    .fill(isSelected ? HDColor.primary : Color.clear)
            )
            .overlay(
                Capsule()
                    .stroke(HDColor.primary, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - HDButtonCoral (taxonomy chip)

/// Coral chip for blog taxonomy. Use sparingly — never as primary CTA.
/// Matches `blog-filter-chip` in the Cohere design system.
struct HDButtonCoral: View {
    let title: String
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(isSelected ? HDColor.ink : HDColor.coral)
                .padding(.horizontal, HDSpacing.md.rawValue + 2)
                .padding(.vertical, HDSpacing.sm.rawValue)
                .background(
                    RoundedRectangle(cornerRadius: HDRadius.sm.rawValue, style: .continuous)
                        .fill(isSelected ? HDColor.coral : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: HDRadius.sm.rawValue, style: .continuous)
                        .stroke(HDColor.coral, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}