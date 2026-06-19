// HapticFeedback.swift
// Thin wrapper over NSHapticFeedbackManager. Triggered at key
// moments: recording start, transcription finish, error.
//
// No-op on Macs that don't have a force-touch trackpad — the API
// silently degrades.

import AppKit

enum HapticFeedback {
    case success
    case warning
    case error

    func fire() {
        let time: NSHapticFeedbackManager.PerformanceTime = .now

        // Map our semantics onto the available API surface.
        switch self {
        case .success:
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: time)
        case .warning:
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: time)
        case .error:
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: time)
        }
    }
}