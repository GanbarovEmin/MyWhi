// TranscriptNote.swift
// A note in the vault: frontmatter + body. Cheap to instantiate —
// `body` is lazy-loaded via VaultStore when needed.

import Foundation

struct TranscriptNote: Identifiable, Hashable {

    /// The note's stable identifier (matches `frontmatter.id`).
    var id: UUID

    /// Path to the `.md` file on disk.
    var url: URL

    /// Parsed from the frontmatter on disk. Always present after init.
    var frontmatter: TranscriptFrontmatter

    /// The Markdown body. Lazily populated by VaultStore; the list view
    /// can leave this empty and only load it when the detail view opens.
    var body: String

    /// Convenience: first non-empty line of the body, trimmed and
    /// truncated. Used for list rows and the menu bar.
    var title: String {
        let first = body
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Untitled note" }
        if trimmed.count <= 60 { return trimmed }
        return String(trimmed.prefix(60)) + "…"
    }
}