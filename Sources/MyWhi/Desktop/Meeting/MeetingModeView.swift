import SwiftUI
import AppKit

struct MeetingModeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.hdTheme) private var theme

    private var meeting: MeetingModeService { appState.meetingMode }

    var body: some View {
        ZStack {
            theme.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: HDSpacing.xl.rawValue) {
                    header
                    controls
                    settings
                    output
                }
                .padding(HDSpacing.xxl.rawValue)
                .frame(maxWidth: 860, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: HDSpacing.xs.rawValue) {
            Text("MEETING MODE")
                .font(HDFont.monoLabel(size: 12))
                .hdTracking(0.5)
                .foregroundStyle(theme.muted)
            Text("Запись звонка, транскрипт, спикеры, summary")
                .font(HDFont.cardHeading)
                .foregroundStyle(theme.ink)
        }
    }

    private var controls: some View {
        HDCard(.canvas) {
            VStack(alignment: .leading, spacing: HDSpacing.lg.rawValue) {
                HStack(spacing: HDSpacing.lg.rawValue) {
                    Button {
                        primaryAction()
                    } label: {
                        Label(primaryTitle, systemImage: primaryIcon)
                            .font(HDFont.actionLabel)
                            .frame(minWidth: 180)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    if case .recording = meeting.state {
                        HDWaveformView(level: meeting.level, style: .compact, color: theme.deepGreen)
                            .frame(width: 160, height: 36)
                    }

                    Spacer()

                    Text(stateText)
                        .font(HDFont.caption)
                        .foregroundStyle(stateColor)
                }

                HStack(spacing: HDSpacing.sm.rawValue) {
                    Image(systemName: appState.settings.meetingRecordSystemAudio ? "speaker.wave.2.fill" : "speaker.slash")
                        .foregroundStyle(appState.settings.meetingRecordSystemAudio ? theme.deepGreen : theme.muted)
                    Text(meeting.systemAudioStatus)
                        .font(HDFont.caption)
                        .foregroundStyle(theme.muted)
                }

                if case .processing(let message) = meeting.state {
                    HStack(spacing: HDSpacing.sm.rawValue) {
                        ProgressView()
                            .controlSize(.small)
                        Text(message)
                            .font(HDFont.caption)
                            .foregroundStyle(theme.muted)
                    }
                }
            }
        }
    }

    private var settings: some View {
        HDCard(.canvas) {
            VStack(alignment: .leading, spacing: HDSpacing.md.rawValue) {
                Text("PIPELINE")
                    .font(HDFont.monoLabel(size: 11))
                    .hdTracking(0.5)
                    .foregroundStyle(theme.muted)

                Picker("ASR модель", selection: meetingModelBinding) {
                    ForEach(AppSettings.availableSoniqoModels, id: \.code) { model in
                        Text(model.label).tag(model.code)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Записывать системный звук звонка", isOn: systemAudioBinding)
                Toggle("Шумоподавление перед транскрибацией", isOn: denoiseBinding)
                Toggle("Разделять по говорящим", isOn: diarizationBinding)

                VStack(alignment: .leading, spacing: HDSpacing.xs.rawValue) {
                    Text("Контекст / участники / термины")
                        .font(HDFont.formLabel)
                        .foregroundStyle(theme.ink)
                    TextField("Например: проект MyWhi, Emin, клиент, product roadmap", text: meetingContextBinding, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    @ViewBuilder
    private var output: some View {
        switch meeting.state {
        case .done(let result):
            HDCard(.canvas) {
                VStack(alignment: .leading, spacing: HDSpacing.lg.rawValue) {
                    HStack {
                        Text(result.title)
                            .font(HDFont.featureHeading)
                            .foregroundStyle(theme.ink)
                        Spacer()
                        if let noteURL = result.noteURL {
                            HDButtonSecondary(title: "Открыть note", icon: "doc.text") {
                                NSWorkspace.shared.open(noteURL)
                            }
                        }
                    }

                    section("Summary", body: result.summary)
                    if !result.diarization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        section("Speakers JSON", body: result.diarization, mono: true)
                    }
                    section("Transcript", body: result.transcript)

                    HStack(spacing: HDSpacing.md.rawValue) {
                        if let url = result.systemAudioURL {
                            HDButtonSecondary(title: "System audio", icon: "speaker.wave.2") {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                        }
                        if let url = result.micAudioURL {
                            HDButtonSecondary(title: "Mic audio", icon: "mic") {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                        }
                        HDButtonSecondary(title: "Новая встреча", icon: "arrow.counterclockwise") {
                            meeting.reset()
                        }
                    }
                }
            }
        case .error(let message):
            HDCard(.stone) {
                VStack(alignment: .leading, spacing: HDSpacing.md.rawValue) {
                    Text("Ошибка Meeting Mode")
                        .font(HDFont.featureHeading)
                    Text(message)
                        .font(HDFont.bodySmall)
                        .foregroundStyle(theme.error)
                    HDButtonSecondary(title: "Сбросить", icon: "arrow.counterclockwise") {
                        meeting.reset()
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    private func section(_ title: String, body: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: HDSpacing.xs.rawValue) {
            Text(title.uppercased())
                .font(HDFont.monoLabel(size: 11))
                .foregroundStyle(theme.muted)
            Text(body)
                .font(mono ? HDFont.monoLabel(size: 11) : HDFont.bodySmall)
                .foregroundStyle(theme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func primaryAction() {
        switch meeting.state {
        case .idle, .done, .error:
            meeting.start(settings: appState.settings)
        case .recording:
            meeting.stopAndProcess(settings: appState.settings)
        case .processing:
            break
        }
    }

    private var primaryTitle: String {
        switch meeting.state {
        case .recording: return "Остановить и обработать"
        case .processing: return "Обработка..."
        default: return "Начать встречу"
        }
    }

    private var primaryIcon: String {
        switch meeting.state {
        case .recording: return "stop.fill"
        case .processing: return "hourglass"
        default: return "record.circle"
        }
    }

    private var stateText: String {
        switch meeting.state {
        case .idle: return SoniqoTranscriber.isAvailable() ? "Готово" : "Нужен brew install speech"
        case .recording(let started): return "Идёт запись с \(started.formatted(date: .omitted, time: .shortened))"
        case .processing(let message): return message
        case .done: return "Готово"
        case .error: return "Ошибка"
        }
    }

    private var stateColor: Color {
        switch meeting.state {
        case .recording: return theme.deepGreen
        case .error: return theme.error
        case .processing: return theme.coral
        default: return theme.muted
        }
    }

    private var meetingModelBinding: Binding<String> {
        Binding(get: { appState.settings.meetingModel }, set: { appState.settings.meetingModel = $0 })
    }

    private var systemAudioBinding: Binding<Bool> {
        Binding(get: { appState.settings.meetingRecordSystemAudio }, set: { appState.settings.meetingRecordSystemAudio = $0 })
    }

    private var denoiseBinding: Binding<Bool> {
        Binding(get: { appState.settings.meetingDenoiseAudio }, set: { appState.settings.meetingDenoiseAudio = $0 })
    }

    private var diarizationBinding: Binding<Bool> {
        Binding(get: { appState.settings.meetingDiarizationEnabled }, set: { appState.settings.meetingDiarizationEnabled = $0 })
    }

    private var meetingContextBinding: Binding<String> {
        Binding(get: { appState.settings.meetingContext }, set: { appState.settings.meetingContext = $0 })
    }
}
