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

    private init() {
        self.sceneRouter = AppSceneRouter.shared
        self.appState = AppState()
        // Bind the scene router to the app state so policy switches
        // can re-publish UI state if needed.
        self.appState.sceneRouter = sceneRouter
    }
}