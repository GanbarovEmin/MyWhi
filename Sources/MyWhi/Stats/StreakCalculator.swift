// StreakCalculator.swift
// Pure functions for day-streak math. Extracted from IndexStore for
// testability — no I/O, no Foundation dependencies beyond Calendar.
//
// A "streak" is N consecutive days ending today (or yesterday) that each
// have at least one transcript. Two edge cases:
//   - If today has no entry but yesterday does, the streak is still
//     "alive" (counts up to yesterday). Today not yet started.
//   - If neither today nor yesterday has an entry, streak = 0.

import Foundation

enum StreakCalculator {

    /// Compute the current streak length given a set of distinct days
    /// (each day represented by `Calendar.current.startOfDay(for: ...)`)
    /// on which at least one transcript was created.
    ///
    /// - Parameter activeDays: Set of normalized day-starts (Date values
    ///   that fall at midnight in the current timezone).
    /// - Parameter today: Override for the reference "today" date.
    ///   Defaults to `Date()`. Pass a fixed date in tests.
    /// - Returns: Length of the current streak (>= 0).
    static func currentStreak(
        activeDays: Set<Date>,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        guard !activeDays.isEmpty else { return 0 }

        let todayStart = calendar.startOfDay(for: today)

        // Anchor: the most recent active day that is <= today.
        // If today is active, streak runs from today backward.
        // Else if yesterday is active, streak runs from yesterday backward.
        // Else streak is 0.
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!

        let anchor: Date
        if activeDays.contains(todayStart) {
            anchor = todayStart
        } else if activeDays.contains(yesterdayStart) {
            anchor = yesterdayStart
        } else {
            return 0
        }

        var streak = 0
        var cursor = anchor
        while activeDays.contains(cursor) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = prev
        }
        return streak
    }

    /// Compute the longest streak ever recorded.
    static func longestStreak(
        activeDays: Set<Date>,
        calendar: Calendar = .current
    ) -> Int {
        guard !activeDays.isEmpty else { return 0 }

        let sorted = activeDays.sorted()
        var longest = 1
        var current = 1
        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let curr = sorted[i]
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: prev),
               calendar.isDate(nextDay, inSameDayAs: curr) {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }

    /// Bucket active days into the last `n` days (most recent last).
    /// Returns array of length `n` with count of entries on each day.
    static func lastNDaysCounts(
        activeDays: Set<Date>,
        n: Int,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> [Int] {
        let todayStart = calendar.startOfDay(for: today)
        var result: [Int] = Array(repeating: 0, count: n)
        for i in 0..<n {
            guard let day = calendar.date(byAdding: .day, value: -(n - 1 - i), to: todayStart) else {
                continue
            }
            result[i] = activeDays.contains(day) ? 1 : 0
        }
        return result
    }
}