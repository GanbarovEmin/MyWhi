// HomeView.swift
// "Запись" tab — the hero control. Large record button, last-transcript
// card, engine indicator, optional waveform while recording.

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

            statusLabel
        }
        .padding(.vertical, HDSpacing.xl.rawValue)
    }

    private var statusLabel: some View {
        VStack(spacing: HDSpacing.xs.rawValue) {
            Text(statusHeadline)
                .font(HDFont.featureHeading)
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
        case .idle:         return "Engine: \(engine) · Model: \(model)"
        case .recording:    return "Говори сейчас"
        case .transcribing: return "Подожди пару секунд"
        case .copied:       return "Cmd+V вставить"
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
                Task {
                    await transcribeFile(at: url)
                }
            }
        }
        return true
    }

    private func transcribeFile(at url: URL) async {
        let model = appState.settings.modelSize
        let language = appState.settings.language
        let engine = appState.settings.engine

        appState.objectWillChange.send()
        // We don't have a direct "transcribing from file" hook on AppState,
        // but we can reuse the same engine pipeline. This re-implements
        // AppState.transcribeFile in the public shape.
        do {
            try await appState.engineManager.setEngine(engine, model: model)
            let text = try await appState.engineManager.transcribe(
                audioPath: url.path,
                model: model,
                language: language
            )
            _ = await appState.statsObserver.recordTranscript(
                text: text,
                language: language,
                model: model,
                engine: appState.activeEngineName,
                durationSeconds: 0,
                audio: url.lastPathComponent
            )
        } catch {
            NSLog("MyWhi.HomeView: drop-import failed: \(error)")
        }
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
                    // Triggered via notification; DesktopRootView will switch selection.
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