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
                .foregroundStyle(isSelected ? .primary : HDColor.muted)

            Text(label)
                .font(HDFont.body)
                .foregroundStyle(isSelected ? .primary : HDColor.bodyMuted)

            Spacer(minLength: 0)

            if let badge {
                Text(badge)
                    .font(HDFont.micro)
                    .foregroundStyle(isSelected ? .primary : HDColor.muted)
                    .padding(.horizontal, HDSpacing.xs.rawValue + 2)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(isSelected ? HDColor.softStone.opacity(0.3) : HDColor.softStone)
                    )
            }
        }
        .padding(.vertical, HDSpacing.xs.rawValue)
        .padding(.horizontal, HDSpacing.sm.rawValue)
        .contentShape(Rectangle())
        .tag(section)
    }
}