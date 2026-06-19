// FloatingVoiceHUDView.swift
// A compact Wispr Flow-like voice surface shown above the active app while
// MyWhi is listening, transcribing, or has just copied text.
//
// Phase 7: HDTheme migration, HDColor.X → theme.X, hardcoded fonts →
// HDFont tokens, DurationView uses Text(_:style:.timer).

import SwiftUI

struct FloatingVoiceHUDView: View {

    @EnvironmentObject private var appState: AppState
    @Environment(\.hdTheme) private var theme

    var body: some View {
        HStack(spacing: HDSpacing.md.rawValue) {
            statusGlyph

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: HDSpacing.sm.rawValue) {
                    Text(title)
                        .font(HDFont.hudTitle)
                        .foregroundStyle(theme.ink)
                    if appState.status == .recording {
                        FloatingDurationView()
                    }
                }

                if appState.status == .recording {
                    if !appState.livePartialTranscript.isEmpty {
                        Text(appState.livePartialTranscript)
                            .font(HDFont.hudLiveText)
                            .foregroundStyle(theme.ink)
                            .lineLimit(2)
                            .transition(.opacity)
                    } else {
                        HDWaveformView(
                            level: appState.recorderLevel,
                            style: .compact,
                            color: theme.deepGreen
                        )
                        .frame(width: 168)
                    }
                } else {
                    Text(subtitle)
                        .font(HDFont.micro)
                        .foregroundStyle(theme.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: HDSpacing.sm.rawValue)

            if appState.status == .recording {
                Button {
                    appState.discardRecording()
                } label: {
                    Image(systemName: "xmark")
                        .font(HDFont.hudIconClose)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.muted)
                .help("Отменить запись")

                Button {
                    appState.stopRecording()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(HDFont.hudIconStop)
                        .frame(width: 32, height: 32)
                        .foregroundStyle(theme.onPrimary)
                        .background(Circle().fill(theme.primary))
                }
                .buttonStyle(.plain)
                .help("Остановить и транскрибировать")
            }
        }
        .padding(.horizontal, HDSpacing.lg.rawValue)
        .padding(.vertical, HDSpacing.md.rawValue)
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: HDRadius.xl.rawValue, style: .continuous)
                .fill(theme.surface.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: HDRadius.xl.rawValue, style: .continuous)
                        .stroke(theme.border, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.14), radius: 24, x: 0, y: 14)
        )
        .animation(.easeInOut(duration: 0.18), value: appState.status)
        .animation(.easeInOut(duration: 0.18), value: appState.livePartialTranscript)
    }

    private var statusGlyph: some View {
        ZStack {
            Circle()
                .fill(glyphBackground)
                .frame(width: 42, height: 42)
            Image(systemName: appState.status.iconName)
                .font(HDFont.hudGlyph)
                .foregroundStyle(glyphForeground)
        }
        .symbolEffect(.pulse, options: .repeating, isActive: appState.status == .recording)
    }

    private var glyphBackground: Color {
        switch appState.status {
        case .recording:    return theme.surfacePaleGreen
        case .transcribing: return theme.coralSoft.opacity(0.45)
        case .copied:       return theme.surfacePaleBlue
        case .error:        return theme.error.opacity(0.12)
        case .idle:         return theme.surfaceStone
        }
    }

    private var glyphForeground: Color {
        switch appState.status {
        case .recording:    return theme.deepGreen
        case .transcribing: return theme.coral
        case .copied:       return theme.actionBlue
        case .error:        return theme.error
        case .idle:         return theme.muted
        }
    }

    private var title: String {
        switch appState.status {
        case .recording:    return "Слушаю"
        case .transcribing: return "Преобразую речь"
        case .copied:       return "Текст готов"
        case .error:        return "Не получилось"
        case .idle:         return "MyWhi"
        }
    }

    private var subtitle: String {
        switch appState.status {
        case .transcribing: return "WhisperKit · \(appState.settings.modelSize)"
        case .copied:       return appState.settings.autoPaste ? "Вставлено в активное приложение" : "Скопировано в буфер · ⌘V"
        case .error:        return appState.errorMessage ?? "Проверь разрешения и попробуй снова"
        default:            return "⌘⌥D — начать запись"
        }
    }
}

private struct FloatingDurationView: View {
    private let startTime = Date()

    var body: some View {
        Text(timerInterval: startTime...Date.distantFuture, countsDown: false, showsHours: false)
            .font(HDFont.monoLabel(size: 12, weight: .medium))
            .foregroundStyle(HDColor.deepGreen)
            .monospacedDigit()
    }
}