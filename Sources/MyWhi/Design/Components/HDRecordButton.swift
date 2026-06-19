// HDRecordButton.swift
// The hero control. Three states mirror the recording flow:
//
//   .idle         — outlined circle, mic icon
//   .recording    — filled deep-green, mic.fill, subtle pulse animation
//   .transcribing — filled coral, animated spinner
//
// Two sizes: compact (48px, menu bar) and hero (88px, desktop Home view).
//
// Phase 7: HDTheme-aware. Colors come from the current theme so dark
// mode renders correctly. Focus ring for keyboard navigation.

import SwiftUI

enum HDRecordState {
    case idle
    case recording
    case transcribing
}

struct HDRecordButton: View {
    @Environment(\.hdTheme) private var theme
    @FocusState private var isFocused: Bool

    let state: HDRecordState
    var size: CGFloat = 88
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var pulseScale: CGFloat = 1.0

    private var iconName: String {
        switch state {
        case .idle:         return "mic"
        case .recording:    return "mic.fill"
        case .transcribing: return "waveform"
        }
    }

    private var fillColor: Color {
        switch state {
        case .idle:         return theme.canvas
        case .recording:    return theme.deepGreen
        case .transcribing: return theme.coral
        }
    }

    private var iconColor: Color {
        switch state {
        case .idle:         return theme.primary
        case .recording:    return theme.onDark
        case .transcribing: return theme.onPrimary
        }
    }

    private var borderColor: Color {
        switch state {
        case .idle:         return theme.primary
        case .recording:    return theme.deepGreen
        case .transcribing: return theme.coral
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if state == .recording {
                    // Pulse halo
                    Circle()
                        .fill(theme.deepGreen.opacity(0.18))
                        .frame(width: size * 1.45, height: size * 1.45)
                        .scaleEffect(pulseScale)
                        .opacity(2.0 - pulseScale)
                }

                Circle()
                    .fill(fillColor)
                    .frame(width: size, height: size)
                    .overlay(
                        Circle()
                            .stroke(borderColor, lineWidth: state == .idle ? 1.5 : 0)
                    )
                    .overlay(
                        Circle()
                            .stroke(isFocused ? theme.focusBlue : Color.clear, lineWidth: 2)
                            .frame(width: size + 6, height: size + 6)
                    )

                if state == .transcribing {
                    // Spinner-ish: rotating arc
                    Circle()
                        .trim(from: 0.0, to: 0.7)
                        .stroke(theme.onPrimary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: size * 0.45, height: size * 0.45)
                        .rotationEffect(.degrees(pulseScale * 360))
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: size * 0.4, weight: .medium))
                        .foregroundStyle(iconColor)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || state == .transcribing)
        .focused($isFocused)
        .onChange(of: state) { _, newState in
            if newState == .recording {
                startPulse()
            } else {
                stopPulse()
            }
        }
        .onAppear {
            if state == .recording {
                startPulse()
            }
        }
    }

    private func startPulse() {
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) {
            pulseScale = 1.6
        }
    }

    private func stopPulse() {
        withAnimation(.easeOut(duration: 0.3)) {
            pulseScale = 1.0
        }
    }
}