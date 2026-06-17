// AppSceneRouter.swift
// Manages the dual-scene architecture: menu bar (NSStatusItem) + desktop
// (WindowGroup). Switches NSApp.setActivationPolicy to control whether
// the Dock icon appears.
//
// Usage:
//   AppSceneRouter.shared.setMode(.menuBar)  // default: accessory, no Dock
//   AppSceneRouter.shared.setMode(.desktop)  // regular, Dock icon visible
//
// The router is a singleton because activation policy changes must
// happen from the main thread and there is exactly one NSApp instance.

import AppKit
import SwiftUI

enum AppSceneMode: Equatable {
    case menuBar
    case desktop
}

@MainActor
final class AppSceneRouter: ObservableObject {

    static let shared = AppSceneRouter()

    @Published private(set) var mode: AppSceneMode = .menuBar

    private init() {}

    /// Switch activation policy. Idempotent — calling with the current mode
    /// is a no-op. Always invoked on the main thread (callers are @MainActor).
    func setMode(_ newMode: AppSceneMode) {
        guard newMode != mode else { return }
        mode = newMode
        switch newMode {
        case .menuBar:
            NSApp.setActivationPolicy(.accessory)
        case .desktop:
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Convenience: switch to desktop and bring app forward.
    func openDesktop() {
        setMode(.desktop)
    }

    /// Convenience: switch back to menu bar only.
    func returnToMenuBar() {
        setMode(.menuBar)
    }
}