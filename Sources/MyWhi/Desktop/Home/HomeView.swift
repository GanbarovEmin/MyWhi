// HomeView.swift
// "Запись" tab — the hero control. Large record button, live waveform,
// last-transcript card, engine indicator, and drag-and-drop import.
//
// Phase 7 changes:
// - Migrated to HDTheme (`@Environment(\.hdTheme)`) — dark mode coherent.
// - Hardcoded fonts/colors → HDFont + theme tokens.
// - Performance: wordsToday() is computed once via @State and refreshed
//   on statsObserver.notes change (was O(n) per frame previously).

import SwiftUI

struct HomeView: View {

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var statsObserver: StatsObserver
    @Environment(\.hdTheme) private var theme

    @State private var wordsTodayCache: Int = 0
    @State private var notesRevision: Int = 0

    private var wordsToday: Int { wordsTodayCache }

    var body: some View {
        ZStack {
            theme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: HDSpacing.xxl.rawValue) {
                    header
                    todayBar
                    recordControl

                    if !appState.lastTranscript.isEmpty {
                        lastTranscriptCard
                    }

                    if statsObserver.notes.isEmpty {
                        OnboardingCard()
                    }

                    dropHint
                }
                .padding(HDSpacing.xxl.rawValue)
                .frame(maxWidth: 720)
            }
            .onDrop(of: [.fileURL, .audio, .data], isTargeted: nil) { providers in
                handleDrop(providers: providers)
            }
        }
        .onAppear { recomputeWordsToday() }
        .onChange(of: statsObserver.notes) { _, _ in recomputeWordsToday() }
    }

    private func recomputeWordsToday() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        wordsTodayCache = statsObserver.notes
            .filter { cal.startOfDay(for: $0.frontmatter.createdAt) == today }
            .reduce(0) { $0 + $1.frontmatter.words }
    }

    /// Sticky "сегодня" status bar — shows today's word count and
    /// current streak right under the header.
    private var todayBar: some View {
        let stats = statsObserver.stats
        return HStack(spacing: HDSpacing.lg.rawValue) {
            stat(value: "\(wordsToday)", label: "слов сегодня")
            divider
            stat(value: "\(stats.currentStreak) дн.", label: "текущая серия")
            divider
            stat(value: "\(stats.totalNotes)", label: "транскрибаций")
            Spacer()
        }
        .padding(HDSpacing.md.rawValue)
        .background(
            RoundedRectangle(cornerRadius: HDRadius.md.rawValue, style: .continuous)
                .fill(theme.surfaceStone)
        )
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(HDFont.statValue)
                .foregroundStyle(theme.ink)
                .monospacedDigit()
            Text(label.uppercased())
                .font(HDFont.monoLabel(size: 9))
                .hdTracking(0.5)
                .foregroundStyle(theme.muted)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.cardBorder)
            .frame(width: 1, height: 28)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: HDSpacing.xs.rawValue) {
            Text("ЗАПИСЬ")
                .font(HDFont.monoLabel(size: 12))
                .hdTracking(0.5)
                .foregroundStyle(theme.muted)
            Text("Скажи — увидишь текст")
                .font(HDFont.cardHeading)
                .hdTracking(-0.32)
                .foregroundStyle(theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Record control

    private var recordControl: some View {
        let state: HDRecordState = {
            switch appState.status {
            case .recording:    return .recording
            case .transcribing: return .transcribing
            default:            return .idle
            }
        }()

        return VStack(spacing: HDSpacing.xl.rawValue) {
            HDRecordButton(state: state, size: 96) {
                appState.toggleRecording()
            }

            if appState.status == .recording {
                HDWaveformView(
                    level: appState.recorderLevel,
                    style: .hero,
                    color: theme.deepGreen
                )
                .frame(maxWidth: 280)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))

                if !appState.livePartialTranscript.isEmpty {
                    Text(appState.livePartialTranscript)
                        .font(HDFont.bodyLarge)
                        .foregroundStyle(theme.ink)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 560)
                        .padding(.horizontal, HDSpacing.xl.rawValue)
                        .transition(.opacity)
                }
            }

            statusLabel
        }
        .padding(.vertical, HDSpacing.xl.rawValue)
        .animation(.easeInOut(duration: 0.18), value: appState.status)
    }

    private var statusLabel: some View {
        VStack(spacing: HDSpacing.xs.rawValue) {
            Text(statusHeadline)
                .font(HDFont.statusHeadline)
                .foregroundStyle(statusColor)

            if let err = appState.errorMessage {
                Text(err)
                    .font(HDFont.caption)
                    .foregroundStyle(theme.error)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, HDSpacing.xl.rawValue)
            } else {
                Text(statusSubtitle)
                    .font(HDFont.caption)
                    .foregroundStyle(theme.muted)
            }
        }
    }

    private var statusHeadline: String {
        switch appState.status {
        case .idle:         return "Готово к записи"
        case .recording:    return "Идёт запись…"
        case .transcribing: return "Транскрибация…"
        case .copied:       return "Готово · в буфере"
        case .error:        return "Ошибка"
        }
    }

    private var statusSubtitle: String {
        let model = appState.settings.modelSize
        let engine = appState.activeEngineName
        switch appState.status {
        case .idle:         return "\(engine) · \(model)"
        case .recording:    return "Говори сейчас"
        case .transcribing: return "Подожди пару секунд"
        case .copied:       return "⌘V — вставить"
        case .error:        return ""
        }
    }

    private var statusColor: Color {
        switch appState.status {
        case .recording:    return theme.deepGreen
        case .transcribing: return theme.coral
        case .copied:       return theme.ink
        case .error:        return theme.error
        default:            return theme.ink
        }
    }

    // MARK: - Drag-and-drop import

    private var dropHint: some View {
        HStack(spacing: HDSpacing.sm.rawValue) {
            Image(systemName: "tray.and.arrow.down")
                .font(HDFont.iconSmall)
                .foregroundStyle(theme.muted)
            Text("Перетащи .wav / .m4a файл сюда для транскрибации")
                .font(HDFont.caption)
                .foregroundStyle(theme.muted)
            Spacer()
            // Phase 10: coral button — a secondary CTA for the file picker.
            // HDButtonCoral was defined as a taxonomy chip but never used
            // in real UI; this gives it a purpose. Disabled during
            // recording / transcribing to avoid racing the engine.
            HDButtonCoral(
                title: "Файл…",
                isSelected: false
            ) {
                openFilePicker()
            }
            .disabled(
                appState.status == .recording ||
                appState.status == .transcribing
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, HDSpacing.lg.rawValue)
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .wav, .mpeg4Audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            appState.transcribeImportedFile(at: url)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async {
                appState.transcribeImportedFile(at: url)
            }
        }
        return true
    }

    // MARK: - Last transcript

    private var lastTranscriptCard: some View {
        VStack(alignment: .leading, spacing: HDSpacing.md.rawValue) {
            HStack {
                Text("ПОСЛЕДНЯЯ ТРАНСКРИБАЦИЯ")
                    .font(HDFont.monoLabel(size: 11))
                    .hdTracking(0.4)
                    .foregroundStyle(theme.muted)
                Spacer()
                Text("\(appState.lastTranscript.count) символов")
                    .font(HDFont.micro)
                    .foregroundStyle(theme.muted)
            }

            Text(appState.lastTranscript)
                .font(HDFont.bodyLarge)
                .foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            HStack(spacing: HDSpacing.md.rawValue) {
                HDButtonSecondary(title: "Скопировать", icon: "doc.on.doc") {
                    appState.clipboard.copy(appState.lastTranscript)
                }
                HDButtonSecondary(title: "Открыть в Scratchpad", icon: "arrow.right") {
                    NotificationCenter.default.post(
                        name: .mywhiNavigateToScratchpad,
                        object: nil,
                        userInfo: ["query": appState.lastTranscript]
                    )
                }
            }
        }
        .padding(HDSpacing.xl.rawValue)
        .background(
            RoundedRectangle(cornerRadius: HDRadius.lg.rawValue, style: .continuous)
                .fill(theme.surfaceStone)
        )
    }
}