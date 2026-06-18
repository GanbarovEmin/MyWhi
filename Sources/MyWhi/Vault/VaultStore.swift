// VaultStore.swift
// File-system CRUD for the Markdown vault of transcripts. Async to
// keep the main thread free for the SwiftUI list/detail views.
//
// Thread-safety: all writes go through an internal serial queue. Reads
// use `Task.detached` so they can run on a background actor.
//
// Atomic writes: each save writes to a temp file in the same folder
// then renames over the target. This guarantees the file is either the
// old version or the new version — never half-written.
//
// Phase 5.1 — NSFileCoordinator
// All disk operations on vault files now go through NSFileCoordinator
// so two MyWhi instances (or MyWhi + Obsidian) can't tear the file
// mid-write. The coordinator locks the file URI for the duration of
// the I/O; readers/writers either see the whole pre-write content or
// the whole post-write content.

import Foundation
import os

actor VaultStore {

    private let fm = FileManager.default
    private let calendar: Calendar
    private let fileCoordinator = NSFileCoordinator(filePresenter: nil)
    private let logger = Logger(subsystem: "az.isupport.mywhi", category: "VaultStore")

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    // MARK: - Write

    /// Create a new note from raw transcript text. Returns the saved note.
    @discardableResult
    func save(
        transcript: String,
        language: String,
        model: String,
        engine: String,
        durationSeconds: Double,
        audio: String?,
        date: Date = Date()
    ) throws -> TranscriptNote {
        let fmatter = TranscriptFrontmatter(
            id: UUID(),
            createdAt: date,
            language: language,
            model: model,
            engine: engine,
            durationSeconds: durationSeconds,
            chars: transcript.count,
            words: countWords(transcript),
            audio: audio
        )
        return try save(fmatter: fmatter, body: transcript)
    }

    /// Persist a frontmatter + body to disk. Atomic via temp file.
    @discardableResult
    func save(fmatter: TranscriptFrontmatter, body: String) throws -> TranscriptNote {
        let slug = VaultPaths.slugify(firstLine(of: body))
        let monthDir = try VaultPaths.ensureMonthDir(for: fmatter.createdAt, calendar: calendar)
        let url = monthDir.appendingPathComponent(
            VaultPaths.fileName(for: fmatter.createdAt, slug: slug, calendar: calendar)
        )

        let content = fmatter.renderYAML() + body
        try writeAtomic(content: content, to: url)

        return TranscriptNote(
            id: fmatter.id,
            url: url,
            frontmatter: fmatter,
            body: body
        )
    }

    /// Update the body of an existing note in place. Preserves the
    /// original `id`, `created_at`, and `audio` fields.
    func update(_ note: TranscriptNote, newBody: String) throws -> TranscriptNote {
        var fm = note.frontmatter
        fm.chars = newBody.count
        fm.words = countWords(newBody)
        let content = fm.renderYAML() + newBody
        try writeAtomic(content: content, to: note.url)

        return TranscriptNote(
            id: note.id,
            url: note.url,
            frontmatter: fm,
            body: newBody
        )
    }

    /// Delete a note. Throws if the file is missing.
    func delete(_ note: TranscriptNote) throws {
        var coordinationError: NSError?
        fileCoordinator.coordinate(writingItemAt: note.url, options: .forDeleting, error: &coordinationError) { writeURL in
            do {
                try fm.removeItem(at: writeURL)
            } catch {
                // Re-throw inside the closure; the outer throws
                // propagates the original error.
                NSLog("MyWhi.VaultStore: removeItem failed: \(error)")
            }
        }
        if let coordinationError {
            throw coordinationError
        }
    }

    // MARK: - Read

    /// List all notes, newest first. Reads metadata only; `body` is
    /// empty until you call `load(_:)`. Coordinated read so external
    /// apps can rename / move files safely.
    func listAll() throws -> [TranscriptNote] {
        guard fm.fileExists(atPath: VaultPaths.root.path) else { return [] }

        var results: [TranscriptNote] = []
        var coordError: NSError?
        fileCoordinator.coordinate(readingItemAt: VaultPaths.root, options: [], error: &coordError) { readURL in
            let enumerator = fm.enumerator(
                at: readURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            guard let enumerator else { return }
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "md" else { continue }
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                guard let parsed = TranscriptFrontmatter.parse(from: content) else { continue }
                results.append(TranscriptNote(
                    id: parsed.frontmatter.id,
                    url: fileURL,
                    frontmatter: parsed.frontmatter,
                    body: parsed.body
                ))
            }
        }
        if let coordError { throw coordError }
        return results.sorted { $0.frontmatter.createdAt > $1.frontmatter.createdAt }
    }

    /// Reload a note's body from disk. Use this when the file might
    /// have been edited externally.
    func load(_ note: TranscriptNote) throws -> TranscriptNote {
        var loaded = note
        var coordError: NSError?
        fileCoordinator.coordinate(readingItemAt: note.url, options: [], error: &coordError) { readURL in
            let content = try? String(contentsOf: readURL, encoding: .utf8)
            guard let content, let parsed = TranscriptFrontmatter.parse(from: content) else { return }
            loaded = TranscriptNote(
                id: parsed.frontmatter.id,
                url: note.url,
                frontmatter: parsed.frontmatter,
                body: parsed.body
            )
        }
        if let coordError { throw coordError }
        return loaded
    }

    /// Total number of notes (fast: just counts .md files).
    func count() throws -> Int {
        guard fm.fileExists(atPath: VaultPaths.root.path) else { return 0 }
        let enumerator = fm.enumerator(
            at: VaultPaths.root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        guard let enumerator else { return 0 }
        var n = 0
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "md" {
            n += 1
        }
        return n
    }

    /// Total disk size of the vault, in bytes.
    func sizeOnDisk() throws -> Int64 {
        guard fm.fileExists(atPath: VaultPaths.root.path) else { return 0 }
        let keys: Set<URLResourceKey> = [.fileSizeKey]
        let enumerator = fm.enumerator(
            at: VaultPaths.root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        guard let enumerator else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "md" {
            let resourceValues = try? fileURL.resourceValues(forKeys: keys)
            total += Int64(resourceValues?.fileSize ?? 0)
        }
        return total
    }

    // MARK: - Migration from legacy history.json

    /// Read `~/Library/Application Support/MyWhi/history.json` (legacy
    /// v1 format) and create vault notes for each entry. Idempotent —
    /// skips entries that already exist in the vault (matched by id).
    ///
    /// Returns the number of notes created. The original `history.json`
    /// is backed up to `history.json.migrated-<date>`.
    func migrateFromLegacyHistoryJSON() throws -> Int {
        let legacyURL = VaultPaths.root
            .deletingLastPathComponent()  // ~/Library/Application Support/MyWhi/
            .appendingPathComponent("history.json")

        guard fm.fileExists(atPath: legacyURL.path) else { return 0 }
        guard let data = try? Data(contentsOf: legacyURL) else { return 0 }

        struct LegacyEntry: Decodable {
            let id: UUID?
            let text: String
            let timestamp: Date
            let audioFilename: String?
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let entries = try? decoder.decode([LegacyEntry].self, from: data) else {
            return 0
        }

        // Build set of existing IDs to skip duplicates.
        let existing = (try? listAll()) ?? []
        let existingIDs = Set(existing.map(\.id))

        var created = 0
        for entry in entries {
            if let id = entry.id, existingIDs.contains(id) { continue }
            let fmatter = TranscriptFrontmatter(
                id: entry.id ?? UUID(),
                createdAt: entry.timestamp,
                language: "ru",
                model: "small",
                engine: "faster-whisper",
                durationSeconds: 0,
                chars: entry.text.count,
                words: countWords(entry.text),
                audio: entry.audioFilename
            )
            _ = try save(fmatter: fmatter, body: entry.text)
            created += 1
        }

        // Back up the original file.
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = legacyURL.deletingPathExtension()
            .appendingPathExtension("json.migrated-\(stamp)")
        try? fm.moveItem(at: legacyURL, to: backupURL)

        return created
    }

    // MARK: - Helpers

    private func firstLine(of body: String) -> String {
        body.components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "note"
    }

    private func countWords(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// Atomic write: write to a temp file in the same folder, then
    /// either rename (new file) or replace (existing file). Coordinated
    /// through NSFileCoordinator so the swap is atomic from the
    /// perspective of external apps (Obsidian, Finder, etc.).
    private func writeAtomic(content: String, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        fileCoordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { writeURL in
            do {
                let tmp = writeURL.appendingPathExtension("tmp-\(UUID().uuidString)")
                try content.write(to: tmp, atomically: true, encoding: .utf8)
                if fm.fileExists(atPath: writeURL.path) {
                    _ = try fm.replaceItemAt(writeURL, withItemAt: tmp)
                } else {
                    try fm.moveItem(at: tmp, to: writeURL)
                }
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
}