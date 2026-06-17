// AggregateStats.swift
// Computed aggregates over the vault. Used by the Insights view to
// render hero stats, the streak heatmap, and trend lines.

import Foundation

struct AggregateStats: Codable, Equatable {

    /// Total number of notes in the vault.
    var totalNotes: Int

    /// Sum of all chars across notes.
    var totalChars: Int

    /// Sum of all words across notes.
    var totalWords: Int

    /// Length of the current day-streak (consecutive days ending today/yesterday).
    var currentStreak: Int

    /// Longest day-streak ever recorded.
    var longestStreak: Int

    /// Per-language breakdown: language code → total words.
    var byLanguage: [String: Int]

    /// Per-day counts for the last 30 days (oldest first, length = 30).
    var last30Days: [Int]

    static let empty = AggregateStats(
        totalNotes: 0,
        totalChars: 0,
        totalWords: 0,
        currentStreak: 0,
        longestStreak: 0,
        byLanguage: [:],
        last30Days: Array(repeating: 0, count: 30)
    )
}