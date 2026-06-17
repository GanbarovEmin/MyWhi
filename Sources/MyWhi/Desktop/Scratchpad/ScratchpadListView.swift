// ScratchpadListView.swift
// Left pane of the Scratchpad section. Search field + grouped list of
// transcript notes. Date groupings: Сегодня / Вчера / На этой неделе
// / older by month.

import SwiftUI

struct ScratchpadListView: View {

    @Binding var selection: TranscriptNote?
    @EnvironmentObject private var statsObserver: StatsObserver

    @State private var searchText: String = ""
    @State private var searchResults: [TranscriptNote] = []

    private var sections: [ScratchpadSection] {
        let notes = searchText.isEmpty ? statsObserver.notes : searchResults
        return ScratchpadSection.group(notes)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScratchpadSearchField(text: $searchText, onChange: { query in
                Task { await runSearch(query) }
            })
            Divider()
            list
        }
        .background(HDColor.canvas)
        .onReceive(NotificationCenter.default.publisher(for: .mywhiNavigateToScratchpad)) { note in
            if let query = note.userInfo?["query"] as? String, !query.isEmpty {
                searchText = query
                Task { await runSearch(query) }
            }
        }
    }

    private var list: some View {
        Group {
            if statsObserver.notes.isEmpty {
                emptyState
            } else {
                List(selection: $selection) {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.notes, id: \.id) { note in
                                ScratchpadRow(note: note, isSelected: selection?.id == note.id)
                                    .tag(note)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                            }
                        } header: {
                            Text(section.title.uppercased())
                                .font(HDFont.monoLabel(size: 10))
                                .hdTracking(0.5)
                                .foregroundStyle(HDColor.muted)
                                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 4, trailing: 0))
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: HDSpacing.md.rawValue) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(HDColor.muted)
            Text("Скажи что-нибудь — начнём")
                .font(HDFont.featureHeading)
                .foregroundStyle(HDColor.coral)
                .multilineTextAlignment(.center)
            Text("Запиши первую фразу на вкладке «Запись».")
                .font(HDFont.caption)
                .foregroundStyle(HDColor.muted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(HDSpacing.xl.rawValue)
    }

    private func runSearch(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            searchResults = []
            return
        }
        searchResults = await statsObserver.search(trimmed)
    }
}

// MARK: - Row

private struct ScratchpadRow: View {
    let note: TranscriptNote
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(HDColor.ink)
                .lineLimit(2)
            HStack(spacing: HDSpacing.xs.rawValue) {
                Text(timeAgoString(from: note.frontmatter.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(HDColor.muted)
                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(HDColor.muted)
                Text("\(note.frontmatter.words) слов")
                    .font(.system(size: 11))
                    .foregroundStyle(HDColor.muted)
                Spacer()
                if note.frontmatter.engine == "faster-whisper" {
                    Text("py")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(HDColor.paleBlue))
                        .foregroundStyle(HDColor.actionBlue)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func timeAgoString(from date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .short
        fmt.locale = Locale(identifier: "ru_RU")
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Date grouping

struct ScratchpadSection: Identifiable {
    let id: String
    let title: String
    let notes: [TranscriptNote]

    static func group(_ notes: [TranscriptNote], now: Date = Date(), calendar: Calendar = .current) -> [ScratchpadSection] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today)!

        var todayN: [TranscriptNote] = []
        var yesterdayN: [TranscriptNote] = []
        var weekN: [TranscriptNote] = []
        var olderByMonth: [String: [TranscriptNote]] = [:]
        var olderOrder: [String] = []

        let monthFmt = DateFormatter()
        monthFmt.locale = Locale(identifier: "ru_RU")
        monthFmt.dateFormat = "LLLL yyyy"

        for note in notes {
            let day = calendar.startOfDay(for: note.frontmatter.createdAt)
            if day == today {
                todayN.append(note)
            } else if day == yesterday {
                yesterdayN.append(note)
            } else if day >= weekStart {
                weekN.append(note)
            } else {
                let key = monthFmt.string(from: note.frontmatter.createdAt)
                if olderByMonth[key] == nil {
                    olderByMonth[key] = []
                    olderOrder.append(key)
                }
                olderByMonth[key]?.append(note)
            }
        }

        var sections: [ScratchpadSection] = []
        if !todayN.isEmpty    { sections.append(.init(id: "today",     title: "Сегодня",          notes: todayN)) }
        if !yesterdayN.isEmpty { sections.append(.init(id: "yesterday", title: "Вчера",            notes: yesterdayN)) }
        if !weekN.isEmpty     { sections.append(.init(id: "week",      title: "На этой неделе",   notes: weekN)) }
        for key in olderOrder {
            if let notes = olderByMonth[key] {
                sections.append(.init(id: "older-\(key)", title: key.capitalized, notes: notes))
            }
        }
        return sections
    }
}