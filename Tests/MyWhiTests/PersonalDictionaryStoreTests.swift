// PersonalDictionaryStoreTests.swift
// Phase 19 — round-trip tests for the personal dictionary save/load
// pair. We point the store at a temp file so we don't touch the
// user's real ~/Library/Application Support/MyWhi/dictionary.json.

import XCTest
@testable import MyWhi

final class PersonalDictionaryStoreTests: XCTestCase {

    /// Phase 19: round-trip — save entries, reload, must come back
    /// identical (DictionaryReplacement is Codable + Hashable, so
    /// equality is straightforward).
    func testSaveAndLoadRoundTrip() async throws {
        let tmp = try makeTempDictionaryURL()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = PersonalDictionaryStore(url: tmp)
        let original = [
            DictionaryReplacement(from: "ашбис", to: "ASBIS"),
            DictionaryReplacement(from: "айспейс", to: "iSpace"),
            DictionaryReplacement(from: "мхп", to: "MHP")
        ]
        await store.save(original)

        // Load via a fresh store instance — exercises the on-disk
        // format, not just the in-memory dict.
        let store2 = PersonalDictionaryStore(url: tmp)
        let loaded = await store2.load()

        XCTAssertEqual(loaded.count, original.count)
        XCTAssertEqual(Set(loaded.map { "\($0.from)|\($0.to)" }),
                       Set(original.map { "\($0.from)|\($0.to)" }),
                       "Loaded entries must match what was saved")
    }

    /// Phase 19: load() on a non-existent file returns empty.
    func testLoadOnMissingFileReturnsEmpty() async throws {
        let tmp = URL(fileURLWithPath: "/tmp/mywhi-test-missing-\(UUID()).json")
        // Don't create the file.
        let store = PersonalDictionaryStore(url: tmp)
        let loaded = await store.load()
        XCTAssertTrue(loaded.isEmpty)
    }

    /// Phase 19: load() accepts the legacy `{ "from": "to" }` shape
    /// so users who hand-edited their dictionary file before Phase 19
    /// don't lose their entries.
    func testLoadAcceptsLegacyMapShape() async throws {
        let tmp = try makeTempDictionaryURL()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Write the legacy map shape.
        let legacy: [String: String] = [
            "ашбис": "ASBIS",
            "айспейс": "iSpace"
        ]
        let data = try JSONEncoder().encode(legacy)
        try data.write(to: tmp)

        let store = PersonalDictionaryStore(url: tmp)
        let loaded = await store.load()

        XCTAssertEqual(loaded.count, 2)
        XCTAssertTrue(loaded.contains { $0.from == "ашбис" && $0.to == "ASBIS" })
        XCTAssertTrue(loaded.contains { $0.from == "айспейс" && $0.to == "iSpace" })
    }

    /// Phase 19: load() on a corrupt file returns empty (no crash).
    func testLoadOnCorruptFileReturnsEmpty() async throws {
        let tmp = try makeTempDictionaryURL()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try "not valid json".data(using: .utf8)!.write(to: tmp)

        let store = PersonalDictionaryStore(url: tmp)
        let loaded = await store.load()
        XCTAssertTrue(loaded.isEmpty, "Corrupt file must not crash; should return empty.")
    }

    /// Phase 19: save() with an empty list writes a valid empty JSON
    /// array. This means deleting all entries produces an empty file,
    /// not a missing one — consistent regardless of how many entries
    /// the user has.
    func testSaveEmptyListProducesEmptyArray() async throws {
        let tmp = try makeTempDictionaryURL()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = PersonalDictionaryStore(url: tmp)
        await store.save([])

        let raw = try Data(contentsOf: tmp)
        let json = try JSONSerialization.jsonObject(with: raw)
        XCTAssertTrue(json is NSArray, "Empty save should produce []")
        if let arr = json as? NSArray {
            XCTAssertEqual(arr.count, 0)
        }
    }

    // MARK: - Helpers

    private func makeTempDictionaryURL() throws -> URL {
        let dir = URL(fileURLWithPath: "/tmp/mywhi-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dictionary.json")
    }
}