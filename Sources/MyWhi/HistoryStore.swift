// HistoryStore.swift
// Persistent ring buffer of the last N transcripts.

import Foundation

struct HistoryEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var text: String
    var timestamp: Date
    var audioFilename: String?

    /// Short, human-readable timestamp for display in the popover.
    var displayTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.locale = Locale(identifier: "ru_RU")
        return f.string(from: timestamp)
    }
}

final class HistoryStore {

    private let url: URL
    private let limit: Int

    init(limit: Int = 10) {
        self.limit = limit
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("MyWhi", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("history.json")
    }

    func load() -> [HistoryEntry] {
        guard
            let data = try? Data(contentsOf: url),
            let entries = try? JSONDecoder().decode([HistoryEntry].self, from: data)
        else {
            return []
        }
        return entries
    }

    func add(_ entry: HistoryEntry, limit: Int? = nil) {
        let cap = limit ?? self.limit
        var current = load()
        // Newest first.
        current.insert(entry, at: 0)
        if current.count > cap {
            current = Array(current.prefix(cap))
        }
        save(current)
    }

    func clear() {
        save([])
    }

    private func save(_ entries: [HistoryEntry]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(entries)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("MyWhi: failed to save history: \(error)")
        }
    }
}
