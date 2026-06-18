// MainPopoverView.swift
// The single window anchored to the menu bar icon. Reuses shared
// components from the Design System so the visual language matches
// the desktop app exactly.
//
// Phase 2.2 / 2.3 changes:
// - Live HDWaveformView while recording (compact mode, 12 bars)
// - Explicit "Остановить" Stop button when status == .recording
// - Live duration counter in the header
// - "Отменить" Discard button — calls AppState.discardRecording()

import SwiftUI

struct MainPopoverView: View {

    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var statsObserver: StatsObserver

    private var recentNotes: [TranscriptNote] {
        Array(statsObserver.notes.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HDSpacing.lg.rawValue) {
            header
            if let err = appState.errorMessage, !err.isEmpty {
                errorBanner(err)
            }
            quickRecord
            if appState.status == .recording {
                recordingControls
            }
            if !appState.lastTranscript.isEmpty && appState.status != .recording {
                lastTranscriptCard
            }
            if !recentNotes.isEmpty {
                recentList
            }
            footer
        }
        .padding(HDSpacing.lg.rawValue)
        .frame(width: 380)
        .background(HDColor.canvas)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: HDSpacing.md.rawValue) {
            Image(systemName: appState.status.iconName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(statusColor)
                .symbolEffect(.pulse, options: .repeating, isActive: appState.status == .recording)

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.status.rawValue)
                    .font(HDFont.featureHeading)
                    .foregroundStyle(HDColor.ink)
                HStack(spacing: HDSpacing.xs.rawValue) {
                    Text("MyWhi")
                        .font(HDFont.caption)
                        .foregroundStyle(HDColor.muted)
                    Text("·")
                        .font(HDFont.caption)
                        .foregroundStyle(HDColor.muted)
                    Text(appState.activeEngineName)
                        .font(HDFont.monoLabel(size: 11))
                        .foregroundStyle(HDColor.muted)
                }
            }
            Spacer()
            if appState.status == .recording {
                RecordingDurationView()
            }
        }
    }

    private var statusColor: Color {
        switch appState.status {
        case .recording:    return HDColor.deepGreen
        case .transcribing: return HDColor.coral
        case .copied:       return HDColor.actionBlue
        case .error:        return HDColor.error
        default:            return HDColor.muted
        }
    }

    // MARK: - Error

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(HDFont.caption)
            .foregroundStyle(HDColor.onDark)
            .padding(HDSpacing.md.rawValue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: HDRadius.sm.rawValue, style: .continuous)
                    .fill(HDColor.error)
            )
            .lineLimit(4)
    }

    // MARK: - Quick record (idle / transcribing)

    private var quickRecord: some View {
        let state: HDRecordState = {
            switch appState.status {
            case .recording:    return .recording
            case .transcribing: return .transcribing
            default:            return .idle
            }
        }()

        return HStack(spacing: HDSpacing.md.rawValue) {
            HDRecordButton(state: state, size: 48) {
                appState.toggleRecording()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(actionLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HDColor.ink)
                Text(hintLabel)
                    .font(HDFont.micro)
                    .foregroundStyle(HDColor.muted)
            }

            Spacer()

            Button {
                appState.transcribeLastRecording()
            } label: {
                Image(systemName: "waveform")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .disabled(appState.recorder.lastRecordingURL == nil
                      || appState.status == .recording
                      || appState.status == .transcribing)
        }
    }

    // MARK: - Recording controls (live waveform + stop + discard)

    private var recordingControls: some View {
        VStack(spacing: HDSpacing.md.rawValue) {
            // Live waveform fills the width
            HDWaveformView(
                level: appState.recorder.currentLevel,
                style: .compact,
                color: HDColor.deepGreen
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, HDSpacing.xs.rawValue)

            HStack(spacing: HDSpacing.md.rawValue) {
                HDButtonPrimary(
                    title: "Остановить",
                    icon: "stop.fill"
                ) {
                    appState.stopRecording()
                }
                .keyboardShortcut(.return, modifiers: [])

                Button {
                    appState.discardRecording()
                } label: {
                    Label("Отменить", systemImage: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(HDColor.muted)
                }
                .buttonStyle(.plain)
                .help("Удалить запись без транскрибации (Esc)")
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(HDSpacing.md.rawValue)
        .background(
            RoundedRectangle(cornerRadius: HDRadius.md.rawValue, style: .continuous)
                .fill(HDColor.paleGreen)
        )
    }

    private var actionLabel: String {
        switch appState.status {
        case .recording:    return "Говори…"
        case .transcribing: return "Транскрибация…"
        case .copied:       return "Готово · в буфере"
        default:            return "Готово к записи"
        }
    }

    private var hintLabel: String {
        let model = appState.settings.modelSize
        switch appState.status {
        case .idle:    return "Engine \(appState.activeEngineName) · \(model)"
        case .copied:  return "Cmd+V"
        default:       return ""
        }
    }

    // MARK: - Last transcript

    private var lastTranscriptCard: some View {
        HDCard(.stone, cornerRadius: .md, padding: .md) {
            VStack(alignment: .leading, spacing: HDSpacing.sm.rawValue) {
                HStack {
                    Text("ПОСЛЕДНЯЯ")
                        .font(HDFont.monoLabel(size: 10))
                        .hdTracking(0.5)
                        .foregroundStyle(HDColor.muted)
                    Spacer()
                    Text("\(appState.lastTranscript.count) символов")
                        .font(HDFont.micro)
                        .foregroundStyle(HDColor.muted)
                }
                Text(appState.lastTranscript)
                    .font(.system(size: 13))
                    .foregroundStyle(HDColor.ink)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                HStack {
                    HDButtonSecondary(title: "Копировать") {
                        appState.clipboard.copy(appState.lastTranscript)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Recent

    private var recentList: some View {
        VStack(alignment: .leading, spacing: HDSpacing.xs.rawValue) {
            Text("НЕДАВНИЕ")
                .font(HDFont.monoLabel(size: 10))
                .hdTracking(0.5)
                .foregroundStyle(HDColor.muted)
            ForEach(recentNotes, id: \.id) { note in
                Button {
                    appState.clipboard.copy(note.body)
                } label: {
                    HStack(alignment: .top, spacing: HDSpacing.sm.rawValue) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11))
                            .foregroundStyle(HDColor.muted)
                            .frame(width: 14)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title)
                                .font(.system(size: 12))
                                .foregroundStyle(HDColor.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text("\(note.frontmatter.words) слов · \(note.frontmatter.createdAt.formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 10))
                                .foregroundStyle(HDColor.muted)
                        }
                        Spacer()
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(HDColor.muted)
                    }
                    .padding(.vertical, HDSpacing.xs.rawValue)
                    .padding(.horizontal, HDSpacing.sm.rawValue)
                    .background(
                        RoundedRectangle(cornerRadius: HDRadius.xs.rawValue, style: .continuous)
                            .fill(HDColor.softStone.opacity(0.5))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: HDSpacing.sm.rawValue) {
            Divider()

            // Hotkey hint — visible until the user has used the
            // global hotkey at least once. Audit #17.
            if !hotkeyHintDismissed {
                hotkeyHint
            }

            HStack {
                Text("v2.0 · \(statsObserver.stats.totalWords) слов всего")
                    .font(HDFont.micro)
                    .foregroundStyle(HDColor.muted)
                Spacer()
                HDButtonSecondary(title: "Открыть MyWhi", icon: "arrow.up.right.square") {
                    NotificationCenter.default.post(name: .mywhiOpenDesktop, object: nil)
                    container.sceneRouter.setMode(.desktop)
                }
            }
        }
    }

    @AppStorage("mywhi.hotkeyHintShown") private var hotkeyHintDismissed: Bool = false

    private var hotkeyHint: some View {
        HStack(spacing: HDSpacing.sm.rawValue) {
            Image(systemName: "keyboard")
                .font(.system(size: 12))
                .foregroundStyle(HDColor.coral)
            VStack(alignment: .leading, spacing: 1) {
                Text("Глобальный hotkey")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HDColor.ink)
                Text("Нажми ⌘⌥D из любого приложения")
                    .font(.system(size: 10))
                    .foregroundStyle(HDColor.muted)
            }
            Spacer()
            Button {
                hotkeyHintDismissed = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(HDColor.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(HDSpacing.sm.rawValue)
        .background(
            RoundedRectangle(cornerRadius: HDRadius.xs.rawValue, style: .continuous)
                .fill(HDColor.paleGreen)
        )
    }
}

// MARK: - Recording duration counter

private struct RecordingDurationView: View {
    @State private var startTime: Date = Date()

    var body: some View {
        TimelineView(.periodic(from: startTime, by: 0.5)) { context in
            let elapsed = Int(Date().timeIntervalSince(startTime))
            Text(formatDuration(elapsed))
                .font(HDFont.monoLabel(size: 13, weight: .medium))
                .foregroundStyle(HDColor.deepGreen)
                .monospacedDigit()
        }
        .onAppear { startTime = Date() }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}