// AppState.swift
// Single source of truth for the UI. Owns the recorder, transcriber,
// clipboard, history, and settings. All mutations happen on the main
// actor; long-running work is dispatched to a background task.

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

    // Settings is an ObservableObject so SwiftUI bindings work directly.
    // `var` is required for $appState.settings.<field> bindings to compile
    // (the binding's setter writes through this property).
    var settings: AppSettings

    // MARK: - Services

    let recorder = AudioRecorder()
    let transcriber: Transcriber
    let historyStore: HistoryStore
    let clipboard: ClipboardService

    // MARK: - Init

    init() {
        let loaded = AppSettings.load()
        self.settings = loaded
        self.transcriber = Transcriber(pythonPath: loaded.pythonPath)
        self.historyStore = HistoryStore()
        self.clipboard = ClipboardService()
        self.history = historyStore.load()

        // Persist settings on any change.
        settings.objectWillChange
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.settings.save()
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

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
                self.errorMessage = "Microphone permission denied. Open System Settings → Privacy & Security → Microphone and allow Hermes Dictate."
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
        let filename = url.lastPathComponent

        Task { @MainActor in
            do {
                let text = try await transcriber.transcribe(
                    audioPath: url.path,
                    model: model,
                    language: language
                )
                self.lastTranscript = text

                if autoCopy && !text.isEmpty {
                    self.clipboard.copy(text)
                }

                if saveHistory && !text.isEmpty {
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
