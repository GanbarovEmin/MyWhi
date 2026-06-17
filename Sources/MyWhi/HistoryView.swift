// HistoryView.swift
// Last 10 transcripts. Clicking a row copies that transcript to the
// clipboard (same as the rest of the app's copy path).

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if !appState.history.isEmpty {
                    Button("Clear", role: .destructive) {
                        appState.clearHistory()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            if appState.history.isEmpty {
                Text("No transcripts yet. Click Start Recording, speak, then Stop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(appState.history) { entry in
                            HistoryRow(entry: entry) {
                                appState.copyFromHistory(entry)
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let onCopy: () -> Void

    var body: some View {
        Button(action: onCopy) {
            HStack(alignment: .top, spacing: 8) {
                Text(entry.displayTime)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)

                Text(entry.text)
                    .font(.callout)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "doc.on.clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}
