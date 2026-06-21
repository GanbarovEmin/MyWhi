// LanguageDetector.swift
// Lightweight on-device language detection for partial transcripts.
// Uses simple heuristics (Cyrillic vs Latin script ratio) — no ML model needed.

import Foundation

@MainActor
final class LanguageDetector {
    static let shared = LanguageDetector()

    private init() {}

    /// Detect language from text. Returns "ru", "en", or "auto".
    /// Designed for partial/streaming text — works on short fragments.
    func detectLanguage(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "auto" }

        let cyrillicCount = trimmed.unicodeScalars.filter { isCyrillic($0) }.count
        let latinCount = trimmed.unicodeScalars.filter { isLatin($0) }.count
        let totalLetters = cyrillicCount + latinCount

        guard totalLetters > 0 else { return "auto" }

        let cyrillicRatio = Double(cyrillicCount) / Double(totalLetters)

        // Thresholds tuned for mixed Russian/English text
        if cyrillicRatio > 0.6 {
            return "ru"
        } else if cyrillicRatio < 0.4 {
            return "en"
        } else {
            return "auto"
        }
    }

    private func isCyrillic(_ scalar: UnicodeScalar) -> Bool {
        // Cyrillic range: U+0400–U+04FF
        (0x0400...0x04FF).contains(scalar.value)
    }

    private func isLatin(_ scalar: UnicodeScalar) -> Bool {
        // Basic Latin: U+0041–U+007A (A-Z, a-z)
        // Latin-1 Supplement: U+00C0–U+00FF
        let value = scalar.value
        return (0x0041...0x007A).contains(value) || (0x00C0...0x00FF).contains(value)
    }
}