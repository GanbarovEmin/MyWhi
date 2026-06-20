// ScratchpadListView.swift
// Left pane of the Scratchpad section. Searchable, grouped transcript list
// backed by the in-memory VaultIndex through StatsObserver.
//
// Phase 7: HDTheme migration, hardcoded fonts → HDFont tokens.

import SwiftUI

struct ScratchpadListView: View {

    @Binding var selection: TranscriptNote?
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var statsObserver: StatsObserver
    @Environment(\.hdTheme) private var theme

    @State private var searchText: String = ""
    @State private var searchResults: [TranscriptNote] = []
    @State private var searchTask: Task<Void, Never>?

    // Phase 10: date-range filter chips.
    enum DateFilter: String, CaseIterable, Identifiable {
        case all, today, week, month
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:    return "Всё"
            case .today:  return "Сегодня"
            case .week:   return "Неделя"
            case .month:  return "Месяц"
            }
        }
        /// Calendar predicate applied after search.
        func matches(_ date: Date) -> Bool {
            let cal = Calendar.current
            switch self {
            case .all:    return true
            case .today:  return cal.isDateInToday(date)
            case .week:
                let weekAgo = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: Date()))!
                return date >= weekAgo
            case .month:
                let monthAgo = cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: Date()))!
                return date >= monthAgo
            }
        }
    }
    @State private var dateFilter: DateFilter = .all

    private var visibleNotes: [TranscriptNote] {
        let base = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? statsObserver.notes
            : searchResults
        return base.filter { dateFilter.matches($0.frontmatter.createdAt) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScratchpadSearchField(text: $searchText) { query in
                runSearch(query)
            }
            // Phase 10: chip-row filter. Sits right under the search
            // field so the relationship to "I'm filtering these results"
            // is obvious.
            DateFilterChips(selection: $dateFilter)

            if visibleNotes.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(theme.canvas)
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
                        .foregroundStyle(theme.muted)
                        .padding(.top, HDSpacing.sm.rawValue)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(theme.canvas)
    }

    private var emptyState: some View {
        VStack(spacing: HDSpacing.lg.rawValue) {
            Image(systemName: searchText.isEmpty ? "doc.text" : "magnifyingglass")
                .font(HDFont.emptyInline)
                .foregroundStyle(theme.muted)

            VStack(spacing: HDSpacing.xs.rawValue) {
                Text(searchText.isEmpty ? "Скажи что-нибудь" : "Ничего не найдено")
                    .font(HDFont.featureHeading)
                    .foregroundStyle(theme.ink)

                Text(searchText.isEmpty
                     ? "Новые транскрибации появятся здесь."
                     : "Попробуй другой запрос.")
                    .font(HDFont.caption)
                    .foregroundStyle(theme.muted)
                    .multilineTextAlignment(.center)
            }

            if searchText.isEmpty {
                Button {
                    appState.toggleRecording()
                } label: {
                    Label(emptyRecordTitle, systemImage: emptyRecordIcon)
                        .font(HDFont.actionLabel)
                        .padding(.horizontal, HDSpacing.lg.rawValue)
                        .padding(.vertical, HDSpacing.sm.rawValue)
                        .background(
                            Capsule()
                                .fill(appState.status == .recording ? theme.deepGreen : theme.primary)
                        )
                        .foregroundStyle(theme.onPrimary)
                }
                .buttonStyle(.plain)
                .disabled(appState.status == .transcribing)
                .help(emptyRecordHelp)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(HDSpacing.xl.rawValue)
    }

    private var emptyRecordTitle: String {
        switch appState.status {
        case .recording:
            return "Остановить запись"
        case .transcribing:
            return "Транскрибация..."
        default:
            return "Начать запись"
        }
    }

    private var emptyRecordIcon: String {
        switch appState.status {
        case .recording:
            return "stop.fill"
        case .transcribing:
            return "waveform"
        default:
            return "record.circle"
        }
    }

    private var emptyRecordHelp: String {
        switch appState.status {
        case .recording:
            return "Остановить текущую запись"
        case .transcribing:
            return "Подождите, пока закончится транскрибация"
        default:
            return "Начать запись прямо из Scratchpad"
        }
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

// MARK: - Date filter chips (Phase 10)

/// Horizontal row of chip-style buttons that narrow the list to a
/// date range. Sits directly under the search field so the visual
/// relationship is obvious.
private struct DateFilterChips: View {
    @Environment(\.hdTheme) private var theme
    @Binding var selection: ScratchpadListView.DateFilter

    var body: some View {
        HStack(spacing: HDSpacing.xs.rawValue) {
            ForEach(ScratchpadListView.DateFilter.allCases) { f in
                Button {
                    selection = f
                } label: {
                    Text(f.label)
                        .font(HDFont.filterChip)
                        .padding(.horizontal, HDSpacing.md.rawValue)
                        .padding(.vertical, HDSpacing.xxs.rawValue + 2)
                        .foregroundStyle(selection == f ? theme.onPrimary : theme.bodyMuted)
                        .background(
                            Capsule()
                                .fill(selection == f ? theme.primary : theme.surfaceStone)
                        )
                        .overlay(
                            Capsule()
                                .stroke(theme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HDSpacing.md.rawValue)
        .padding(.vertical, HDSpacing.xs.rawValue)
    }
}

// MARK: - Row

private struct ScratchpadRow: View {
    @Environment(\.hdTheme) private var theme

    let note: TranscriptNote
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title)
                .font(HDFont.scratchpadTitle)
                .foregroundStyle(isSelected ? theme.ink : theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: HDSpacing.xs.rawValue) {
                Text(timeAgoString(from: note.frontmatter.createdAt))
                    .font(HDFont.scratchpadMeta)
                    .foregroundStyle(theme.muted)

                Text("·")
                    .font(HDFont.scratchpadMeta)
                    .foregroundStyle(theme.muted)

                Text("\(note.frontmatter.words) слов")
                    .font(HDFont.scratchpadMeta)
                    .foregroundStyle(theme.muted)

                Spacer(minLength: 0)

                if note.frontmatter.engine == "faster-whisper" {
                    Text("py")
                        .font(HDFont.badge)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(theme.surfacePaleBlue)
                        )
                        .foregroundStyle(theme.actionBlue)
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
