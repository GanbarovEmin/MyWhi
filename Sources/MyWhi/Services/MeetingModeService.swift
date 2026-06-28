import Foundation
import Combine

struct MeetingTranscriptResult: Equatable {
    var title: String
    var startedAt: Date
    var finishedAt: Date
    var micAudioURL: URL?
    var systemAudioURL: URL?
    var transcript: String
    var diarization: String
    var summary: String
    var noteURL: URL?
}

@MainActor
final class MeetingModeService: ObservableObject {
    enum State: Equatable {
        case idle
        case recording(startedAt: Date)
        case processing(String)
        case done(MeetingTranscriptResult)
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var systemAudioStatus: String = "System audio idle"
    @Published private(set) var level: Float = 0

    private let micRecorder = AudioRecorder()
    private let systemRecorder = SystemAudioRecorder()
    private let vaultStore: VaultStore
    private var startedAt: Date?

    init(vaultStore: VaultStore) {
        self.vaultStore = vaultStore
        micRecorder.$currentLevel
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.level = value }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    func start(settings: AppSettings) {
        guard case .idle = state else { return }
        state = .processing("Preparing meeting recorders...")
        Task { @MainActor in
            do {
                let granted = await micRecorder.requestPermissionIfNeeded()
                guard granted else {
                    state = .error("Microphone permission denied.")
                    return
                }

                await micRecorder.prepare()
                try micRecorder.start()
                let start = Date()
                startedAt = start

                if settings.meetingRecordSystemAudio {
                    do {
                        _ = try await systemRecorder.start()
                        systemAudioStatus = "System audio recording"
                    } catch {
                        systemAudioStatus = "System audio unavailable: \(error.localizedDescription)"
                    }
                } else {
                    systemAudioStatus = "System audio disabled"
                }

                state = .recording(startedAt: start)
            } catch {
                micRecorder.cancel()
                systemRecorder.cancel()
                state = .error("Failed to start Meeting Mode: \(error.localizedDescription)")
            }
        }
    }

    func stopAndProcess(settings: AppSettings) {
        guard case .recording = state else { return }
        state = .processing("Stopping recorders...")

        Task { @MainActor in
            let finish = Date()
            let start = startedAt ?? finish
            let micURL: URL?
            do {
                micURL = try micRecorder.stop()
            } catch {
                state = .error("Failed to stop microphone recording: \(error.localizedDescription)")
                return
            }
            let systemURL = await systemRecorder.stop()
            micRecorder.resetLiveBuffer()

            do {
                let result = try await processMeeting(
                    startedAt: start,
                    finishedAt: finish,
                    micURL: micURL,
                    systemURL: systemURL,
                    settings: settings
                )
                state = .done(result)
            } catch {
                state = .error("Meeting processing failed: \(error.localizedDescription)")
            }
        }
    }

    func reset() {
        state = .idle
        systemAudioStatus = "System audio idle"
    }

    func cancel() {
        micRecorder.cancel()
        systemRecorder.cancel()
        state = .idle
        systemAudioStatus = "System audio idle"
    }

    private func processMeeting(
        startedAt: Date,
        finishedAt: Date,
        micURL: URL?,
        systemURL: URL?,
        settings: AppSettings
    ) async throws -> MeetingTranscriptResult {
        let context = settings.meetingContext
        var transcriptBlocks: [String] = []
        var diarization = ""

        let systemForASR = try await preparedAudio(
            systemURL,
            label: "system audio",
            denoise: settings.meetingDenoiseAudio
        )
        let micForASR = try await preparedAudio(
            micURL,
            label: "microphone",
            denoise: settings.meetingDenoiseAudio
        )

        if let systemForASR {
            state = .processing("Transcribing call audio with \(settings.meetingModel)...")
            let text = try await SoniqoTranscriber.transcribeFile(
                systemForASR,
                model: settings.meetingModel,
                language: settings.language,
                context: context
            )
            if !text.isEmpty {
                transcriptBlocks.append("## Call audio\n\n\(text)")
            }

            if settings.meetingDiarizationEnabled {
                state = .processing("Separating speakers...")
                diarization = try await SoniqoTranscriber.diarize(systemForASR)
            }
        }

        if let micForASR {
            state = .processing("Transcribing your microphone...")
            let text = try await SoniqoTranscriber.transcribeFile(
                micForASR,
                model: settings.meetingModel,
                language: settings.language,
                context: context
            )
            if !text.isEmpty {
                transcriptBlocks.append("## Your microphone\n\n\(text)")
            }
        }

        let transcript = transcriptBlocks.joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            throw NSError(
                domain: "MyWhi.MeetingMode",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No speech was transcribed from the meeting audio."]
            )
        }

        state = .processing("Preparing summary...")
        let summary = MeetingSummarizer.summarize(transcript)
        let title = "Meeting \(Self.titleFormatter.string(from: startedAt))"
        let markdown = Self.renderMarkdown(
            title: title,
            startedAt: startedAt,
            finishedAt: finishedAt,
            micURL: micURL,
            systemURL: systemURL,
            summary: summary,
            diarization: diarization,
            transcript: transcript
        )
        let note = try await vaultStore.save(
            transcript: markdown,
            language: settings.language,
            model: settings.meetingModel,
            engine: "Soniqo Meeting Mode",
            durationSeconds: finishedAt.timeIntervalSince(startedAt),
            audio: systemURL?.lastPathComponent ?? micURL?.lastPathComponent,
            date: startedAt
        )

        return MeetingTranscriptResult(
            title: title,
            startedAt: startedAt,
            finishedAt: finishedAt,
            micAudioURL: micURL,
            systemAudioURL: systemURL,
            transcript: transcript,
            diarization: diarization,
            summary: summary,
            noteURL: note.url
        )
    }

    private func preparedAudio(_ url: URL?, label: String, denoise: Bool) async throws -> URL? {
        guard let url else { return nil }
        guard denoise else { return url }
        state = .processing("Denoising \(label)...")
        let output = url.deletingPathExtension()
            .appendingPathExtension("clean.wav")
        do {
            return try await SoniqoTranscriber.denoise(url, output: output)
        } catch {
            NSLog("MyWhi.MeetingMode: denoise failed for \(label): \(error)")
            return url
        }
    }

    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private static func renderMarkdown(
        title: String,
        startedAt: Date,
        finishedAt: Date,
        micURL: URL?,
        systemURL: URL?,
        summary: String,
        diarization: String,
        transcript: String
    ) -> String {
        var lines: [String] = [
            "# \(title)",
            "",
            "- Started: \(startedAt)",
            "- Finished: \(finishedAt)",
        ]
        if let systemURL {
            lines.append("- System audio: \(systemURL.path)")
        }
        if let micURL {
            lines.append("- Microphone audio: \(micURL.path)")
        }
        lines.append("")
        lines.append("## Summary")
        lines.append("")
        lines.append(summary)
        lines.append("")
        if !diarization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("## Speakers")
            lines.append("")
            lines.append("```json")
            lines.append(diarization)
            lines.append("```")
            lines.append("")
        }
        lines.append("## Transcript")
        lines.append("")
        lines.append(transcript)
        return lines.joined(separator: "\n")
    }
}

private enum MeetingSummarizer {
    static func summarize(_ transcript: String) -> String {
        let cleaned = transcript
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sentences = cleaned
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 20 }

        let overview = sentences.prefix(5).map { "- \($0)." }.joined(separator: "\n")
        let actionWords = ["надо", "нужно", "сделать", "договорились", "action", "todo", "follow up", "next step"]
        let actions = sentences
            .filter { sentence in
                let lower = sentence.lowercased()
                return actionWords.contains { lower.contains($0) }
            }
            .prefix(8)
            .map { "- \($0)." }
            .joined(separator: "\n")

        var blocks: [String] = []
        blocks.append("### Кратко\n\(overview.isEmpty ? "- Summary will improve after a longer transcript." : overview)")
        blocks.append("### Action items\n\(actions.isEmpty ? "- Не найдено явных action items." : actions)")
        return blocks.joined(separator: "\n\n")
    }
}
