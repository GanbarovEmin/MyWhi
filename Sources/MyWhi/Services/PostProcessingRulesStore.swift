// PostProcessingRulesStore.swift
// User-defined custom post-processing rules (regex patterns).
// Allows power users to define their own transcript cleanup rules.

import Foundation

struct PostProcessingRule: Codable, Identifiable, Equatable {
    let id: UUID
    var pattern: String
    var replacement: String
    var isEnabled: Bool
    var description: String

    init(id: UUID = UUID(), pattern: String, replacement: String, isEnabled: Bool = true, description: String = "") {
        self.id = id
        self.pattern = pattern
        self.replacement = replacement
        self.isEnabled = isEnabled
        self.description = description
    }
}

@MainActor
final class PostProcessingRulesStore: ObservableObject {
    static let shared = PostProcessingRulesStore()

    @Published private(set) var rules: [PostProcessingRule] = []

    private let rulesURL: URL

    private init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("MyWhi", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.rulesURL = dir.appendingPathComponent("post_processing_rules.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: rulesURL),
              let decoded = try? JSONDecoder().decode([PostProcessingRule].self, from: data) else {
            // Default rules for Russian users
            self.rules = defaultRules()
            save()
            return
        }
        self.rules = decoded
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(rules)
            try data.write(to: rulesURL, options: .atomic)
        } catch {
            NSLog("MyWhi.PostProcessingRulesStore: failed to save rules: \(error)")
        }
    }

    func addRule(_ rule: PostProcessingRule) {
        rules.append(rule)
        save()
    }

    func updateRule(_ rule: PostProcessingRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
            save()
        }
    }

    func deleteRule(id: UUID) {
        rules.removeAll { $0.id == id }
        save()
    }

    func toggleRule(id: UUID) {
        if let index = rules.firstIndex(where: { $0.id == id }) {
            rules[index].isEnabled.toggle()
            save()
        }
    }

    /// Apply all enabled rules to the text.
    func applyRules(to text: String) -> String {
        var result = text
        for rule in rules where rule.isEnabled {
            do {
                let regex = try NSRegularExpression(pattern: rule.pattern, options: [])
                let range = NSRange(location: 0, length: (result as NSString).length)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: rule.replacement)
            } catch {
                NSLog("MyWhi.PostProcessingRulesStore: invalid regex '\(rule.pattern)': \(error)")
            }
        }
        return result
    }

    private func defaultRules() -> [PostProcessingRule] {
        [
            PostProcessingRule(
                pattern: "\\b(э-э-э|э-э|э|эм|ээ|эээ|ну|как бы|типа|короче|кстати)\\b",
                replacement: "",
                description: "Удаление русских слов-паразитов"
            ),
            PostProcessingRule(
                pattern: "\\s+([.,!?;:])",
                replacement: "$1",
                description: "Убрать пробел перед знаками препинания"
            ),
            PostProcessingRule(
                pattern: "([.,!?;:])(?=\\S)",
                replacement: "$1 ",
                description: "Добавить пробел после знаков препинания"
            ),
            PostProcessingRule(
                pattern: "\\s{2,}",
                replacement: " ",
                description: "Схлопнуть множественные пробелы"
            )
        ]
    }
}