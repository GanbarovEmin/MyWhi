// SettingsView.swift
// Inline settings disclosure. Keeps the popover compact while exposing
// the four fields from the spec.

import SwiftUI

struct SettingsDisclosure: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        DisclosureGroup {
            SettingsView()
                .padding(.top, 8)
        } label: {
            Label("Settings", systemImage: "gear")
                .font(.subheadline)
        }

        HStack {
            Spacer()
            Button("Quit Hermes Dictate") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Model", selection: $appState.settings.modelSize) {
                ForEach(AppSettings.availableModels, id: \.self) { m in
                    Text(m).tag(m)
                }
            }
            .pickerStyle(.menu)

            Picker("Language", selection: $appState.settings.language) {
                ForEach(AppSettings.availableLanguages, id: \.code) { lang in
                    Text(lang.label).tag(lang.code)
                }
            }
            .pickerStyle(.menu)

            Toggle("Auto copy to clipboard", isOn: $appState.settings.autoCopy)
            Toggle("Save history (last 10)", isOn: $appState.settings.saveHistory)

            HStack {
                Text("Python: \(shortPath(appState.settings.pythonPath))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
        }
        .controlSize(.small)
    }

    private func shortPath(_ p: String) -> String {
        let home = NSHomeDirectory()
        if p.hasPrefix(home) {
            return "~" + p.dropFirst(home.count)
        }
        return p
    }
}
