// HDStatTile.swift
// Big-number stat display. Used on the Insights hero band.
// Matches the editorial "Cohere product-display" feel — large tight type
// against either a dark or light surface.
//
// Phase 7: HDTheme-aware.
//
// Example:
//   HDStatTile(label: "Total words", value: "12 482", surface: .dark)
//   HDStatTile(label: "Current streak", value: "7 days", surface: .light)

import SwiftUI

enum HDStatSurface {
    case light  // for use on canvas/stone surfaces
    case dark   // for use on deep-green band
}

struct HDStatTile: View {
    @Environment(\.hdTheme) private var theme

    let label: String
    let value: String
    var delta: String? = nil         // e.g. "+12% this week"
    var surface: HDStatSurface = .light

    private var labelColor: Color {
        surface == .dark ? theme.onDark.opacity(0.7) : theme.muted
    }

    private var valueColor: Color {
        surface == .dark ? theme.onDark : theme.ink
    }

    private var deltaColor: Color {
        theme.coral
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HDSpacing.sm.rawValue) {
            Text(label.uppercased())
                .font(HDFont.monoLabel(size: 12))
                .hdTracking(0.5)
                .foregroundStyle(labelColor)

            Text(value)
                .font(HDFont.cardHeading)
                .hdTracking(-0.32)
                .foregroundStyle(valueColor)

            if let delta {
                HStack(spacing: HDSpacing.xs.rawValue) {
                    Image(systemName: "arrow.up.right")
                        .font(HDFont.statDeltaIcon)
                    Text(delta)
                        .font(HDFont.statDelta)
                }
                .foregroundStyle(deltaColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HDSpacing.lg.rawValue)
    }
}