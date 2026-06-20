// TranscriptPolisher.swift
// Lightweight local post-processing for raw Whisper transcripts.
// This is intentionally local-only: no network calls, no telemetry.

import Foundation

struct DictionaryReplacement: Codable, Hashable {
    let from: String
    let to: String
}

actor PersonalDictionaryStore {

    private let url: URL

    init(url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            let dir = base.appendingPathComponent("MyWhi", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.url = dir.appendingPathComponent("dictionary.json")
        }
    }

    func load() -> [DictionaryReplacement] {
        guard let data = try? Data(contentsOf: url) else { return [] }

        if let array = try? JSONDecoder().decode([DictionaryReplacement].self, from: data) {
            return array
        }

        // Also accept a simple object shape:
        // { "ашбис": "ASBIS", "айспейс": "iSpace" }
        if let map = try? JSONDecoder().decode([String: String].self, from: data) {
            return map.map { DictionaryReplacement(from: $0.key, to: $0.value) }
        }

        return []
    }
}

enum TranscriptPolisher {

    static func polish(_ raw: String, dictionary: [DictionaryReplacement] = []) -> String {
        // Strip BOM (UTF-8 byte-order mark) that some upstream tools
        // emit at the start of files.
        var text = raw.replacingOccurrences(of: "\u{FEFF}", with: "")

        // WhisperKit's "[BLANK_AUDIO]" / "[MUSIC]" markers — these are
        // model-side annotations, not user speech.
        text = text.replacingOccurrences(of: "[BLANK_AUDIO]", with: "", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "[MUSIC]", with: "", options: .caseInsensitive)

        text = normalizeWhitespace(text)
        text = normalizePunctuationSpacing(text)
        text = applyDictionary(dictionary, to: text)
        text = capitalizeFirstLetter(text)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed
    }

    private static func normalizePunctuationSpacing(_ text: String) -> String {
        var result = text
        let replacements: [(String, String)] = [
            (" ,", ","),
            (" .", "."),
            (" !", "!"),
            (" ?", "?"),
            (" ;", ";"),
            (" :", ":"),
            (",,", ","),
            ("..", "."),
            ("!!", "!"),
            ("??", "?")
        ]
        for (from, to) in replacements {
            while result.contains(from) {
                result = result.replacingOccurrences(of: from, with: to)
            }
        }
        return result
    }

    private static func applyDictionary(_ replacements: [DictionaryReplacement], to text: String) -> String {
        guard !replacements.isEmpty else { return text }
        var result = text
        for replacement in replacements where !replacement.from.isEmpty {
            result = result.replacingOccurrences(
                of: replacement.from,
                with: replacement.to,
                options: [.caseInsensitive, .diacriticInsensitive]
            )
        }
        return result
    }

    private static func capitalizeFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        if first.isLetter {
            return first.uppercased() + text.dropFirst()
        }
        return text
    }
}