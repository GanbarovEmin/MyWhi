// MyWhiApp.swift
// Entry point. Three SwiftUI scenes + AppKit NSStatusItem:
//
//   - WindowGroup("MyWhi", id: "desktop")   → DesktopRootView (main shell)
//   - WindowGroup("Design Preview", id:)    → DesignSystemPreviewView
//   - SwiftUI.Settings                     → EmptyView (no Settings scene)
//
// AppContainer.shared exposes AppState + AppSceneRouter as a single
// ObservableObject injected via .environmentObject.

import SwiftUI
import AppKit
import Combine

@main
struct MyWhiApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var container = AppContainer.shared

    var body: some Scene {

        // --- Main desktop shell ---
        WindowGroup("MyWhi", id: "desktop") {
            DesktopRootView()
                .environmentObject(container)
                .environmentObject(container.appState)
                .environmentObject(container.appState.statsObserver)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            // Hide the default "New" menu item — we don't have documents.
            CommandGroup(replacing: .newItem) {}
        }

        // --- Design system preview (alpha dev tool) ---
        WindowGroup("Design Preview", id: "design-preview") {
            DesignPreviewWindow()
                .environmentObject(container)
        }
        .defaultSize(width: 820, height: 760)
        .windowResizability(.contentMinSize)

        // Settings scene — intentionally empty. The desktop app has
        // its own SettingsView in the sidebar; this exists only to keep
        // SwiftUI happy (it requires at least one Scene that isn't a
        // Settings scene, but this harmless empty Settings lets us be
        // defensive if macOS later opens one).
        SwiftUI.Settings { EmptyView() }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()

    private var container: AppContainer { AppContainer.shared }
    private var appState: AppState { container.appState }
    private var sceneRouter: AppSceneRouter { container.sceneRouter }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only by default — Dock icon appears once the desktop
        // window is opened (via AppSceneRouter.setMode(.desktop)).
        NSApp.setActivationPolicy(.accessory)

        // ---- Status item ----
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "mic",
                accessibilityDescription: "MyWhi"
            )
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // ---- Popover ----
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 540)
        popover.contentViewController = NSHostingController(
            rootView: MainPopoverView()
                .environmentObject(container)
                .environmentObject(appState)
        )

        // Re-render status icon whenever AppState.status changes.
        appState.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.refreshIcon(for: status)
            }
            .store(in: &cancellables)

        // When the router switches to .desktop, activate the app so the
        // Dock icon appears and windows come forward.
        sceneRouter.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                if mode == .desktop {
                    self?.handleDesktopActivation()
                }
            }
            .store(in: &cancellables)
    }

    private func handleDesktopActivation() {
        // NSApp already set policy via AppSceneRouter; just make sure
        // something is brought to the foreground.
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Popover

    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        let event = NSApp.currentEvent

        if popover.isShown {
            popover.performClose(sender)
            return
        }

        // Right-click → context menu. Left-click → popover.
        if event?.type == .rightMouseUp {
            showContextMenu(from: button)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "About MyWhi", action: #selector(about), keyEquivalent: "")
        menu.addItem(withTitle: "Open MyWhi", action: #selector(openDesktop), keyEquivalent: "")
        menu.addItem(withTitle: "Open Design Preview", action: #selector(openDesignPreview), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MyWhi", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func about() {
        let alert = NSAlert()
        alert.messageText = "MyWhi"
        let model = MainActor.assumeIsolated { appState.settings.modelSize }
        let lang = MainActor.assumeIsolated { appState.settings.language }
        let engine = MainActor.assumeIsolated { appState.activeEngineName }
        alert.informativeText = """
        Local-only voice dictation for macOS.
        Engine: \(engine)

        Model: \(model)
        Language: \(lang)
        """
        alert.runModal()
    }

    @objc private func openDesktop() {
        NotificationCenter.default.post(name: .mywhiOpenDesktop, object: nil)
    }

    @objc private func openDesignPreview() {
        NotificationCenter.default.post(name: .mywhiOpenDesignPreview, object: nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Icon refresh

    private func refreshIcon(for status: AppStatus) {
        guard let button = statusItem.button else { return }
        let symbolName = status.iconName
        guard let img = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "MyWhi — \(status.rawValue)"
        ) else { return }
        img.isTemplate = true
        button.image = img
    }
}