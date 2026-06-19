// HDSidebarItem.swift
// Single row in the desktop sidebar. Used inside NavigationSplitView's
// sidebar List. Designed to work with native macOS sidebar selection
// (accent color) while keeping consistent typography and spacing from
// the Cohere design system.
//
// Phase 7: HDTheme migration + hover state (soft-stone fill on hover,
// not just on selected).
//
// Example:
//   List(selection: $selection) {
//     HDSidebarItem(icon: "mic", label: "Запись",
//                   section: .home, selection: selection)
//     HDSidebarItem(icon: "doc.text", label: "Scratchpad",
//                   section: .scratchpad, badge: "12", selection: selection)
//   }

import SwiftUI

struct HDSidebarItem<Section: Hashable>: View {
    @Environment(\.hdTheme) private var theme
    @State private var isHovering: Bool = false

    let icon: String
    let label: String
    let section: Section
    var badge: String? = nil
    var selection: Section? = nil

    private var isSelected: Bool {
        selection == section
    }

    private var rowBackground: Color {
        if isSelected {
            return theme.surfaceStone.opacity(0.6)
        }
        if isHovering {
            return theme.surfaceStone.opacity(0.3)
        }
        return Color.clear
    }

    private var iconColor: Color {
        isSelected ? theme.ink : (isHovering ? theme.ink : theme.muted)
    }

    private var labelColor: Color {
        isSelected ? theme.ink : (isHovering ? theme.ink : theme.bodyMuted)
    }

    private var badgeColor: Color {
        isSelected ? theme.ink : theme.muted
    }

    private var badgeBackground: Color {
        theme.surfaceStone.opacity(isSelected ? 0.55 : (isHovering ? 0.45 : 0.3))
    }

    var body: some View {
        HStack(spacing: HDSpacing.md.rawValue) {
            Image(systemName: icon)
                .font(HDFont.sidebarIcon)
                .frame(width: 20, alignment: .center)
                .foregroundStyle(iconColor)

            Text(label)
                .font(HDFont.body)
                .foregroundStyle(labelColor)

            Spacer(minLength: 0)

            if let badge {
                Text(badge)
                    .font(HDFont.micro)
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, HDSpacing.xs.rawValue + 2)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(badgeBackground)
                    )
            }
        }
        .padding(.vertical, HDSpacing.xs.rawValue)
        .padding(.horizontal, HDSpacing.sm.rawValue)
        .background(
            RoundedRectangle(cornerRadius: HDRadius.xs.rawValue, style: .continuous)
                .fill(rowBackground)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .tag(section)
    }
}