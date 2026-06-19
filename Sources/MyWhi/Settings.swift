// AppSettings.swift
// Persisted user preferences. Class (not struct) so SwiftUI bindings work
// directly through @Published, and so onChange fires on any field update.
//
// v2.0: faster-whisper removed. WhisperKit is the only engine — the
// `engine` setting and `pythonPath` are gone. Existing settings.json
// files that still carry them decode without error but the values
// are ignored (they're not in CodingKeys).

import Foundation
import Combine
import Carbon.HIToolbox

final class AppSettings: ObservableObject, Codable {

    // MARK: Engine

    @Published var modelSize: String               // tiny|base|small|medium|large-v3|...
    @Published var language: String                // ru | en | auto

    // MARK: Behavior

    @Published var autoCopy: Bool                  // copy transcript to clipboard on finish
    @Published var saveHistory: Bool               // save to vault on finish
    @Published var autoPaste: Bool                 // simulate Cmd+V into active app (opt-in, Phase 6.2)
    @Published var useDarkMode: Bool               // override system color scheme (Phase 3.5)

    // MARK: Hotkey (Phase 6.3)

    /// Carbon modifier flags. Default Cmd+Option (= 0x1500 = cmdKey | optionKey).
    @Published var hotkeyModifiers: UInt32
    /// macOS virtual key code. Default 0x02 = D key.
    @Published var hotkeyKeyCode: UInt32

    // MARK: Live streaming (Phase 8)

    /// Show partial transcripts in the floating HUD as the user speaks
    /// (Phase 8 streaming). Default ON — this is the headline Wispr-Flow
    /// parity feature. Off = legacy behavior (text only after stop).
    @Published var liveStreamingEnabled: Bool

    /// Show a soft chime on record start/stop (Phase 9). Default ON.
    @Published var soundFeedbackEnabled: Bool

    // MARK: Available values

    static let availableModels: [(code: String, label: String, description: String)] = [
        ("tiny",            "tiny",            "~40 MB · fastest · lower accuracy"),
        ("base",            "base",            "~75 MB · fast · decent"),
        ("small",           "small",           "~250 MB · recommended for dictation"),
        ("medium",          "medium",          "~750 MB · high quality · slower first load"),
        ("large-v3-turbo",  "large-v3-turbo",  "~1.5 GB · best speed/quality tradeoff"),
        ("large-v3",        "large-v3",        "~1.5 GB · highest accuracy · slowest"),
    ]

    static let availableLanguages: [(code: String, label: String)] = [
        ("ru",   "Russian"),
        ("en",   "English"),
        ("auto", "Auto-detect"),
    ]

    init(
        modelSize: String = "small",
        language: String = "ru",
        autoCopy: Bool = true,
        saveHistory: Bool = true,
        autoPaste: Bool = false,
        useDarkMode: Bool = false,
        hotkeyModifiers: UInt32 = UInt32(cmdKey | optionKey),
        hotkeyKeyCode: UInt32 = 0x02,   // kVK_ANSI_D
        liveStreamingEnabled: Bool = true,
        soundFeedbackEnabled: Bool = true
    ) {
        // Validate inputs against known values; fall back to defaults so
        // a hand-edited settings file cannot crash the app.
        let validModels = AppSettings.availableModels.map(\.code)
        self.modelSize = validModels.contains(modelSize) ? modelSize : "small"

        let validLangCodes = AppSettings.availableLanguages.map(\.code)
        self.language = validLangCodes.contains(language) ? language : "ru"

        self.autoCopy = autoCopy
        self.saveHistory = saveHistory
        self.autoPaste = autoPaste
        self.useDarkMode = useDarkMode
        self.hotkeyModifiers = hotkeyModifiers
        self.hotkeyKeyCode = hotkeyKeyCode
        self.liveStreamingEnabled = liveStreamingEnabled
        self.soundFeedbackEnabled = soundFeedbackEnabled
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
    //
    // `engine` and `pythonPath` are intentionally NOT in CodingKeys.
    // They were dropped in v2.0. Old settings.json files that still
    // contain them decode without error (ignored) and will be cleaned
    // up the next time `save()` runs.

    enum CodingKeys: String, CodingKey {
        case modelSize, language, autoCopy, saveHistory, autoPaste, useDarkMode,
             hotkeyModifiers, hotkeyKeyCode, liveStreamingEnabled, soundFeedbackEnabled
    }

    convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            modelSize: try c.decodeIfPresent(String.self, forKey: .modelSize) ?? "small",
            language: try c.decodeIfPresent(String.self, forKey: .language) ?? "ru",
            autoCopy: try c.decodeIfPresent(Bool.self, forKey: .autoCopy) ?? true,
            saveHistory: try c.decodeIfPresent(Bool.self, forKey: .saveHistory) ?? true,
            autoPaste: try c.decodeIfPresent(Bool.self, forKey: .autoPaste) ?? false,
            useDarkMode: try c.decodeIfPresent(Bool.self, forKey: .useDarkMode) ?? false,
            hotkeyModifiers: try c.decodeIfPresent(UInt32.self, forKey: .hotkeyModifiers)
                ?? UInt32(cmdKey | optionKey),
            hotkeyKeyCode: try c.decodeIfPresent(UInt32.self, forKey: .hotkeyKeyCode)
                ?? 0x02,   // kVK_ANSI_D
            // Phase 8 / 9: default-on for both. Old settings.json files
            // that don't have these keys decode as true.
            liveStreamingEnabled: try c.decodeIfPresent(Bool.self, forKey: .liveStreamingEnabled) ?? true,
            soundFeedbackEnabled: try c.decodeIfPresent(Bool.self, forKey: .soundFeedbackEnabled) ?? true
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(modelSize, forKey: .modelSize)
        try c.encode(language, forKey: .language)
        try c.encode(autoCopy, forKey: .autoCopy)
        try c.encode(saveHistory, forKey: .saveHistory)
        try c.encode(autoPaste, forKey: .autoPaste)
        try c.encode(useDarkMode, forKey: .useDarkMode)
        try c.encode(hotkeyModifiers, forKey: .hotkeyModifiers)
        try c.encode(hotkeyKeyCode, forKey: .hotkeyKeyCode)
        try c.encode(liveStreamingEnabled, forKey: .liveStreamingEnabled)
        try c.encode(soundFeedbackEnabled, forKey: .soundFeedbackEnabled)
    }
}