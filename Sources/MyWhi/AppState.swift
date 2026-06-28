// AppState.swift
// Single source of truth for the UI. Owns the recorder, engine manager,
// clipboard, history (legacy JSON), and settings. All mutations happen
// on the main actor; long-running work is dispatched to a background task.
//
// Phase 2: EngineManager replaces the old Transcriber. VaultStore is added
// in Phase 2B (currently history is still the legacy JSON HistoryStore).

import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {

    // MARK: - Published state

    @Published private(set) var status: AppStatus = .idle
    @Published private(set) var lastTranscript: String = ""
    @Published private(set) var recorderLevel: Float = 0
    @Published private(set) var history: [HistoryEntry] = []
    @Published var errorMessage: String?

    /// Which engine is currently active (for UI display).
    @Published private(set) var activeEngineName: String = "WhisperKit"

    /// True when we fell back from WhisperKit → faster-whisper after an error.
    @Published private(set) var engineDidFallback: Bool = false

    // Phase 8: live streaming transcript (updated ~0.8s during recording).
    @Published private(set) var livePartialTranscript: String = ""

    /// True while a partial decode is in flight. Drives a "transcribing…"
    /// indicator in the HUD.
    @Published private(set) var isLiveDecoding: Bool = false

    // Settings is an ObservableObject so SwiftUI bindings work directly.
    // `var` is required for $appState.settings.<field> bindings to compile
    // (the binding's setter writes through this property).
    var settings: AppSettings

    // MARK: - Services

    let recorder = AudioRecorder()
    let engineManager: EngineManager
    let historyStore: HistoryStore  // legacy JSON; kept for one migration
    let clipboard: ClipboardService
    let vaultStore: VaultStore
    let vaultIndex: VaultIndex
    let dictionaryStore: PersonalDictionaryStore
    let statsObserver: StatsObserver
    let meetingMode: MeetingModeService

    // Phase 8: rolling partial-decode loop driven by the rolling audio
    // buffer maintained in AudioRecorder.
    private var liveTranscriber: LiveTranscriber?

    /// Set by AppContainer after init so AppState can ask the router to
    /// switch scenes (e.g. switch from .desktop → .menuBar when the
    /// last window closes).
    weak var sceneRouter: AppSceneRouter?

    // MARK: - Init

    init() {
        let loaded = AppSettings.load()
        self.settings = loaded
        let em = EngineManager()
        em.appSettings = loaded   // Phase 17: engine reads voice-commands toggle
        self.engineManager = em
        self.historyStore = HistoryStore()
        self.clipboard = ClipboardService()
        let vs = VaultStore()
        let vi = VaultIndex()
        self.vaultStore = vs
        self.vaultIndex = vi
        self.dictionaryStore = PersonalDictionaryStore()
        self.statsObserver = StatsObserver(vaultStore: vs, vaultIndex: vi)
        self.meetingMode = MeetingModeService(vaultStore: vs)
        self.history = historyStore.load()

        recorder.$currentLevel
            .receive(on: RunLoop.main)
            .sink { [weak self] level in
                self?.recorderLevel = level
            }
            .store(in: &cancellables)

        // Forward nested settings changes through AppState. Views observe
        // AppState, not AppSettings directly, so without this a Picker can
        // update its own selection while the surrounding settings pane keeps
        // rendering stale backend/model-specific controls.
        settings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Persist settings on any change.
        settings.objectWillChange
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.settings.save()
            }
            .store(in: &cancellables)
        settings.save()

        // Pre-load the engine in the background so the first recording is fast.
        // We seed preloadTask up front so that ensureEngineLoaded() called
        // from transcribeFile (race: user records in the first 7s) awaits
        // the same Task instead of starting a parallel load.
        preloadTask = Task { @MainActor [weak self] in
            await self?.preloadEngine()
        }

        // One-time: remove the legacy /tmp/hermes-dictate folder from
        // the v1.0 codebase. The new path is /tmp/mywhi/recordings.
        cleanupLegacyRecordingsDir()

        // Run one-time migration from history.json → vault, then refresh.
        Task { @MainActor [weak self] in
            await self?.statsObserver.runMigrationIfNeeded()
            await self?.statsObserver.refresh()
        }
    }

    private func cleanupLegacyRecordingsDir() {
        let legacy = URL(fileURLWithPath: "/tmp/hermes-dictate", isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacy.path) else { return }
        // Move files into the new dir if they exist (preserves user's
        // last recording for "Transcribe Last" feature), then remove the
        // empty legacy dir.
        do {
            let contents = try fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)
            for url in contents {
                let dest = AudioRecorder.recordingsDir.appendingPathComponent(url.lastPathComponent)
                try? fm.moveItem(at: url, to: dest)
            }
            try fm.removeItem(at: legacy)
            NSLog("MyWhi.AppState: migrated legacy /tmp/hermes-dictate → /tmp/mywhi/recordings")
        } catch {
            NSLog("MyWhi.AppState: legacy cleanup failed: \(error)")
        }
    }

    private var cancellables = Set<AnyCancellable>()

    // Single in-flight preload so a recording that starts before preload
    // completes can await the same Task instead of triggering a parallel
    // engine swap. See #8 in audit.
    private var preloadTask: Task<Void, Never>?

    // MARK: - Engine

    private var activeEngineCode: String {
        settings.transcriptionBackend == "soniqo" ? "soniqo" : "whisperkit"
    }

    private var activeModelCode: String {
        settings.transcriptionBackend == "soniqo" ? settings.soniqoModel : settings.modelSize
    }

    /// Preload the engine on first use (called from init and from Settings
    /// when the user changes engine/model). Idempotent — concurrent callers
    /// share the same Task.
    private func preloadEngine() async {
        NSLog("MyWhi.AppState: preloadEngine starting (engine=\(activeEngineCode), model=\(activeModelCode))")
        do {
            try await engineManager.setEngine(activeEngineCode, model: activeModelCode)
            self.activeEngineName = engineManager.displayName
            self.engineDidFallback = engineManager.didFallback
            NSLog("MyWhi.AppState: preloadEngine done — active=\(activeEngineName), fallback=\(engineDidFallback)")
        } catch {
            NSLog("MyWhi.AppState: engine preload failed: \(error)")
            // Don't surface to UI — the error will re-appear at recording time.
        }
    }

    /// Public entry point — coalesces concurrent preload requests. Returns
    /// once the engine is loaded (or failed). Safe to await from anywhere
    /// on the main actor.
    func ensureEngineLoaded() async {
        if let task = preloadTask {
            await task.value
            return
        }
        let task: Task<Void, Never> = Task { @MainActor [weak self] in
            await self?.preloadEngine()
        }
        preloadTask = task
        await task.value
        // Don't clear preloadTask — we want subsequent calls to share it
        // until the user changes engine/model.
    }

    /// Called from Settings when the user changes engine or model.
    func reloadEngine() async {
        // Invalidate the in-flight preload so a new (name, model) pair
        // triggers a fresh load instead of returning a cached engine.
        preloadTask = nil
        await preloadEngine()
    }

    // MARK: - Recording flow

    func toggleRecording() {
        switch status {
        case .recording:
            stopRecording()
        default:
            startRecording()
        }
    }

    func startRecording() {
        guard status != .recording else { return }
        errorMessage = nil
        Task { @MainActor in
            let granted = await recorder.requestPermissionIfNeeded()
            guard granted else {
                self.status = .error
                self.errorMessage = "Microphone permission denied. Open System Settings → Privacy & Security → Microphone and allow MyWhi."
                return
            }
            do {
                await self.recorder.prepare()
                try self.recorder.start()
                self.status = .recording
                self.livePartialTranscript = ""
                self.recorder.resetLiveBuffer()
                self.startLiveStreaming()
            } catch {
                self.status = .error
                self.errorMessage = "Failed to start recording: \(error.localizedDescription)"
            }
        }
    }

    func stopRecording() {
        guard status == .recording else { return }
        // Tear down the live streaming loop first so it doesn't try to
        // transcribe a buffer that no longer makes sense (we're about
        // to close the file).
        liveTranscriber?.stop()
        // Phase 9: audible cue at recording stop.
        if settings.soundFeedbackEnabled {
            SoundFeedback.playStop()
        }
        do {
            let url = try recorder.stop()
            recorder.resetLiveBuffer()
            status = .transcribing
            errorMessage = nil
            transcribeFile(at: url)
        } catch {
            status = .error
            errorMessage = "Failed to stop recording: \(error.localizedDescription)"
        }
    }

    /// Cancel the in-flight recording and throw away the .wav file
    /// (audit #13: Esc / "Discard" — useful when the user started by
    /// accident, hit the wrong key, or is just testing).
    func discardRecording() {
        guard status == .recording else { return }
        liveTranscriber?.stop()
        recorder.cancel()
        recorder.resetLiveBuffer()
        livePartialTranscript = ""
        status = .idle
        errorMessage = nil
        NSLog("MyWhi.AppState: recording discarded")
    }

    // MARK: - Live streaming (Phase 8)

    private func startLiveStreaming() {
        guard activeEngineCode == "whisperkit" else {
            NSLog("MyWhi.AppState: live streaming disabled for \(activeEngineCode); final decode will use selected backend")
            return
        }
        if liveTranscriber == nil {
            liveTranscriber = LiveTranscriber(
                recorder: recorder,
                engineManager: engineManager,
                appState: self
            )
        }
        liveTranscriber?.start(
            model: activeModelCode,
            language: settings.language
        ) { [weak self] partial in
            self?.livePartialTranscript = partial
        }
        // Phase 9: audible cue at recording start (low-volume chime).
        // Gated on `settings.soundFeedbackEnabled` so users can disable
        // it from Settings.
        if settings.soundFeedbackEnabled {
            SoundFeedback.playStart()
        }
    }

    func transcribeLastRecording() {
        guard let url = recorder.lastRecordingURL else {
            errorMessage = "No previous recording available."
            return
        }
        status = .transcribing
        errorMessage = nil
        transcribeFile(at: url)
    }

    // MARK: - Transcribe + clipboard + history

    func transcribeImportedFile(at url: URL) {
        guard status != .recording && status != .transcribing else { return }
        status = .transcribing
        errorMessage = nil
        transcribeFile(at: url, durationSeconds: 0)
    }

    private func transcribeFile(at url: URL, durationSeconds: Double? = nil) {
        let engine = activeEngineCode
        let engineModel = activeModelCode
        let language = settings.language
        let autoCopy = settings.autoCopy
        let saveHistory = settings.saveHistory
        let filename = url.lastPathComponent

        Task { @MainActor in
            do {
                // Wait for any in-flight preload to finish (avoids a
                // race where a recording starts before the model is
                // ready — we'd hit the UnloadedTranscriber and throw).
                await ensureEngineLoaded()

                // Cache hit on subsequent recordings (no 6s re-init).
                try await engineManager.setEngine(engine, model: engineModel)
                self.activeEngineName = engineManager.displayName
                self.engineDidFallback = engineManager.didFallback

                let rawText = try await engineManager.transcribe(
                    audioPath: url.path,
                    model: engineModel,
                    language: language
                )
                let dictionary = await dictionaryStore.load()
                var text = TranscriptPolisher.polish(rawText, dictionary: dictionary)

                // Post-process with Apple Intelligence (macOS 15+) or regex fallback
                if settings.postProcessingEnabled {
                    text = await TranscriptPostProcessor.shared.process(text, language: language)
                }

                self.lastTranscript = text

                // Empty result handling: if WhisperKit returned no text
                // (silence, very short clip, or hallucination), don't
                // pretend the transcription succeeded. Show an
                // informative error so the user knows what happened.
                if text.isEmpty {
                    NSLog("MyWhi.AppState: empty transcription (engine=\(engine), model=\(engineModel), file=\(filename))")
                    self.status = .error
                    self.errorMessage = "Не удалось распознать речь. Попробуй говорить громче или дольше."
                    HapticFeedback.error.fire()
                    return
                }

                if autoCopy && !text.isEmpty {
                    // Phase 23: snapshot the clipboard BEFORE we
                    // overwrite it, so the user can Cmd+Shift+Z to
                    // restore. We only snapshot if there's actually
                    // something to restore (UndoService.snapshot()
                    // no-ops on empty input).
                    UndoService.shared.snapshot()
                    self.clipboard.copy(text)
                    // Phase 23: phantom cursor mode. When enabled (and
                    // Accessibility is granted), type the text
                    // character-by-character into the focused app
                    // instead of pasting. This is the Wispr Flow
                    // "text just appears" experience. Falls back to
                    // clipboard+Cmd+V if the permission is missing.
                    if settings.phantomCursorMode && PhantomCursorService.shared.isAccessibilityTrusted() {
                        PhantomCursorService.shared.typeText(text)
                    } else if settings.autoPaste {
                        AutoPasteService.pasteFromClipboard()
                    }
                    HapticFeedback.success.fire()
                }

                if saveHistory && !text.isEmpty {
                    // Save to vault (markdown + SQLite index).
                    _ = await statsObserver.recordTranscript(
                        text: text,
                        language: language,
                        model: engineModel,
                        engine: activeEngineName,
                        durationSeconds: durationSeconds ?? recorder.lastRecordingDuration,
                        audio: filename
                    )
                    // Keep legacy history in sync for the menu bar popover.
                    self.historyStore.add(
                        HistoryEntry(
                            text: text,
                            timestamp: Date(),
                            audioFilename: filename
                        ),
                        limit: 10
                    )
                    self.history = self.historyStore.load()

                    // Phase 7.13 — first-successful-transcript onboarding
                    // auto-dismiss. We use UserDefaults directly (matches
                    // the @AppStorage key the OnboardingCard reads) so
                    // the SwiftUI view re-renders without any extra
                    // plumbing.
                    UserDefaults.standard.set(true, forKey: "mywhi.hideOnboarding")
                }

                self.status = .copied
            } catch {
                self.status = .error
                self.errorMessage = "Transcription failed: \(error.localizedDescription)"
                HapticFeedback.error.fire()
            }
        }
    }

    // MARK: - History interactions

    func copyFromHistory(_ entry: HistoryEntry) {
        clipboard.copy(entry.text)
        lastTranscript = entry.text
        status = .copied
    }

    func returnToIdleIfCopied() {
        guard status == .copied else { return }
        status = .idle
    }

    func clearHistory() {
        historyStore.clear()
        history = []
    }

    /// Phase 11: promote the editor's edited draft to the canonical
    /// `lastTranscript`. Called from `MainPopoverView.commitDraft()`
    /// when the user clicks "Вставить" with edits in place. Keeps the
    /// `private(set)` invariant by routing through a dedicated method.
    func promoteLastTranscript(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastTranscript = trimmed
    }

    /// Phase 18: set the live-decoding indicator. Called by
    /// `LiveTranscriber.runOnce` around each WhisperKit decode so
    /// the UI can show a "транскрибирую…" pulse while the engine
    /// works. Routing through a dedicated method preserves the
    /// `private(set)` invariant on `isLiveDecoding`.
    func setIsLiveDecoding(_ value: Bool) {
        isLiveDecoding = value
    }
}
