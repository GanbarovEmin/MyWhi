// AppContainer.swift
// Single source of truth for SwiftUI scene access. AppDelegate owns the
// concrete instance; scenes read it via @EnvironmentObject after MyWhiApp
// injects it at the WindowGroup root.
//
// Singleton because we have exactly one app instance, exactly one NSApp,
// and SwiftUI scenes + AppKit delegate both need access to the same
// AppState (for state) and AppSceneRouter (for policy).

import SwiftUI

@MainActor
final class AppContainer: ObservableObject {

    static let shared = AppContainer()

    let appState: AppState
    let sceneRouter: AppSceneRouter
    let globalHotKey: GlobalHotKey

    private init() {
        self.sceneRouter = AppSceneRouter.shared
        self.appState = AppState()
        self.appState.sceneRouter = sceneRouter

        self.globalHotKey = GlobalHotKey()

        // App-menu commands (Phase 5.2) — observers are stored so they
        // don't get deallocated. We forward to the same handlers the
        // global hotkey and the menu bar popover use.
        NotificationCenter.default.addObserver(
            forName: .mywhiToggleRecording,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.appState.toggleRecording()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .mywhiDiscardRecording,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.appState.discardRecording()
            }
        }

        // Wire hot key → toggle recording. We re-register with the
        // current default chord; users can change it later.
        NotificationCenter.default.addObserver(
            forName: .mywhiHotKeyPressed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.appState.toggleRecording()
            }
        }
        globalHotKey.register { [weak self] in
            Task { @MainActor [weak self] in
                self?.appState.toggleRecording()
            }
        }
    }
}