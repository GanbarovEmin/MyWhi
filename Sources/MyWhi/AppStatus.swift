// AppStatus.swift
// Discrete state machine for the menu bar app.

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

    var color: Color {
        switch self {
        case .idle:         return .secondary
        case .recording:    return .red
        case .transcribing: return .orange
        case .copied:       return .green
        case .error:        return .red
        }
    }
}
