// TranscriptFrontmatter.swift
// YAML frontmatter for vault notes. Stored as:
//
//   ---
//   id: 8A1B2C3D-...
//   created_at: 2026-06-17T14:23:18Z
//   language: ru
//   model: small
//   engine: whisperkit
//   duration_seconds: 12.5
//   chars: 482
//   words: 78
//   audio: recording-1721234598.wav
//   ---
//
// We hand-roll YAML (no deps) because the frontmatter is fully
// machine-generated — no need for a full YAML lib.

import Foundation

struct TranscriptFrontmatter: Codable, Equatable, Hashable {

    var id: UUID
    var createdAt: Date
    var language: String
    var model: String
    var engine: String              // "whisperkit" | "faster-whisper"
    var durationSeconds: Double
    var chars: Int
    var words: Int
    var audio: String?              // filename of the source recording (optional)

    // MARK: - YAML

    /// Render as YAML frontmatter (delimited by `---`). Includes a
    /// trailing newline before the closing fence so the body starts on
    /// a fresh line.
    func renderYAML() -> String {
        var lines: [String] = ["---"]
        lines.append("id: \(id.uuidString)")
        lines.append("created_at: \(iso8601String(createdAt))")
        lines.append("language: \(language)")
        lines.append("model: \(model)")
        lines.append("engine: \(engine)")
        lines.append("duration_seconds: \(formatNumber(durationSeconds))")
        lines.append("chars: \(chars)")
        lines.append("words: \(words)")
        if let audio, !audio.isEmpty {
            lines.append("audio: \(audio)")
        }
        lines.append("---")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Parse YAML frontmatter from a note's full content. Returns nil if
    /// no `---`-delimited frontmatter block is present.
    static func parse(from content: String) -> (frontmatter: TranscriptFrontmatter, body: String)? {
        // Split off the frontmatter block.
        let lines = content.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }

        // Find the closing fence.
        var endIdx: Int? = nil
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                endIdx = i
                break
            }
        }
        guard let endIdx else { return nil }

        let yamlLines = Array(lines[1..<endIdx])
        let bodyLines = Array(lines[(endIdx + 1)...])
        let body = bodyLines.joined(separator: "\n")

        var dict: [String: String] = [:]
        for line in yamlLines {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let val = parts[1].trimmingCharacters(in: .whitespaces)
            dict[key] = val
        }

        guard
            let idStr = dict["id"], let id = UUID(uuidString: idStr),
            let createdStr = dict["created_at"], let createdAt = parseISO8601(createdStr)
        else {
            return nil
        }

        let fm = TranscriptFrontmatter(
            id: id,
            createdAt: createdAt,
            language: dict["language"] ?? "auto",
            model: dict["model"] ?? "small",
            engine: dict["engine"] ?? "whisperkit",
            durationSeconds: Double(dict["duration_seconds"] ?? "0") ?? 0,
            chars: Int(dict["chars"] ?? "0") ?? 0,
            words: Int(dict["words"] ?? "0") ?? 0,
            audio: dict["audio"]
        )
        return (fm, body)
    }

    // MARK: - Helpers

    private func iso8601String(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    private static func parseISO8601(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    private func formatNumber(_ n: Double) -> String {
        if n == n.rounded() { return String(Int(n)) }
        return String(format: "%.2f", n)
    }
}