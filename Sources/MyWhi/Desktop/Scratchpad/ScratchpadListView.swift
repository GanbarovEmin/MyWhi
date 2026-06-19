// ScratchpadListView.swift
// Left pane of the Scratchpad section. Searchable, grouped transcript list
// backed by the in-memory VaultIndex through StatsObserver.

import SwiftUI

struct ScratchpadListView: View {

    @Binding var selection: TranscriptNote?
    @EnvironmentObject private var statsObserver: StatsObserver

    @State private var searchText: String = ""
    @State private var searchResults: [TranscriptNote] = []
    @State private var searchTask: Task<Void, Never>?

    private var visibleNotes: [TranscriptNote] {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? statsObserver.notes
            : searchResults
    }

    var body: some View {
        VStack(spacing: 0) {
            ScratchpadSearchField(text: $searchText) { query in
                runSearch(query)
            }

            if visibleNotes.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(HDColor.canvas)
        .task {
            await statsObserver.refresh()
            if selection == nil {
                selection = statsObserver.notes.first
            }
        }
        .onChange(of: statsObserver.notes) { _, _ in
            runSearch(searchText)
            if selection == nil {
                selection = visibleNotes.first
            }
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(groupedNotes(), id: \.id) { group in
                Section {
                    ForEach(group.notes, id: \.id) { note in
                        ScratchpadRow(
                            note: note,
                            isSelected: selection?.id == note.id
                        )
                        .tag(note)
                        .listRowInsets(EdgeInsets(
                            top: HDSpacing.xs.rawValue,
                            leading: HDSpacing.md.rawValue,
                            bottom: HDSpacing.xs.rawValue,
                            trailing: HDSpacing.md.rawValue
                        ))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    Text(group.title)
                        .font(HDFont.monoLabel(size: 10, weight: .medium))
                        .hdTracking(0.5)
                        .foregroundStyle(HDColor.muted)
                        .padding(.top, HDSpacing.sm.rawValue)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(HDColor.canvas)
    }

    private var emptyState: some View {
        VStack(spacing: HDSpacing.lg.rawValue) {
            Image(systemName: searchText.isEmpty ? "doc.text" : "magnifyingglass")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(HDColor.muted)

            VStack(spacing: HDSpacing.xs.rawValue) {
                Text(searchText.isEmpty ? "Скажи что-нибудь" : "Ничего не найдено")
                    .font(HDFont.featureHeading)
                    .foregroundStyle(HDColor.ink)

                Text(searchText.isEmpty
                     ? "Новые транскрибации появятся здесь."
                     : "Попробуй другой запрос.")
                    .font(HDFont.caption)
                    .foregroundStyle(HDColor.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(HDSpacing.xl.rawValue)
    }

    private func runSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()

        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }

        searchTask = Task { @MainActor in
            let results = await statsObserver.search(trimmed)
            guard !Task.isCancelled else { return }
            searchResults = results
        }
    }

    private func groupedNotes() -> [ScratchpadGroup] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today

        var todayNotes: [TranscriptNote] = []
        var yesterdayNotes: [TranscriptNote] = []
        var weekNotes: [TranscriptNote] = []
        var older: [Date: [TranscriptNote]] = [:]

        for note in visibleNotes.sorted(by: { $0.frontmatter.createdAt > $1.frontmatter.createdAt }) {
            let day = calendar.startOfDay(for: note.frontmatter.createdAt)
            if day == today {
                todayNotes.append(note)
            } else if day == yesterday {
                yesterdayNotes.append(note)
            } else if day >= weekAgo {
                weekNotes.append(note)
            } else {
                older[day, default: []].append(note)
            }
        }

        var groups: [ScratchpadGroup] = []
        if !todayNotes.isEmpty {
            groups.append(ScratchpadGroup(id: "today", title: "Сегодня", notes: todayNotes))
        }
        if !yesterdayNotes.isEmpty {
            groups.append(ScratchpadGroup(id: "yesterday", title: "Вчера", notes: yesterdayNotes))
        }
        if !weekNotes.isEmpty {
            groups.append(ScratchpadGroup(id: "week", title: "На этой неделе", notes: weekNotes))
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "ru_RU")

        for day in older.keys.sorted(by: >) {
            groups.append(ScratchpadGroup(
                id: ISO8601DateFormatter().string(from: day),
                title: formatter.string(from: day),
                notes: older[day]?.sorted(by: { $0.frontmatter.createdAt > $1.frontmatter.createdAt }) ?? []
            ))
        }

        return groups
    }
}

private struct ScratchpadGroup: Identifiable {
    let id: String
    let title: String
    let notes: [TranscriptNote]
}

// MARK: - Row

private struct ScratchpadRow: View {
    let note: TranscriptNote
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? .primary : HDColor.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: HDSpacing.xs.rawValue) {
                Text(timeAgoString(from: note.frontmatter.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .primary : HDColor.muted)

                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .primary : HDColor.muted)

                Text("\(note.frontmatter.words) слов")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .primary : HDColor.muted)

                Spacer(minLength: 0)

                if note.frontmatter.engine == "faster-whisper" {
                    Text("py")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(isSelected ? HDColor.paleBlue.opacity(0.5) : HDColor.paleBlue)
                        )
                        .foregroundStyle(isSelected ? .primary : HDColor.actionBlue)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func timeAgoString(from date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)

        if calendar.isDateInToday(date) {
            return time
        }
        if calendar.isDateInYesterday(date) {
            return "Вчера · \(time)"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
