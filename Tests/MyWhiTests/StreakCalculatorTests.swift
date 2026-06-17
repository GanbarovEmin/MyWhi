// StreakCalculatorTests.swift
// Pure-function tests for the streak math. No I/O, no async.
//
// Timezone strategy: we use `Calendar.current` (the system timezone)
// everywhere — both in the test helpers and as the explicit argument
// to StreakCalculator — to avoid TZ drift between caller and callee.

import XCTest
@testable import MyWhi

final class StreakCalculatorTests: XCTestCase {

    // Use a fixed reference date at noon in the system timezone so the
    // startOfDay computation is unambiguous regardless of TZ offset.
    private let referenceToday: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 17
        c.hour = 12; c.minute = 0; c.second = 0
        return Calendar.current.date(from: c)!
    }()

    private let cal = Calendar.current

    private func day(_ offset: Int, from base: Date) -> Date {
        cal.date(byAdding: .day, value: offset, to: base)!
    }

    private func startOfDay(_ date: Date) -> Date {
        cal.startOfDay(for: date)
    }

    // MARK: - currentStreak

    func testCurrentStreak_emptySet_returnsZero() {
        XCTAssertEqual(
            StreakCalculator.currentStreak(activeDays: [], today: referenceToday, calendar: cal),
            0
        )
    }

    func testCurrentStreak_singleDayToday_returnsOne() {
        let today = startOfDay(referenceToday)
        XCTAssertEqual(
            StreakCalculator.currentStreak(activeDays: [today], today: referenceToday, calendar: cal),
            1
        )
    }

    func testCurrentStreak_singleDayYesterday_returnsOne() {
        let yesterday = startOfDay(day(-1, from: referenceToday))
        XCTAssertEqual(
            StreakCalculator.currentStreak(activeDays: [yesterday], today: referenceToday, calendar: cal),
            1
        )
    }

    func testCurrentStreak_onlyOldDay_returnsZero() {
        let tenDaysAgo = startOfDay(day(-10, from: referenceToday))
        XCTAssertEqual(
            StreakCalculator.currentStreak(activeDays: [tenDaysAgo], today: referenceToday, calendar: cal),
            0
        )
    }

    func testCurrentStreak_sevenConsecutiveDaysIncludingToday_returnsSeven() {
        var days: Set<Date> = []
        for offset in 0...6 {
            days.insert(startOfDay(day(-offset, from: referenceToday)))
        }
        XCTAssertEqual(
            StreakCalculator.currentStreak(activeDays: days, today: referenceToday, calendar: cal),
            7
        )
    }

    func testCurrentStreak_sevenConsecutiveDaysEndingYesterday_returnsSeven() {
        var days: Set<Date> = []
        for offset in (1...7) {
            days.insert(startOfDay(day(-offset, from: referenceToday)))
        }
        XCTAssertEqual(
            StreakCalculator.currentStreak(activeDays: days, today: referenceToday, calendar: cal),
            7
        )
    }

    func testCurrentStreak_brokenStreak_returnsUpToAnchor() {
        var days: Set<Date> = []
        // Today + yesterday + day-before-yesterday = 3
        for offset in 0...2 {
            days.insert(startOfDay(day(-offset, from: referenceToday)))
        }
        // Gap on day -3
        // -4 and -5 again
        for offset in 4...5 {
            days.insert(startOfDay(day(-offset, from: referenceToday)))
        }
        XCTAssertEqual(
            StreakCalculator.currentStreak(activeDays: days, today: referenceToday, calendar: cal),
            3
        )
    }

    func testCurrentStreak_multipleEntriesOnSameDay_countsOnce() {
        let today = startOfDay(referenceToday)
        let sameDay = today.addingTimeInterval(3600)  // 1 hour later, same day
        let sameDay2 = today.addingTimeInterval(7200) // 2 hours later
        XCTAssertEqual(
            StreakCalculator.currentStreak(
                activeDays: [today, sameDay, sameDay2],
                today: referenceToday,
                calendar: cal
            ),
            1
        )
    }

    // MARK: - longestStreak

    func testLongestStreak_empty_returnsZero() {
        XCTAssertEqual(StreakCalculator.longestStreak(activeDays: [], calendar: cal), 0)
    }

    func testLongestStreak_singleDay_returnsOne() {
        let today = startOfDay(referenceToday)
        XCTAssertEqual(StreakCalculator.longestStreak(activeDays: [today], calendar: cal), 1)
    }

    func testLongestStreak_consecutiveFiveLongest() {
        var days: Set<Date> = []
        for offset in 0...4 {
            days.insert(startOfDay(day(-offset, from: referenceToday)))
        }
        days.insert(startOfDay(day(-10, from: referenceToday)))
        days.insert(startOfDay(day(-20, from: referenceToday)))
        XCTAssertEqual(StreakCalculator.longestStreak(activeDays: days, calendar: cal), 5)
    }

    // MARK: - lastNDaysCounts

    func testLastNDaysCounts_zeroOnAllDaysExceptOne() {
        let threeDaysAgo = startOfDay(day(-3, from: referenceToday))
        let counts = StreakCalculator.lastNDaysCounts(
            activeDays: [threeDaysAgo],
            n: 7,
            today: referenceToday,
            calendar: cal
        )
        XCTAssertEqual(counts.count, 7)
        let sum = counts.reduce(0, +)
        XCTAssertEqual(sum, 1)
        XCTAssertEqual(counts[3], 1)  // index 3 in 7-day window = 3 days before today
    }
}