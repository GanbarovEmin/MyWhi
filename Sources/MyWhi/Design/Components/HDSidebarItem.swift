// HDSidebarItem.swift
// Single row in the desktop sidebar. Used inside NavigationSplitView's
// sidebar List. Designed to work with native macOS sidebar selection
// (accent color) while keeping consistent typography and spacing from
// the Cohere design system.
//
// Example:
//   List(selection: $selection) {
//     HDSidebarItem(icon: "mic", label: "Запись",
//                   section: .home, selection: selection)
//     HDSidebarItem(icon: "doc.text", label: "Scratchpad",
//                   section: .scratchpad, selection: selection, badge: "12")
//   }

import SwiftUI

struct HDSidebarItem<Section: Hashable>: View {
    let icon: String
    let label: String
    let section: Section
    var badge: String? = nil
    var selection: Section? = nil

    private var isSelected: Bool {
        selection == section
    }

    var body: some View {
        HStack(spacing: HDSpacing.md.rawValue) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .frame(width: 20, alignment: .center)
                // Native sidebar selection handles icon color automatically.
                // When not selected, use muted; when selected, let native highlight apply.
                .foregroundStyle(isSelected ? HDColor.primary : HDColor.muted)

            Text(label)
                .font(HDFont.body)
                .foregroundStyle(isSelected ? HDColor.ink : HDColor.bodyMuted)

            Spacer(minLength: 0)

            if let badge {
                Text(badge)
                    .font(HDFont.micro)
                    .foregroundStyle(isSelected ? HDColor.primary : HDColor.muted)
                    .padding(.horizontal, HDSpacing.xs.rawValue + 2)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(isSelected ? HDColor.softStone.opacity(0.5) : HDColor.softStone)
                    )
            }
        }
        .padding(.vertical, HDSpacing.xs.rawValue)
        .padding(.horizontal, HDSpacing.sm.rawValue)
        // Don't add custom background — let native sidebar selection
        // (accent color) handle the highlight. This avoids the conflict
        // between custom background and native blue selection.
        .contentShape(Rectangle())
        .tag(section)
    }
}