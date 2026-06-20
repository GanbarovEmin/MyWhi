// PersonalDictionaryView.swift
// Phase 19 — UI for editing the user's personal dictionary (the
// list of word replacements applied post-transcription). Power-user
// feature: lets users teach MyWhi their domain vocabulary (e.g.
// company names, technical terms, brand names) without touching the
// underlying JSON file.
//
// The view lives inside SettingsViewDesktop as a card and uses the
// shared HDColor/HDButton components. State is loaded from and
// persisted through PersonalDictionaryStore (which already exists
// for loading; Phase 19 added a save(_:) method).

import SwiftUI

struct PersonalDictionaryView: View {

    @Environment(\.hdTheme) private var theme
    @EnvironmentObject private var appState: AppState

    @State private var entries: [DictionaryReplacement] = []
    @State private var draftFrom: String = ""
    @State private var draftTo: String = ""
    @State private var isLoading: Bool = true
    @State private var showAddSheet: Bool = false

    var body: some View {
        HDCard(.canvas) {
            VStack(alignment: .leading, spacing: HDSpacing.md.rawValue) {
                sectionHeader

                if isLoading {
                    HStack(spacing: HDSpacing.sm.rawValue) {
                        ProgressView().controlSize(.small)
                        Text("Загружается…")
                            .font(HDFont.caption)
                            .foregroundStyle(theme.muted)
                    }
                } else if entries.isEmpty {
                    emptyState
                } else {
                    entryList
                }

                Divider()
                    .padding(.vertical, HDSpacing.xs.rawValue)

                HStack {
                    Text("\(entries.count) записей")
                        .font(HDFont.micro)
                        .foregroundStyle(theme.muted)
                    Spacer()
                    HDButtonSecondary(title: "Добавить запись", icon: "plus") {
                        draftFrom = ""
                        draftTo = ""
                        showAddSheet = true
                    }
                }
            }
        }
        .task {
            await reload()
        }
        .sheet(isPresented: $showAddSheet) {
            addSheet
        }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: HDSpacing.xs.rawValue) {
            Text("СЛОВАРЬ")
                .font(HDFont.monoLabel(size: 12))
                .hdTracking(0.5)
                .foregroundStyle(theme.muted)
            Text("Замены слов после транскрибации")
                .font(HDFont.cardBody)
                .foregroundStyle(theme.ink)
            Text("WhisperKit иногда путает доменные имена. Добавьте сюда замены — они применятся автоматически. Например «айбиэм» → «IBM».")
                .font(HDFont.caption)
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack(spacing: HDSpacing.sm.rawValue) {
            Image(systemName: "character.book.closed")
                .font(HDFont.iconSmall)
                .foregroundStyle(theme.muted)
            Text("Словарь пуст")
                .font(HDFont.caption)
                .foregroundStyle(theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, HDSpacing.sm.rawValue)
    }

    // MARK: - Entry list

    private var entryList: some View {
        VStack(spacing: 1) {
            ForEach(entries.indices, id: \.self) { idx in
                entryRow(entries[idx])
                if idx < entries.count - 1 {
                    Rectangle()
                        .fill(theme.border)
                        .frame(height: 1)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: HDRadius.sm.rawValue, style: .continuous)
                .fill(theme.surface.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: HDRadius.sm.rawValue, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private func entryRow(_ entry: DictionaryReplacement) -> some View {
        HStack(spacing: HDSpacing.sm.rawValue) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.from)
                    .font(HDFont.noteTitle)
                    .foregroundStyle(theme.ink)
                Text(entry.to)
                    .font(HDFont.caption)
                    .foregroundStyle(theme.muted)
            }
            Spacer(minLength: 0)
            Button {
                deleteEntry(entry)
            } label: {
                Image(systemName: "trash")
                    .font(HDFont.iconSmall)
                    .foregroundStyle(theme.error)
            }
            .buttonStyle(.plain)
            .help("Удалить запись")
        }
        .padding(.horizontal, HDSpacing.md.rawValue)
        .padding(.vertical, HDSpacing.sm.rawValue)
    }

    // MARK: - Add sheet

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: HDSpacing.lg.rawValue) {
            VStack(alignment: .leading, spacing: HDSpacing.xs.rawValue) {
                Text("Новая замена")
                    .font(HDFont.featureHeading)
                    .foregroundStyle(theme.ink)
                Text("Заменять каждое вхождение первого слова на второе (без учёта регистра).")
                    .font(HDFont.caption)
                    .foregroundStyle(theme.muted)
            }

            VStack(alignment: .leading, spacing: HDSpacing.xs.rawValue) {
                Text("Как WhisperKit пишет")
                    .font(HDFont.formLabel)
                    .foregroundStyle(theme.ink)
                TextField("например: ашбис", text: $draftFrom)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: HDSpacing.xs.rawValue) {
                Text("Как должно быть")
                    .font(HDFont.formLabel)
                    .foregroundStyle(theme.ink)
                TextField("например: ASBIS", text: $draftTo)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                HDButtonSecondary(title: "Отмена") {
                    showAddSheet = false
                }
                .keyboardShortcut(.escape, modifiers: [])
                HDButtonPrimary(title: "Добавить") {
                    commitDraft()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!canAdd)
            }
        }
        .padding(HDSpacing.xl.rawValue)
        .frame(width: 420)
        .background(theme.canvas)
    }

    private var canAdd: Bool {
        let trimmedFrom = draftFrom.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTo = draftTo.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedFrom.isEmpty && !trimmedTo.isEmpty
    }

    private func commitDraft() {
        let from = draftFrom.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = draftTo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty else { return }
        let newEntry = DictionaryReplacement(from: from, to: to)
        entries.append(newEntry)
        Task { await persist() }
        showAddSheet = false
    }

    private func deleteEntry(_ entry: DictionaryReplacement) {
        entries.removeAll { $0.from == entry.from && $0.to == entry.to }
        Task { await persist() }
    }

    // MARK: - Persistence

    private func reload() async {
        let loaded = await appState.dictionaryStore.load()
        await MainActor.run {
            entries = loaded
            isLoading = false
        }
    }

    private func persist() async {
        await appState.dictionaryStore.save(entries)
    }
}