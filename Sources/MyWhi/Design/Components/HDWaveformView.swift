// HDWaveformView.swift
// Live audio waveform — reads `currentLevel` from AudioRecorder and
// renders a horizontal bar of N segments whose height pulses with
// amplitude. Each segment has a slight decay so the wave "trails off"
// instead of jumping back to zero between samples.
//
// Two display modes:
//   - .compact  — narrow (used in the menu bar popover header)
//   - .hero     — wide  (used in the desktop Home view)
//
// Animation strategy: TimelineView polls at the device's refresh rate
// (no fixed Hz, no timer). Each segment's height is computed as a
// function of (level, time, segmentIndex) with a per-segment phase
// offset so the wave looks organic, not synchronized.

import SwiftUI

enum HDWaveformStyle {
    case compact
    case hero
}

struct HDWaveformView: View {

    let level: Float
    var style: HDWaveformStyle = .compact
    var color: Color = HDColor.deepGreen

    private var barCount: Int {
        switch style {
        case .compact: return 12
        case .hero:    return 32
        }
    }

    private var segmentWidth: CGFloat {
        switch style {
        case .compact: return 2.5
        case .hero:    return 4.0
        }
    }

    private var segmentSpacing: CGFloat {
        switch style {
        case .compact: return 2
        case .hero:    return 3
        }
    }

    private var minHeight: CGFloat {
        switch style {
        case .compact: return 2
        case .hero:    return 3
        }
    }

    private var maxHeight: CGFloat {
        switch style {
        case .compact: return 18
        case .hero:    return 44
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            Canvas { ctx, size in
                let totalWidth = CGFloat(barCount) * (segmentWidth + segmentSpacing) - segmentSpacing
                let originX = (size.width - totalWidth) / 2
                let centerY = size.height / 2
                let level01 = Double(max(0, min(1, level)))

                for i in 0..<barCount {
                    // Each segment oscillates with its own phase, multiplied
                    // by the live level. Phase is in radians.
                    let phase = Double(i) * 0.45 + context.date.timeIntervalSinceReferenceDate * 3
                    let oscillation = (sin(phase) + 1) / 2   // 0...1
                    let amplitude = oscillation * level01 + (1 - level01) * 0.05
                    let h = max(minHeight, CGFloat(amplitude) * maxHeight)
                    let x = originX + CGFloat(i) * (segmentWidth + segmentSpacing)
                    let rect = CGRect(
                        x: x,
                        y: centerY - h / 2,
                        width: segmentWidth,
                        height: h
                    )
                    let bar = Path(roundedRect: rect, cornerRadius: segmentWidth / 2)
                    ctx.fill(bar, with: .color(color))
                }
            }
        }
        .frame(height: maxHeight + 4)  // a little extra for vertical breathing
        .animation(.easeOut(duration: 0.1), value: level)
    }
}

#Preview {
    VStack(spacing: 20) {
        HDWaveformView(level: 0.0, style: .compact)
        HDWaveformView(level: 0.3, style: .compact)
        HDWaveformView(level: 0.7, style: .compact)
        HDWaveformView(level: 1.0, style: .compact)
        HDWaveformView(level: 0.5, style: .hero, color: HDColor.coral)
    }
    .padding()
    .background(HDColor.canvas)
}