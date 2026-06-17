// VaultIndex.swift
// In-memory index over the vault. Built from a list of notes; supports
// fast search (case-insensitive substring across title + body) and
// aggregate stats (totals, streaks, language breakdown).
//
// Why not SQLite FTS5 right now? Vaults typically hold dozens to a few
// hundred notes — well within Swift's string-search performance budget.
// When a real user hits >1000 notes, we'll swap the backend for SQLite
// FTS5 without changing this class's public API.
//
// Thread-safety: actor-isolated; all methods are async.

import Foundation

actor VaultIndex {

    /// All notes currently indexed. Body is included for search.
    private var notes: [TranscriptNote] = []

    /// Whether the cache is fresh. Set to false when the underlying
    /// vault changes; callers call `rebuild(from:)` to refresh.
    private(set) var isDirty: Bool = true

    // MARK: - Build / refresh

    /// Replace the index with a snapshot from the vault.
    func setNotes(_ notes: [TranscriptNote]) {
        self.notes = notes
        self.isDirty = false
    }

    /// Mark the index as stale (e.g. after a save/update/delete).
    func invalidate() {
        isDirty = true
    }

    var allNotes: [TranscriptNote] {
        notes.sorted { $0.frontmatter.createdAt > $1.frontmatter.createdAt }
    }

    // MARK: - Search

    /// Case-insensitive substring search over title + body. Empty
    /// `query` returns all notes.
    func search(_ query: String) -> [TranscriptNote] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return allNotes }
        let needle = trimmed.lowercased()
        return notes.filter { note in
            note.title.lowercased().contains(needle)
                || note.body.lowercased().contains(needle)
        }
        .sorted { $0.frontmatter.createdAt > $1.frontmatter.createdAt }
    }

    // MARK: - Aggregate

    /// Compute aggregate stats over the current index.
    func aggregate(calendar: Calendar = .current, today: Date = Date()) -> AggregateStats {
        guard !notes.isEmpty else { return .empty }

        let activeDays = Set(notes.map { calendar.startOfDay(for: $0.frontmatter.createdAt) })

        let totalChars = notes.reduce(0) { $0 + $1.frontmatter.chars }
        let totalWords = notes.reduce(0) { $0 + $1.frontmatter.words }
        let byLang = notes.reduce(into: [String: Int]()) { acc, note in
            acc[note.frontmatter.language, default: 0] += note.frontmatter.words
        }

        return AggregateStats(
            totalNotes: notes.count,
            totalChars: totalChars,
            totalWords: totalWords,
            currentStreak: StreakCalculator.currentStreak(
                activeDays: activeDays, today: today, calendar: calendar
            ),
            longestStreak: StreakCalculator.longestStreak(
                activeDays: activeDays, calendar: calendar
            ),
            byLanguage: byLang,
            last30Days: StreakCalculator.lastNDaysCounts(
                activeDays: activeDays, n: 30, today: today, calendar: calendar
            )
        )
    }
}