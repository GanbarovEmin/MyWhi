// VaultIndexTests.swift
// Tests for the in-memory index over notes.

import XCTest
@testable import MyWhi

final class VaultIndexTests: XCTestCase {

    private func makeNote(
        daysAgo: Int,
        words: Int,
        language: String = "ru",
        bodyText: String = "Some transcript body text"
    ) -> TranscriptNote {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let fm = TranscriptFrontmatter(
            id: UUID(),
            createdAt: date,
            language: language,
            model: "small",
            engine: "whisperkit",
            durationSeconds: 5.0,
            chars: bodyText.count,
            words: words,
            audio: nil
        )
        return TranscriptNote(
            id: fm.id,
            url: URL(fileURLWithPath: "/tmp/\(fm.id).md"),
            frontmatter: fm,
            body: bodyText
        )
    }

    func testSearch_emptyQuery_returnsAllNotes() async {
        let idx = VaultIndex()
        let notes = (0..<5).map { makeNote(daysAgo: $0, words: 10) }
        await idx.setNotes(notes)
        let result = await idx.search("")
        XCTAssertEqual(result.count, 5)
    }

    func testSearch_caseInsensitive() async {
        let idx = VaultIndex()
        let notes = [
            makeNote(daysAgo: 0, words: 5, bodyText: "Привет МИР как дела"),
            makeNote(daysAgo: 1, words: 3, bodyText: "Hello World"),
        ]
        await idx.setNotes(notes)

        let r1 = await idx.search("мир")
        XCTAssertEqual(r1.count, 1)

        let r2 = await idx.search("HELLO")
        XCTAssertEqual(r2.count, 1)
    }

    func testSearch_matchesAcrossTitleAndBody() async {
        let idx = VaultIndex()
        let notes = [
            makeNote(daysAgo: 0, words: 5, bodyText: "Some unrelated content here"),
        ]
        await idx.setNotes(notes)
        // First line of body is the title.
        let result = await idx.search("Some")
        XCTAssertEqual(result.count, 1)
    }

    func testAggregate_emptyNotes_returnsZero() async {
        let idx = VaultIndex()
        await idx.setNotes([])
        let stats = await idx.aggregate()
        XCTAssertEqual(stats.totalNotes, 0)
        XCTAssertEqual(stats.totalWords, 0)
        XCTAssertEqual(stats.currentStreak, 0)
    }

    func testAggregate_sumsWordsAndChars() async {
        let idx = VaultIndex()
        let notes = [
            makeNote(daysAgo: 0, words: 100),
            makeNote(daysAgo: 1, words: 200),
            makeNote(daysAgo: 2, words: 300),
        ]
        await idx.setNotes(notes)
        let stats = await idx.aggregate()
        XCTAssertEqual(stats.totalNotes, 3)
        XCTAssertEqual(stats.totalWords, 600)
    }

    func testAggregate_byLanguage_breakdown() async {
        let idx = VaultIndex()
        let notes = [
            makeNote(daysAgo: 0, words: 100, language: "ru"),
            makeNote(daysAgo: 1, words: 50, language: "en"),
            makeNote(daysAgo: 2, words: 30, language: "ru"),
        ]
        await idx.setNotes(notes)
        let stats = await idx.aggregate()
        XCTAssertEqual(stats.byLanguage["ru"], 130)
        XCTAssertEqual(stats.byLanguage["en"], 50)
    }

    func testAggregate_currentStreak_threeDaysBack() async {
        let idx = VaultIndex()
        let notes = [
            makeNote(daysAgo: 0, words: 10),
            makeNote(daysAgo: 1, words: 10),
            makeNote(daysAgo: 2, words: 10),
        ]
        await idx.setNotes(notes)
        let stats = await idx.aggregate()
        XCTAssertEqual(stats.currentStreak, 3)
    }

    func testAggregate_last30Days_lengthIs30() async {
        let idx = VaultIndex()
        await idx.setNotes([])
        let stats = await idx.aggregate()
        XCTAssertEqual(stats.last30Days.count, 30)
    }
}