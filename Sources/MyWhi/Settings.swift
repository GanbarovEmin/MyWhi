// AppSettings.swift
// Persisted user preferences. Class (not struct) so SwiftUI bindings work
// directly through @Published, and so onChange fires on any field update.

import Foundation
import Combine

final class AppSettings: ObservableObject, Codable {

    @Published var modelSize: String
    @Published var language: String
    @Published var autoCopy: Bool
    @Published var saveHistory: Bool
    @Published var pythonPath: String

    static let availableModels: [String] = [
        "small",
        "medium",
        "large-v3-turbo",
        "large-v3",
    ]

    static let availableLanguages: [(code: String, label: String)] = [
        ("ru",   "Russian"),
        ("en",   "English"),
        ("auto", "Auto-detect"),
    ]

    static let defaultPythonPath: String = {
        let home = NSHomeDirectory()
        return "\(home)/Documents/MyWhi/venv/bin/python3"
    }()

    init(
        modelSize: String = "medium",
        language: String = "ru",
        autoCopy: Bool = true,
        saveHistory: Bool = true,
        pythonPath: String = AppSettings.defaultPythonPath
    ) {
        // Validate model/language against known values; fall back to defaults
        // so a hand-edited settings file cannot crash the app.
        let validModels = AppSettings.availableModels
        self.modelSize = validModels.contains(modelSize) ? modelSize : "medium"

        let validLangCodes = AppSettings.availableLanguages.map(\.code)
        self.language = validLangCodes.contains(language) ? language : "ru"

        self.autoCopy = autoCopy
        self.saveHistory = saveHistory
        self.pythonPath = pythonPath.isEmpty ? AppSettings.defaultPythonPath : pythonPath
    }

    // MARK: - Persistence

    private static func configURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("MyWhi", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    static func load() -> AppSettings {
        let url = configURL()
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return AppSettings()
        }
        return decoded
    }

    func save() {
        let url = AppSettings.configURL()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            try data.write(to: url, options: .atomic)
        } catch {
            // Non-fatal: settings just won't persist this change.
            NSLog("MyWhi: failed to save settings: \(error)")
        }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case modelSize, language, autoCopy, saveHistory, pythonPath
    }

    convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            modelSize: try c.decodeIfPresent(String.self, forKey: .modelSize) ?? "medium",
            language: try c.decodeIfPresent(String.self, forKey: .language) ?? "ru",
            autoCopy: try c.decodeIfPresent(Bool.self, forKey: .autoCopy) ?? true,
            saveHistory: try c.decodeIfPresent(Bool.self, forKey: .saveHistory) ?? true,
            pythonPath: try c.decodeIfPresent(String.self, forKey: .pythonPath)
                ?? AppSettings.defaultPythonPath
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(modelSize, forKey: .modelSize)
        try c.encode(language, forKey: .language)
        try c.encode(autoCopy, forKey: .autoCopy)
        try c.encode(saveHistory, forKey: .saveHistory)
        try c.encode(pythonPath, forKey: .pythonPath)
    }
}
