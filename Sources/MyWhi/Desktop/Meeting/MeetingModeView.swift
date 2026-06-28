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
                .padding(.bottom, 92)
                .frame(maxWidth: 860, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: HDSpacing.xs.rawValue) {
                Text("MEETING MODE")
                    .font(HDFont.monoLabel(size: 12))
                    .hdTracking(0.5)
                    .foregroundStyle(theme.muted)
                Text("Рабочая встреча в текст")
                    .font(HDFont.cardHeading)
                    .foregroundStyle(theme.ink)
            }
            Spacer()
            Text(SoniqoTranscriber.isAvailable() ? "speech ready" : "speech CLI missing")
                .font(HDFont.monoLabel(size: 11, weight: .medium))
                .foregroundStyle(SoniqoTranscriber.isAvailable() ? theme.deepGreen : theme.coral)
                .padding(.horizontal, HDSpacing.md.rawValue)
                .padding(.vertical, 6)
                .background(Capsule().fill(theme.surfaceStone))
        }
    }

    private var controls: some View {
        HDCard(.dark, cornerRadius: .lg, padding: .xxl) {
            VStack(alignment: .leading, spacing: HDSpacing.xl.rawValue) {
                HStack(alignment: .center, spacing: HDSpacing.xl.rawValue) {
                    VStack(alignment: .leading, spacing: HDSpacing.sm.rawValue) {
                        Text(primaryHeadline)
                            .font(HDFont.featureHeading)
                            .foregroundStyle(theme.onDark)
                        Text(primarySubtitle)
                            .font(HDFont.caption)
                            .foregroundStyle(theme.onDark.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if case .recording(let started) = meeting.state {
                        MeetingDurationBadge(startedAt: started)
                    }
                    Button {
                        primaryAction()
                    } label: {
                        Label(primaryTitle, systemImage: primaryIcon)
                            .font(HDFont.actionLabel)
                            .frame(minWidth: 190)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isProcessing)
                }

                if case .recording = meeting.state {
                    HDWaveformView(level: meeting.level, style: .hero, color: theme.onDark)
                        .frame(maxWidth: 380)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                HStack(spacing: HDSpacing.md.rawValue) {
                    pipelineTile(icon: "mic.fill", title: "Микрофон", value: "Локальная дорожка", active: true)
                    pipelineTile(icon: appState.settings.meetingRecordSystemAudio ? "speaker.wave.2.fill" : "speaker.slash", title: "Звук звонка", value: meeting.systemAudioStatus, active: appState.settings.meetingRecordSystemAudio)
                    pipelineTile(icon: "person.wave.2.fill", title: "Спикеры", value: appState.settings.meetingDiarizationEnabled ? "Diarization on" : "Off", active: appState.settings.meetingDiarizationEnabled)
                }

                if case .processing(let message) = meeting.state {
                    processingRow(message)
                }
            }
        }
    }

    private var settings: some View {
        HDCard(.canvas) {
            VStack(alignment: .leading, spacing: HDSpacing.lg.rawValue) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pipeline")
                            .font(HDFont.settingsCardTitle)
                            .foregroundStyle(theme.ink)
                        Text("Настройки применятся к следующей обработке встречи.")
                            .font(HDFont.caption)
                            .foregroundStyle(theme.muted)
                    }
                    Spacer()
                    Picker("", selection: meetingModelBinding) {
                        ForEach(AppSettings.availableSoniqoModels, id: \.code) { model in
                            Text(model.label).tag(model.code)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 260)
                }

                HStack(spacing: HDSpacing.md.rawValue) {
                    pipelineToggle("System audio", "Звук звонка", isOn: systemAudioBinding)
                    pipelineToggle("Denoise", "Очистка шума", isOn: denoiseBinding)
                    pipelineToggle("Speakers", "Разделение", isOn: diarizationBinding)
                }

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

    private func pipelineTile(icon: String, title: String, value: String, active: Bool) -> some View {
        HStack(alignment: .top, spacing: HDSpacing.sm.rawValue) {
            Image(systemName: icon)
                .font(HDFont.iconSmall)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(HDFont.formLabel)
                    .lineLimit(1)
                Text(value)
                    .font(HDFont.micro)
                    .lineLimit(2)
                    .foregroundStyle(theme.onDark.opacity(0.66))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(active ? theme.onDark : theme.onDark.opacity(0.58))
        .padding(HDSpacing.md.rawValue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HDRadius.sm.rawValue, style: .continuous)
                .fill(Color.white.opacity(active ? 0.12 : 0.06))
        )
    }

    private func processingRow(_ message: String) -> some View {
        HStack(spacing: HDSpacing.sm.rawValue) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(HDFont.caption)
                .foregroundStyle(theme.onDark.opacity(0.78))
        }
    }

    private func pipelineToggle(_ title: String, _ subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(HDFont.formLabel)
                    .foregroundStyle(theme.ink)
                Text(subtitle)
                    .font(HDFont.micro)
                    .foregroundStyle(theme.muted)
            }
        }
        .toggleStyle(.switch)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        case .recording: return "Завершить встречу"
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

    private var primaryHeadline: String {
        switch meeting.state {
        case .idle: return "Готов записать звонок"
        case .recording: return "Идёт запись встречи"
        case .processing: return "Собираю транскрипт"
        case .done: return "Встреча обработана"
        case .error: return "Нужно действие"
        }
    }

    private var primarySubtitle: String {
        switch meeting.state {
        case .idle:
            return "Записывается микрофон и, если разрешено macOS, системный звук видеозвонка. После остановки появятся transcript, speakers и summary."
        case .recording:
            return "Оставь MyWhi открытым до конца звонка. Системный звук и микрофон сохраняются отдельными дорожками."
        case .processing(let message):
            return message
        case .done:
            return "Проверь summary ниже, открой note или начни следующую встречу."
        case .error(let message):
            return message
        }
    }

    private var isProcessing: Bool {
        if case .processing = meeting.state { return true }
        return false
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

private struct MeetingDurationBadge: View {
    let startedAt: Date

    var body: some View {
        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false, showsHours: true)
            .font(HDFont.monoLabel(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .monospacedDigit()
            .padding(.horizontal, HDSpacing.md.rawValue)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.14)))
    }
}
