// TranscriptPostProcessor.swift
// Post-processing for transcripts: Apple Intelligence (macOS 15+) or regex fallback.
// Removes filler words, fixes punctuation, capitalizes sentences.
// Applies user-defined custom regex rules.

import Foundation

@MainActor
final class TranscriptPostProcessor {
    static let shared = TranscriptPostProcessor()

    private init() {}

    /// Process transcript text. Returns polished text or original if processing fails.
    func process(_ text: String, language: String) async -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }

        // Try Apple Intelligence first (macOS 15.0+)
        if #available(macOS 15.0, *) {
            if let polished = await processWithAppleIntelligence(text, language: language) {
                return polished
            }
        }

        // Fallback to regex-based processing
        return processWithRegex(text, language: language)
    }

    // MARK: - Apple Intelligence (macOS 15+)

    @available(macOS 15.0, *)
    private func processWithAppleIntelligence(_ text: String, language: String) async -> String? {
        // Note: FoundationModels framework would be used here in production.
        // For now, we return nil to fall through to regex since the framework
        // requires specific entitlements and model availability.
        // When FoundationModels is available, implement:
        //
        // let session = LanguageModelSession()
        // let prompt = """
        // Clean up this transcript: remove filler words (uhm, eh, like),
        // fix punctuation, capitalize sentences. Language: \(language).
        // Return ONLY the cleaned text:
        // \(text)
        // """
        // do {
        //     let response = try await session.respond(to: prompt)
        //     return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        // } catch {
        //     return nil
        // }
        return nil
    }

    // MARK: - Regex Fallback (works on all macOS versions)

    private func processWithRegex(_ text: String, language: String) -> String {
        var result = text

        // 1. Remove common filler words (Russian + English)
        let fillerWords: [String]
        switch language {
        case "ru":
            fillerWords = [
                "э-э-э", "э-э", "э", "эм", "ээ", "эээ",
                "ну", "как бы", "типа", "короче", "кстати",
                "блин", "да", "нет", "ага", "угу"
            ]
        case "en":
            fillerWords = [
                "um", "uh", "er", "ah", "eh",
                "like", "you know", "i mean", "sort of", "kind of",
                "basically", "actually", "literally", "so", "well"
            ]
        default:
            fillerWords = [
                "э-э-э", "э-э", "э", "эм", "ээ", "эээ",
                "ну", "как бы", "типа", "короче", "кстати",
                "um", "uh", "er", "ah", "eh",
                "like", "you know", "i mean"
            ]
        }

        // Build regex for filler words (case insensitive, word boundaries)
        let fillerPattern = fillerWords
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        let fillerRegex = try? NSRegularExpression(
            pattern: "\\b(?:\(fillerPattern))\\b",
            options: [.caseInsensitive]
        )
        if let regex = fillerRegex {
            let range = NSRange(location: 0, length: (result as NSString).length)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: ""
            )
        }

        // 2. Fix spacing around punctuation
        // Remove space before punctuation
        result = result.replacingOccurrences(
            of: "\\s+([.,!?;:])",
            with: "$1",
            options: .regularExpression
        )
        // Ensure space after punctuation (except end of string)
        result = result.replacingOccurrences(
            of: "([.,!?;:])(?=\\S)",
            with: "$1 ",
            options: .regularExpression
        )

        // 3. Collapse multiple spaces
        result = result.replacingOccurrences(
            of: "\\s{2,}",
            with: " ",
            options: .regularExpression
        )

        // 4. Capitalize first letter of sentences
        result = capitalizeSentences(result, language: language)

        // 5. Fix common transcription artifacts
        result = fixArtifacts(result, language: language)

        // 6. Apply user-defined custom regex rules
        result = PostProcessingRulesStore.shared.applyRules(to: result)

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func capitalizeSentences(_ text: String, language: String) -> String {
        // Split by sentence-ending punctuation followed by space using NSRegularExpression
        let pattern = "(?<=[.!?])\\s+"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: (text as NSString).length)
        let matches = regex?.matches(in: text, options: [], range: range) ?? []

        var sentences: [String] = []
        var lastIndex = 0
        for match in matches {
            let sentence = (text as NSString).substring(with: NSRange(location: lastIndex, length: match.range.location - lastIndex + match.range.length))
            sentences.append(sentence)
            lastIndex = match.range.location + match.range.length
        }
        if lastIndex < text.count {
            sentences.append((text as NSString).substring(from: lastIndex))
        }
        if sentences.isEmpty {
            sentences = [text]
        }

        return sentences.map { sentence in
            var s = sentence
            if let firstChar = s.first, firstChar.isLowercase {
                s.replaceSubrange(s.startIndex...s.startIndex, with: String(firstChar).uppercased())
            }
            return s
        }.joined(separator: " ")
    }

    private func fixArtifacts(_ text: String, language: String) -> String {
        var result = text

        // Common WhisperKit hallucinations / artifacts
        let artifacts: [(String, String)] = [
            // Whisper often hallucinates these at end of silence
            ("BLANK_AUDIO", ""),
            ("MUSIC", ""),
            ("Спасибо за просмотр", ""),
            ("Подпишитесь на канал", ""),
            ("Thanks for watching", ""),
            ("Subscribe to", ""),
        ]

        for (from, to) in artifacts {
            result = result.replacingOccurrences(
                of: from,
                with: to,
                options: [.caseInsensitive]
            )
        }

        // Remove duplicate punctuation (e.g., ".." -> ".", "???" -> "?")
        result = result.replacingOccurrences(
            of: "([.!?])\\1+",
            with: "$1",
            options: .regularExpression
        )

        return result
    }
}