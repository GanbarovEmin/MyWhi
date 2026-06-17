// ScratchpadSearchField.swift
// Search input for the Scratchpad list. Cmd+F focuses from the parent.

import SwiftUI

struct ScratchpadSearchField: View {

    @Binding var text: String
    let onChange: (String) -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: HDSpacing.sm.rawValue) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(HDColor.muted)

            TextField("Поиск по транскрибациям", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)
                .onSubmit { onChange(text) }
                .onChange(of: text) { _, newValue in
                    onChange(newValue)
                }

            if !text.isEmpty {
                Button {
                    text = ""
                    onChange("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(HDColor.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, HDSpacing.md.rawValue)
        .padding(.vertical, HDSpacing.sm.rawValue + 2)
        .background(
            RoundedRectangle(cornerRadius: HDRadius.sm.rawValue, style: .continuous)
                .fill(HDColor.softStone)
        )
        .padding(.horizontal, HDSpacing.md.rawValue)
        .padding(.vertical, HDSpacing.sm.rawValue)
        .background(HDColor.canvas)
    }
}