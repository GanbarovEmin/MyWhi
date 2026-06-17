// VaultPaths.swift
// File-system layout for the Markdown-based vault of transcripts.
//
//   ~/Library/Application Support/MyWhi/vault/YYYY/MM/YYYY-MM-DD-HHMMSS-<slug>.md
//
// Year and month folders make scanning by date range cheap; the slug is
// derived from the first line of the transcript (or "note" fallback).

import Foundation

enum VaultPaths {

    /// Root of the vault. Created lazily on first write.
    static var root: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("MyWhi", isDirectory: true)
            .appendingPathComponent("vault", isDirectory: true)
    }

    /// Folder for a given year-month (e.g. `vault/2026/06/`).
    static func monthDir(for date: Date, calendar: Calendar = .current) -> URL {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let y = comps.year ?? 2026
        let m = String(format: "%02d", comps.month ?? 1)
        return root
            .appendingPathComponent("\(y)", isDirectory: true)
            .appendingPathComponent(m, isDirectory: true)
    }

    /// File name (without folder) for a new note at the given date.
    /// Format: `YYYY-MM-DD-HHMMSS-<slug>.md`.
    static func fileName(for date: Date, slug: String, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        let stamp = f.string(from: date)
        let cleanSlug = slugify(slug)
        return "\(stamp)-\(cleanSlug).md"
    }

    /// Full file URL for a new note. Caller is responsible for ensuring
    /// the parent directory exists.
    static func url(for date: Date, slug: String, calendar: Calendar = .current) -> URL {
        monthDir(for: date, calendar: calendar)
            .appendingPathComponent(fileName(for: date, slug: slug, calendar: calendar))
    }

    /// Make a URL-safe slug from arbitrary text. Latin lowercase, digits,
    /// dashes; collapse runs of separators; trim to 60 chars.
    static func slugify(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let alnum = CharacterSet.alphanumerics
        // Map alphanumerics through, all other characters become a dash.
        let scalars = lowered.unicodeScalars.map { scalar -> Character in
            alnum.contains(scalar) ? Character(scalar) : "-"
        }
        // Collapse runs of dashes.
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return String(collapsed.prefix(60)).trimmingCharacters(in: .whitespaces)
    }

    /// Ensure root + year/month folder exist. Returns the month dir URL.
    @discardableResult
    static func ensureMonthDir(for date: Date, calendar: Calendar = .current) throws -> URL {
        let dir = monthDir(for: date, calendar: calendar)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}