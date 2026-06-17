// HDSidebarItem.swift
// Single row in the desktop sidebar. Used inside NavigationSplitView's
// sidebar List.
//
// Example:
//   List(selection: $selection) {
//     HDSidebarItem(icon: "mic", label: "Запись",
//                   section: .home, selection: selection)
//     HDSidebarItem(icon: "doc.text", label: "Scratchpad",
//                   section: .scratchpad, selection: selection, badge: "12")
//     ...
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
                .foregroundStyle(isSelected ? HDColor.primary : HDColor.muted)

            Text(label)
                .font(.system(size: 14, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? HDColor.ink : HDColor.bodyMuted)

            Spacer(minLength: 0)

            if let badge {
                Text(badge)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HDColor.muted)
                    .padding(.horizontal, HDSpacing.xs.rawValue + 2)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(HDColor.softStone)
                    )
            }
        }
        .padding(.vertical, HDSpacing.xs.rawValue + 2)
        .padding(.horizontal, HDSpacing.sm.rawValue)
        .background(
            RoundedRectangle(cornerRadius: HDRadius.xs.rawValue, style: .continuous)
                .fill(isSelected ? HDColor.softStone : Color.clear)
        )
        .contentShape(Rectangle())
        .tag(section)
    }
}