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
    @Published private(set) var history: [HistoryEntry] = []
    @Published var errorMessage: String?

    /// Which engine is currently active (for UI display).
    @Published private(set) var activeEngineName: String = "WhisperKit"

    /// True when we fell back from WhisperKit → faster-whisper after an error.
    @Published private(set) var engineDidFallback: Bool = false

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
    let statsObserver: StatsObserver

    /// Set by AppContainer after init so AppState can ask the router to
    /// switch scenes (e.g. switch from .desktop → .menuBar when the
    /// last window closes).
    weak var sceneRouter: AppSceneRouter?

    // MARK: - Init

    init() {
        let loaded = AppSettings.load()
        self.settings = loaded
        self.engineManager = EngineManager(pythonPath: loaded.pythonPath)
        self.historyStore = HistoryStore()
        self.clipboard = ClipboardService()
        let vs = VaultStore()
        let vi = VaultIndex()
        self.vaultStore = vs
        self.vaultIndex = vi
        self.statsObserver = StatsObserver(vaultStore: vs, vaultIndex: vi)
        self.history = historyStore.load()

        // Persist settings on any change.
        settings.objectWillChange
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.settings.save()
            }
            .store(in: &cancellables)

        // Pre-load the engine in the background so the first recording is fast.
        Task { @MainActor [weak self] in
            await self?.preloadEngine()
        }

        // Run one-time migration from history.json → vault, then refresh.
        Task { @MainActor [weak self] in
            await self?.statsObserver.runMigrationIfNeeded()
            await self?.statsObserver.refresh()
        }
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Engine

    private func preloadEngine() async {
        do {
            try await engineManager.setEngine(settings.engine, model: settings.modelSize)
            self.activeEngineName = engineManager.activeName
            self.engineDidFallback = engineManager.didFallback
        } catch {
            NSLog("MyWhi.AppState: engine preload failed: \(error)")
            // Don't surface to UI — the error will re-appear at recording time.
        }
    }

    /// Called from Settings when the user changes engine or model.
    func reloadEngine() async {
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
                try self.recorder.start()
                self.status = .recording
            } catch {
                self.status = .error
                self.errorMessage = "Failed to start recording: \(error.localizedDescription)"
            }
        }
    }

    func stopRecording() {
        guard status == .recording else { return }
        do {
            let url = try recorder.stop()
            status = .transcribing
            errorMessage = nil
            transcribeFile(at: url)
        } catch {
            status = .error
            errorMessage = "Failed to stop recording: \(error.localizedDescription)"
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

    private func transcribeFile(at url: URL) {
        let model = settings.modelSize
        let language = settings.language
        let autoCopy = settings.autoCopy
        let saveHistory = settings.saveHistory
        let engine = settings.engine
        let filename = url.lastPathComponent

        Task { @MainActor in
            do {
                // Ensure the engine is loaded with the configured model.
                try await engineManager.setEngine(engine, model: model)
                self.activeEngineName = engineManager.activeName
                self.engineDidFallback = engineManager.didFallback

                let text = try await engineManager.transcribe(
                    audioPath: url.path,
                    model: model,
                    language: language
                )
                self.lastTranscript = text

                if autoCopy && !text.isEmpty {
                    self.clipboard.copy(text)
                }

                if saveHistory && !text.isEmpty {
                    // Save to vault (markdown + SQLite index).
                    _ = await statsObserver.recordTranscript(
                        text: text,
                        language: language,
                        model: model,
                        engine: engine,
                        durationSeconds: 0,  // populated in Phase 3 from AVAudioRecorder duration
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
                }

                self.status = .copied
            } catch {
                self.status = .error
                self.errorMessage = "Transcription failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - History interactions

    func copyFromHistory(_ entry: HistoryEntry) {
        clipboard.copy(entry.text)
        lastTranscript = entry.text
        status = .copied
    }

    func clearHistory() {
        historyStore.clear()
        history = []
    }
}