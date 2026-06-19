// HomeView.swift
// "Запись" tab — the hero control. Large record button, live waveform,
// last-transcript card, engine indicator, and drag-and-drop import.

import SwiftUI

struct HomeView: View {

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var statsObserver: StatsObserver

    var body: some View {
        ZStack {
            HDColor.canvas.ignoresSafeArea()

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
    }

    /// Sticky "сегодня" status bar — shows today's word count and
    /// current streak right under the header.
    private var todayBar: some View {
        let stats = statsObserver.stats
        let todayWords = wordsToday()
        return HStack(spacing: HDSpacing.lg.rawValue) {
            stat(value: "\(todayWords)", label: "слов сегодня")
            divider
            stat(value: "\(stats.currentStreak) дн.", label: "текущая серия")
            divider
            stat(value: "\(stats.totalNotes)", label: "транскрибаций")
            Spacer()
        }
        .padding(HDSpacing.md.rawValue)
        .background(
            RoundedRectangle(cornerRadius: HDRadius.md.rawValue, style: .continuous)
                .fill(HDColor.softStone)
        )
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .default))
                .foregroundStyle(HDColor.ink)
                .monospacedDigit()
            Text(label.uppercased())
                .font(HDFont.monoLabel(size: 9))
                .hdTracking(0.5)
                .foregroundStyle(HDColor.muted)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(HDColor.cardBorder)
            .frame(width: 1, height: 28)
    }

    private func wordsToday() -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return statsObserver.notes
            .filter { cal.startOfDay(for: $0.frontmatter.createdAt) == today }
            .reduce(0) { $0 + $1.frontmatter.words }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: HDSpacing.xs.rawValue) {
            Text("ЗАПИСЬ")
                .font(HDFont.monoLabel(size: 12))
                .hdTracking(0.5)
                .foregroundStyle(HDColor.muted)
            Text("Скажи — увидишь текст")
                .font(HDFont.cardHeading)
                .hdTracking(-0.32)
                .foregroundStyle(HDColor.ink)
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
                    color: HDColor.deepGreen
                )
                .frame(maxWidth: 280)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            statusLabel
        }
        .padding(.vertical, HDSpacing.xl.rawValue)
        .animation(.easeInOut(duration: 0.18), value: appState.status)
    }

    private var statusLabel: some View {
        VStack(spacing: HDSpacing.xs.rawValue) {
            Text(statusHeadline)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(statusColor)

            if let err = appState.errorMessage {
                Text(err)
                    .font(HDFont.caption)
                    .foregroundStyle(HDColor.error)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, HDSpacing.xl.rawValue)
            } else {
                Text(statusSubtitle)
                    .font(HDFont.caption)
                    .foregroundStyle(HDColor.muted)
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
        case .recording:    return HDColor.deepGreen
        case .transcribing: return HDColor.coral
        case .copied:       return HDColor.ink
        case .error:        return HDColor.error
        default:            return HDColor.ink
        }
    }

    // MARK: - Drag-and-drop import

    private var dropHint: some View {
        HStack(spacing: HDSpacing.sm.rawValue) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 11))
                .foregroundStyle(HDColor.muted)
            Text("Перетащи .wav / .m4a файл сюда для транскрибации")
                .font(HDFont.caption)
                .foregroundStyle(HDColor.muted)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, HDSpacing.lg.rawValue)
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
                    .foregroundStyle(HDColor.muted)
                Spacer()
                Text("\(appState.lastTranscript.count) символов")
                    .font(HDFont.micro)
                    .foregroundStyle(HDColor.muted)
            }

            Text(appState.lastTranscript)
                .font(HDFont.bodyLarge)
                .foregroundStyle(HDColor.ink)
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
                .fill(HDColor.softStone)
        )
    }
}