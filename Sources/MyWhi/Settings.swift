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
    static let recommendedSoniqoModel = "qwen3-0.6b-8bit"

    // MARK: Engine

    @Published var modelSize: String               // tiny|base|small|medium|large-v3|...
    @Published var language: String                // ru | en | auto
    @Published var transcriptionBackend: String    // whisperkit | soniqo
    @Published var soniqoModel: String             // qwen3-0.6b-8bit | qwen3-1.7b-8bit | parakeet | nemotron
    @Published var meetingModel: String            // Soniqo model used for Meeting Mode
    @Published var meetingContext: String          // hotwords / participants / project context
    @Published var meetingRecordSystemAudio: Bool  // capture call/system audio via ScreenCaptureKit
    @Published var meetingDenoiseAudio: Bool       // DeepFilterNet3 preprocessing through speech CLI
    @Published var meetingDiarizationEnabled: Bool // speaker split through speech diarize

    // MARK: Behavior

    @Published var autoCopy: Bool                  // copy transcript to clipboard on finish
    @Published var saveHistory: Bool               // save to vault on finish
    @Published var autoPaste: Bool                 // simulate Cmd+V into active app (opt-in, Phase 6.2)
    /// Phase 23: phantom cursor mode. When enabled (and Accessibility
    /// permission is granted), dictated text is typed character by
    /// character into the focused application instead of being
    /// pasted as a single Cmd+V. This is the Wispr Flow–style "text
    /// just appears" experience. Falls back to clipboard + Cmd+V if
    /// the permission is missing.
    @Published var phantomCursorMode: Bool
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

    /// How many seconds of audio the live-streaming loop decodes per
    /// tick. Smaller = lower latency per partial update but more
    /// likely to miss the start of words; larger = steadier text but
    /// higher decode cost per tick. Default 8s — a good balance for
    /// dictation (about one phrase). With Phase 14 sliding window,
    /// cost per tick is constant regardless of recording duration.
    @Published var liveWindowSeconds: Int

    /// Show a soft chime on record start/stop (Phase 9). Default ON.
    @Published var soundFeedbackEnabled: Bool

    // MARK: Inline editor (Phase 11)

    /// When ON, the menu-bar popover shows an editable TextEditor for
    /// the last transcript. User can tweak wording before clicking
    /// "Insert" — which copies + (optionally) pastes into the active
    /// app. Default OFF to preserve the legacy auto-copy-on-stop flow.
    @Published var inlineEditorMode: Bool

    // MARK: Push-to-talk (Phase 13)

    /// When ON, the global hotkey behaves as push-to-talk (hold the
    /// key to record, release to stop). When OFF (default), the hotkey
    /// toggles recording on each press.
    @Published var pushToTalkMode: Bool

    // MARK: Floating HUD position (Phase 15)

    /// When ON, MyWhi shows the small idle floating record prompt on
    /// the desktop before recording starts. Default OFF: the global
    /// HUD should confirm active recording/transcription, not occupy
    /// the user's workspace while idle.
    @Published var showIdleFloatingHUD: Bool

    /// Where to anchor the floating HUD panel. Wispr Flow uses bottom
    /// (near the cursor). Phase 20 flipped the default from .top
    /// (legacy MyWhi convention) to .bottom (Wispr Flow convention).
    /// Users who already had settings.json with hudPosition set are
    /// unaffected (the decoder uses .top as a fallback only when the
    /// key is missing or invalid).
    enum HUDPosition: String, Codable {
        case top, bottom
    }
    @Published var hudPosition: HUDPosition

    // MARK: Voice commands (Phase 17)

    /// When ON, the live transcriber passes a "voice commands" prompt
    /// to WhisperKit (e.g. "Period. Comma, New line. Question mark?").
    /// The decoder learns to render those phrases as their punctuation
    /// characters. Default ON — it's a Wispr Flow parity feature and
    /// the bias is mild enough that it doesn't hurt regular dictation.
    @Published var voiceCommandsEnabled: Bool

    // MARK: Post-processing

    /// When ON, transcripts are post-processed to remove filler words,
    /// fix punctuation, and capitalize sentences. Uses Apple Intelligence
    /// on macOS 15+, falls back to regex on older versions. Default ON.
    @Published var postProcessingEnabled: Bool

    // MARK: Available values

    static let availableModels: [(code: String, label: String, description: String)] = [
        ("tiny",            "tiny",            "~40 MB · самый быстрый · ниже точность"),
        ("base",            "base",            "~75 MB · быстрый · базовая точность"),
        ("small",           "small",           "~250 MB · рекомендован для диктовки"),
        ("medium",          "medium",          "~750 MB · выше качество · медленнее первый запуск"),
        ("large-v3-turbo",  "large-v3-turbo",  "~1.5 GB · лучший баланс скорости и качества"),
        ("large-v3",        "large-v3",        "~1.5 GB · максимальная точность · самый медленный"),
    ]

    static let availableBackends: [(code: String, label: String, description: String)] = [
        ("whisperkit", "WhisperKit", "стабильный нативный движок для быстрой диктовки"),
        ("soniqo", "Soniqo Speech", "экспериментальный high-accuracy backend через локальный speech CLI"),
    ]

    static let availableSoniqoModels: [(code: String, label: String, description: String)] = [
        ("qwen3-0.6b-8bit", "Qwen3 0.6B 8-bit", "рекомендовано · лучший баланс качества и скорости для RU/EN"),
        ("qwen3-1.7b-8bit", "Qwen3 1.7B 8-bit", "максимальное качество, больше RAM"),
        ("parakeet", "Parakeet TDT", "очень быстрый batch ASR"),
        ("nemotron", "Nemotron Streaming", "пунктуация и streaming-oriented ASR"),
    ]

    static let availableLanguages: [(code: String, label: String)] = [
        ("ru",   "Русский"),
        ("en",   "Английский"),
        ("auto", "Авто"),
    ]

    init(
        modelSize: String = "small",
        language: String = "ru",
        transcriptionBackend: String = "whisperkit",
        soniqoModel: String = AppSettings.recommendedSoniqoModel,
        meetingModel: String = AppSettings.recommendedSoniqoModel,
        meetingContext: String = "",
        meetingRecordSystemAudio: Bool = true,
        meetingDenoiseAudio: Bool = true,
        meetingDiarizationEnabled: Bool = true,
        autoCopy: Bool = true,
        saveHistory: Bool = true,
        autoPaste: Bool = false,
        phantomCursorMode: Bool = false,
        useDarkMode: Bool = false,
        hotkeyModifiers: UInt32 = UInt32(cmdKey | optionKey),
        hotkeyKeyCode: UInt32 = 0x02,   // kVK_ANSI_D
        liveStreamingEnabled: Bool = true,
        liveWindowSeconds: Int = 8,
        soundFeedbackEnabled: Bool = true,
        inlineEditorMode: Bool = false,
        pushToTalkMode: Bool = false,
        showIdleFloatingHUD: Bool = false,
        hudPosition: HUDPosition = .bottom,
        voiceCommandsEnabled: Bool = true,
        postProcessingEnabled: Bool = true
    ) {
        // Validate inputs against known values; fall back to defaults so
        // a hand-edited settings file cannot crash the app.
        let validModels = AppSettings.availableModels.map(\.code)
        self.modelSize = validModels.contains(modelSize) ? modelSize : "small"

        let validLangCodes = AppSettings.availableLanguages.map(\.code)
        self.language = validLangCodes.contains(language) ? language : "ru"

        let validBackends = AppSettings.availableBackends.map(\.code)
        self.transcriptionBackend = validBackends.contains(transcriptionBackend) ? transcriptionBackend : "whisperkit"

        let validSoniqoModels = AppSettings.availableSoniqoModels.map(\.code)
        self.soniqoModel = validSoniqoModels.contains(soniqoModel) ? soniqoModel : AppSettings.recommendedSoniqoModel
        self.meetingModel = validSoniqoModels.contains(meetingModel) ? meetingModel : AppSettings.recommendedSoniqoModel
        self.meetingContext = meetingContext
        self.meetingRecordSystemAudio = meetingRecordSystemAudio
        self.meetingDenoiseAudio = meetingDenoiseAudio
        self.meetingDiarizationEnabled = meetingDiarizationEnabled

        // Validate window seconds: 4-30s range.
        let clampedWindow = max(4, min(30, liveWindowSeconds))
        self.liveWindowSeconds = clampedWindow

        self.autoCopy = autoCopy
        self.saveHistory = saveHistory
        self.autoPaste = autoPaste
        self.phantomCursorMode = phantomCursorMode
        self.useDarkMode = useDarkMode
        self.hotkeyModifiers = hotkeyModifiers
        self.hotkeyKeyCode = hotkeyKeyCode
        self.liveStreamingEnabled = liveStreamingEnabled
        self.soundFeedbackEnabled = soundFeedbackEnabled
        self.inlineEditorMode = inlineEditorMode
        self.pushToTalkMode = pushToTalkMode
        self.showIdleFloatingHUD = showIdleFloatingHUD
        self.hudPosition = hudPosition
        self.voiceCommandsEnabled = voiceCommandsEnabled
        self.postProcessingEnabled = postProcessingEnabled
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
             hotkeyModifiers, hotkeyKeyCode, liveStreamingEnabled, soundFeedbackEnabled,
             inlineEditorMode, pushToTalkMode, liveWindowSeconds, hudPosition,
             voiceCommandsEnabled, phantomCursorMode, showIdleFloatingHUD,
             postProcessingEnabled, transcriptionBackend, soniqoModel, meetingModel,
             meetingContext, meetingRecordSystemAudio, meetingDenoiseAudio,
             meetingDiarizationEnabled
    }

    convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let hudPosRaw = try c.decodeIfPresent(String.self, forKey: .hudPosition)
        let hudPos: HUDPosition = {
            if let raw = hudPosRaw, let pos = HUDPosition(rawValue: raw) { return pos }
            return .top
        }()
        self.init(
            modelSize: try c.decodeIfPresent(String.self, forKey: .modelSize) ?? "small",
            language: try c.decodeIfPresent(String.self, forKey: .language) ?? "ru",
            transcriptionBackend: try c.decodeIfPresent(String.self, forKey: .transcriptionBackend) ?? "whisperkit",
            soniqoModel: try c.decodeIfPresent(String.self, forKey: .soniqoModel) ?? AppSettings.recommendedSoniqoModel,
            meetingModel: try c.decodeIfPresent(String.self, forKey: .meetingModel) ?? AppSettings.recommendedSoniqoModel,
            meetingContext: try c.decodeIfPresent(String.self, forKey: .meetingContext) ?? "",
            meetingRecordSystemAudio: try c.decodeIfPresent(Bool.self, forKey: .meetingRecordSystemAudio) ?? true,
            meetingDenoiseAudio: try c.decodeIfPresent(Bool.self, forKey: .meetingDenoiseAudio) ?? true,
            meetingDiarizationEnabled: try c.decodeIfPresent(Bool.self, forKey: .meetingDiarizationEnabled) ?? true,
            autoCopy: try c.decodeIfPresent(Bool.self, forKey: .autoCopy) ?? true,
            saveHistory: try c.decodeIfPresent(Bool.self, forKey: .saveHistory) ?? true,
            autoPaste: try c.decodeIfPresent(Bool.self, forKey: .autoPaste) ?? false,
            // Phase 23: default OFF. Most users on a non-US keyboard
            // layout will prefer clipboard+paste; phantom cursor is
            // opt-in.
            phantomCursorMode: try c.decodeIfPresent(Bool.self, forKey: .phantomCursorMode) ?? false,
            useDarkMode: try c.decodeIfPresent(Bool.self, forKey: .useDarkMode) ?? false,
            hotkeyModifiers: try c.decodeIfPresent(UInt32.self, forKey: .hotkeyModifiers)
                ?? UInt32(cmdKey | optionKey),
            hotkeyKeyCode: try c.decodeIfPresent(UInt32.self, forKey: .hotkeyKeyCode)
                ?? 0x02,   // kVK_ANSI_D
            // Phase 8 / 9: default-on for both. Old settings.json files
            // that don't have these keys decode as true.
            liveStreamingEnabled: try c.decodeIfPresent(Bool.self, forKey: .liveStreamingEnabled) ?? true,
            // Phase 14: default 8s sliding window.
            liveWindowSeconds: try c.decodeIfPresent(Int.self, forKey: .liveWindowSeconds) ?? 8,
            soundFeedbackEnabled: try c.decodeIfPresent(Bool.self, forKey: .soundFeedbackEnabled) ?? true,
            // Phase 11 / 13: default OFF for backward compatibility with
            // existing users.
            inlineEditorMode: try c.decodeIfPresent(Bool.self, forKey: .inlineEditorMode) ?? false,
            pushToTalkMode: try c.decodeIfPresent(Bool.self, forKey: .pushToTalkMode) ?? false,
            showIdleFloatingHUD: try c.decodeIfPresent(Bool.self, forKey: .showIdleFloatingHUD) ?? false,
            hudPosition: hudPos,
            // Phase 17: default ON for voice commands (mild bias,
            // useful for most users).
            voiceCommandsEnabled: try c.decodeIfPresent(Bool.self, forKey: .voiceCommandsEnabled) ?? true,
            postProcessingEnabled: try c.decodeIfPresent(Bool.self, forKey: .postProcessingEnabled) ?? true
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(modelSize, forKey: .modelSize)
        try c.encode(language, forKey: .language)
        try c.encode(transcriptionBackend, forKey: .transcriptionBackend)
        try c.encode(soniqoModel, forKey: .soniqoModel)
        try c.encode(meetingModel, forKey: .meetingModel)
        try c.encode(meetingContext, forKey: .meetingContext)
        try c.encode(meetingRecordSystemAudio, forKey: .meetingRecordSystemAudio)
        try c.encode(meetingDenoiseAudio, forKey: .meetingDenoiseAudio)
        try c.encode(meetingDiarizationEnabled, forKey: .meetingDiarizationEnabled)
        try c.encode(autoCopy, forKey: .autoCopy)
        try c.encode(saveHistory, forKey: .saveHistory)
        try c.encode(autoPaste, forKey: .autoPaste)
        try c.encode(phantomCursorMode, forKey: .phantomCursorMode)
        try c.encode(useDarkMode, forKey: .useDarkMode)
        try c.encode(hotkeyModifiers, forKey: .hotkeyModifiers)
        try c.encode(hotkeyKeyCode, forKey: .hotkeyKeyCode)
        try c.encode(liveStreamingEnabled, forKey: .liveStreamingEnabled)
        try c.encode(soundFeedbackEnabled, forKey: .soundFeedbackEnabled)
        try c.encode(inlineEditorMode, forKey: .inlineEditorMode)
        try c.encode(pushToTalkMode, forKey: .pushToTalkMode)
        try c.encode(showIdleFloatingHUD, forKey: .showIdleFloatingHUD)
        try c.encode(liveWindowSeconds, forKey: .liveWindowSeconds)
        try c.encode(hudPosition.rawValue, forKey: .hudPosition)
        try c.encode(voiceCommandsEnabled, forKey: .voiceCommandsEnabled)
        try c.encode(postProcessingEnabled, forKey: .postProcessingEnabled)
    }
}
