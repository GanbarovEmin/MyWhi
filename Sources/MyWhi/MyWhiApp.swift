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
                .preferredColorScheme(container.appState.settings.useDarkMode ? .dark : nil)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            // Hide the default "New" menu item — we don't have documents.
            CommandGroup(replacing: .newItem) {}

            // Phase 5.2 — App-level menu commands that route through
            // the AppContainer so they work whether the desktop window
            // is open or the user is in another app and the menu bar
            // popover is the only MyWhi surface on screen.
            CommandMenu("Recording") {
                Button("Start / Stop") {
                    NotificationCenter.default.post(name: .mywhiToggleRecording, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .option])

                Button("Discard Current") {
                    NotificationCenter.default.post(name: .mywhiDiscardRecording, object: nil)
                }
                .keyboardShortcut(.escape, modifiers: [])

                Divider()

                Button("Open MyWhi") {
                    NotificationCenter.default.post(name: .mywhiOpenDesktop, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var floatingHUDPanel: NSPanel?
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
                self?.updateFloatingHUD(for: status)
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

    // MARK: - Floating HUD

    private func updateFloatingHUD(for status: AppStatus) {
        switch status {
        case .recording, .transcribing, .error:
            showFloatingHUD()
        case .copied:
            showFloatingHUD()
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                guard self?.appState.status == .copied else { return }
                self?.hideFloatingHUD()
            }
        case .idle:
            hideFloatingHUD()
        }
    }

    private func showFloatingHUD() {
        if floatingHUDPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 86),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = false
            panel.contentViewController = NSHostingController(
                rootView: FloatingVoiceHUDView()
                    .environmentObject(appState)
            )
            floatingHUDPanel = panel
        }

        positionFloatingHUD()
        floatingHUDPanel?.orderFrontRegardless()
    }

    private func hideFloatingHUD() {
        floatingHUDPanel?.orderOut(nil)
    }

    private func positionFloatingHUD() {
        guard let panel = floatingHUDPanel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let width: CGFloat = 380
        let height: CGFloat = 86
        let x = frame.midX - width / 2
        let y = frame.maxY - height - 24
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
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