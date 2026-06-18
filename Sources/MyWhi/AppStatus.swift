// AppStatus.swift
// Discrete state machine for the menu bar app.
//
// Color tokens come from HDColor so the menu bar / popover / desktop
// visuals stay consistent. The previous version used system .red /
// .green which clashed with the brand palette. See audit #7.

import SwiftUI

enum AppStatus: String {
    case idle          = "Idle"
    case recording     = "Recording"
    case transcribing  = "Transcribing"
    case copied        = "Copied to clipboard"
    case error         = "Error"

    /// SF Symbol used in the menu bar and popover header.
    var iconName: String {
        switch self {
        case .idle:         return "mic"
        case .recording:    return "record.circle.fill"
        case .transcribing: return "waveform"
        case .copied:       return "checkmark.circle.fill"
        case .error:        return "exclamationmark.triangle.fill"
        }
    }

    /// Brand-consistent status color (HDColor tokens).
    var color: Color {
        switch self {
        case .idle:         return HDColor.muted
        case .recording:    return HDColor.deepGreen
        case .transcribing: return HDColor.coral
        case .copied:       return HDColor.actionBlue
        case .error:        return HDColor.error
        }
    }
}
