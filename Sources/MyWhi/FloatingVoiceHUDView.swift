// FloatingVoiceHUDView.swift
// A compact Wispr Flow-like voice surface shown above the active app while
// MyWhi is listening, transcribing, or has just copied text.

import SwiftUI

struct FloatingVoiceHUDView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: HDSpacing.md.rawValue) {
            statusGlyph

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: HDSpacing.sm.rawValue) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundStyle(HDColor.ink)
                    if appState.status == .recording {
                        FloatingDurationView()
                    }
                }

                if appState.status == .recording {
                    HDWaveformView(
                        level: appState.recorderLevel,
                        style: .compact,
                        color: HDColor.deepGreen
                    )
                    .frame(width: 168)
                } else {
                    Text(subtitle)
                        .font(HDFont.micro)
                        .foregroundStyle(HDColor.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: HDSpacing.sm.rawValue)

            if appState.status == .recording {
                Button {
                    appState.discardRecording()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(HDColor.muted)
                .help("Отменить запись")

                Button {
                    appState.stopRecording()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(HDColor.onPrimary)
                        .background(Circle().fill(HDColor.primary))
                }
                .buttonStyle(.plain)
                .help("Остановить и транскрибировать")
            }
        }
        .padding(.horizontal, HDSpacing.lg.rawValue)
        .padding(.vertical, HDSpacing.md.rawValue)
        .frame(width: 380, height: 86)
        .background(
            RoundedRectangle(cornerRadius: HDRadius.xl.rawValue, style: .continuous)
                .fill(HDColor.canvas.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: HDRadius.xl.rawValue, style: .continuous)
                        .stroke(HDColor.borderLight, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.14), radius: 24, x: 0, y: 14)
        )
    }

    private var statusGlyph: some View {
        ZStack {
            Circle()
                .fill(glyphBackground)
                .frame(width: 42, height: 42)
            Image(systemName: appState.status.iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(glyphForeground)
        }
        .symbolEffect(.pulse, options: .repeating, isActive: appState.status == .recording)
    }

    private var glyphBackground: Color {
        switch appState.status {
        case .recording:    return HDColor.paleGreen
        case .transcribing: return HDColor.coralSoft.opacity(0.45)
        case .copied:       return HDColor.paleBlue
        case .error:        return HDColor.error.opacity(0.12)
        case .idle:         return HDColor.softStone
        }
    }

    private var glyphForeground: Color {
        switch appState.status {
        case .recording:    return HDColor.deepGreen
        case .transcribing: return HDColor.coral
        case .copied:       return HDColor.actionBlue
        case .error:        return HDColor.error
        case .idle:         return HDColor.muted
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
    @State private var startTime = Date()

    var body: some View {
        TimelineView(.periodic(from: startTime, by: 0.5)) { _ in
            let elapsed = Int(Date().timeIntervalSince(startTime))
            Text(formatDuration(elapsed))
                .font(HDFont.monoLabel(size: 12, weight: .medium))
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
