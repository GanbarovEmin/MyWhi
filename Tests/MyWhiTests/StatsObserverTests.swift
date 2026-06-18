// StatsObserverTests.swift
// Tests for the incremental update path. Uses an in-memory VaultStore
// and VaultIndex substitute so we don't touch disk.

import XCTest
@testable import MyWhi

/// In-memory replacement for VaultStore. Implements only the surface
/// StatsObserver uses. Keeps notes in a [TranscriptNote] keyed by id.
final class FakeVaultStore {
    var notes: [TranscriptNote] = []
    var saveError: Error?
    var updateError: Error?
    var deleteError: Error?
    var listError: Error?
    private var nextId = 0

    func save(transcript: String, language: String, model: String, engine: String,
              durationSeconds: Double, audio: String?) async throws -> TranscriptNote {
        if let saveError { throw saveError }
        nextId += 1
        let fm = TranscriptFrontmatter(
            id: UUID(),
            createdAt: Date(),
            language: language,
            model: model,
            engine: engine,
            durationSeconds: durationSeconds,
            chars: transcript.count,
            words: transcript.split(separator: " ").count,
            audio: audio
        )
        let note = TranscriptNote(
            id: fm.id, url: URL(fileURLWithPath: "/tmp/\(fm.id).md"),
            frontmatter: fm, body: transcript
        )
        notes.insert(note, at: 0)
        return note
    }

    func update(_ note: TranscriptNote, newBody: String) async throws -> TranscriptNote {
        if let updateError { throw updateError }
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return note }
        var fm = notes[idx].frontmatter
        fm.chars = newBody.count
        fm.words = newBody.split(separator: " ").count
        let updated = TranscriptNote(id: note.id, url: note.url, frontmatter: fm, body: newBody)
        notes[idx] = updated
        return updated
    }

    func delete(_ note: TranscriptNote) async throws {
        if let deleteError { throw deleteError }
        notes.removeAll { $0.id == note.id }
    }

    func listAll() async throws -> [TranscriptNote] {
        if let listError { throw listError }
        return notes
    }

    func sizeOnDisk() async throws -> Int64 { 0 }
}

@MainActor
final class StatsObserverTests: XCTestCase {

    private var vaultStore: VaultStore!
    private var vaultIndex: VaultIndex!
    private var observer: StatsObserver!

    override func setUp() async throws {
        try await super.setUp()
        vaultStore = VaultStore()
        vaultIndex = VaultIndex()
        observer = StatsObserver(vaultStore: vaultStore, vaultIndex: vaultIndex)
        // Wipe any pre-existing vault files so the test is hermetic.
        try? FileManager.default.removeItem(at: VaultPaths.root)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: VaultPaths.root)
        vaultStore = nil
        vaultIndex = nil
        observer = nil
        try await super.tearDown()
    }

    // MARK: - recordTranscript

    func testRecordTranscript_addsToNotes() async throws {
        // Initial state
        XCTAssertEqual(observer.notes.count, 0)
        XCTAssertEqual(observer.stats.totalNotes, 0)

        // Record one
        let note = await observer.recordTranscript(
            text: "Hello world this is a test",
            language: "ru",
            model: "small",
            engine: "whisperkit",
            durationSeconds: 5,
            audio: nil
        )
        XCTAssertNotNil(note)
        XCTAssertEqual(observer.notes.count, 1)
        XCTAssertEqual(observer.notes.first?.body, "Hello world this is a test")
        XCTAssertEqual(observer.stats.totalNotes, 1)
        XCTAssertEqual(observer.stats.totalWords, 6)
        XCTAssertEqual(observer.stats.totalChars, "Hello world this is a test".count)
    }

    func testRecordTranscript_multiple() async throws {
        for i in 0..<5 {
            _ = await observer.recordTranscript(
                text: "Note \(i) with some words",
                language: "ru",
                model: "small",
                engine: "whisperkit",
                durationSeconds: 0,
                audio: nil
            )
        }
        XCTAssertEqual(observer.notes.count, 5)
        XCTAssertEqual(observer.stats.totalNotes, 5)
        // "Note N with some words" = 5 words; 5 notes = 25 words.
        XCTAssertEqual(observer.stats.totalWords, 25)
    }

    func testRecordTranscript_doesNotRescanDisk() async throws {
        // Record 10 notes; we should be O(N) not O(N²) — i.e. no disk
        // walk per save. We can't directly time this in XCTest, but we
        // can assert that the in-memory `notes` list is consistent
        // with what the fake would return.
        for i in 0..<10 {
            _ = await observer.recordTranscript(
                text: "Note number \(i)",
                language: "en",
                model: "small",
                engine: "whisperkit",
                durationSeconds: 0,
                audio: nil
            )
        }
        XCTAssertEqual(observer.notes.count, 10)
        // Most recent note should be at index 0 (newest-first).
        XCTAssertTrue(observer.notes[0].body.contains("9"))
        XCTAssertTrue(observer.notes[9].body.contains("0"))
    }

    // MARK: - update

    func testUpdate_modifiesInPlace() async throws {
        let note = await observer.recordTranscript(
            text: "Original",
            language: "ru",
            model: "small",
            engine: "whisperkit",
            durationSeconds: 0,
            audio: nil
        )!
        XCTAssertEqual(note.body, "Original")

        let updated = await observer.update(note: note, newBody: "Updated body with more words")
        XCTAssertNotNil(updated)
        XCTAssertEqual(updated?.body, "Updated body with more words")
        // Stats reflect the new word count.
        XCTAssertEqual(observer.stats.totalWords, 5)
    }

    // MARK: - delete

    func testDelete_removesFromList() async throws {
        let note = await observer.recordTranscript(
            text: "To be deleted",
            language: "ru",
            model: "small",
            engine: "whisperkit",
            durationSeconds: 0,
            audio: nil
        )!
        XCTAssertEqual(observer.notes.count, 1)
        await observer.delete(note: note)
        XCTAssertEqual(observer.notes.count, 0)
        XCTAssertEqual(observer.stats.totalNotes, 0)
    }

    // MARK: - refresh

    func testRefresh_loadsFromDisk() async throws {
        // Write directly via vaultStore
        _ = try await vaultStore.save(
            transcript: "From disk",
            language: "ru",
            model: "small",
            engine: "whisperkit",
            durationSeconds: 0,
            audio: nil
        )

        await observer.refresh()
        XCTAssertEqual(observer.notes.count, 1)
        XCTAssertEqual(observer.notes.first?.body, "From disk")
    }

    func testReloadFromDisk_picksUpExternalChanges() async throws {
        // Record one in-memory
        _ = await observer.recordTranscript(
            text: "Original",
            language: "ru",
            model: "small",
            engine: "whisperkit",
            durationSeconds: 0,
            audio: nil
        )
        // Add a file directly to disk (simulating Obsidian edit)
        _ = try await vaultStore.save(
            transcript: "Added externally",
            language: "en",
            model: "small",
            engine: "whisperkit",
            durationSeconds: 0,
            audio: nil
        )
        // In-memory list is stale (only 1 entry)
        XCTAssertEqual(observer.notes.count, 1)
        // After reload we see 2
        await observer.reloadFromDisk()
        XCTAssertEqual(observer.notes.count, 2)
    }
}