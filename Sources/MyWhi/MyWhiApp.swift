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
            HDThemeRoot {
                DesktopRootView()
                    .environmentObject(container)
                    .environmentObject(container.appState)
                    .environmentObject(container.appState.statsObserver)
                    .preferredColorScheme(container.appState.settings.useDarkMode ? .dark : nil)
                    .frame(minWidth: 900, minHeight: 600)
            }
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
            HDThemeRoot {
                DesignPreviewWindow()
                    .environmentObject(container)
            }
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
            rootView: HDThemeRoot {
                MainPopoverView()
                    .environmentObject(self.container)
                    .environmentObject(self.appState)
            }
        )

        // Re-render status icon whenever AppState.status changes.
        appState.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.refreshIcon(for: status)
                self?.updateFloatingHUD(for: status)
                // Phase 18: surface the recording state on the Dock
                // tile so users with MyWhi in the Dock can see the
                // state at a glance — even when the popover/HUD are
                // hidden behind another app. The dockTile only renders
                // when the app is in .regular activation policy
                // (desktop mode); in .accessory mode there's no tile
                // to badge, which is the correct behavior.
                self?.refreshDockBadge(for: status)
            }
            .store(in: &cancellables)

        // Phase 15: reposition the HUD when the user toggles
        // hudPosition in Settings.
        appState.settings.$hudPosition
            .receive(on: RunLoop.main)
            .dropFirst()  // skip initial value (HUD already positioned)
            .sink { [weak self] _ in
                self?.positionFloatingHUD()
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

        // Phase 20: surface errors via a small floating toast. We do
        // this at the AppDelegate level (not in any view) so the toast
        // appears even when the menu-bar popover is closed. We skip
        // empty / cleared messages and only show non-empty ones.
        appState.$errorMessage
            .receive(on: RunLoop.main)
            .removeDuplicates()
            .sink { message in
                let trimmed = (message ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    ErrorToastController.shared.show(trimmed)
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

        // Phase 20: Recent transcripts submenu. Power-user shortcut for
        // re-copying something from a few minutes ago without opening
        // the desktop app. We rebuild the submenu on every right-click
        // so it reflects the latest `statsObserver.notes`.
        let recent = NSMenuItem()
        recent.title = "Recent transcripts"
        recent.submenu = buildRecentTranscriptsMenu()
        // Disabled title-like item — submenu doesn't show on its own.
        if recent.submenu?.items.isEmpty == true {
            recent.isEnabled = false
        }
        menu.addItem(recent)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MyWhi", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    /// Build the "Recent transcripts" submenu with the 5 most recent
    /// notes. Click → copy + close menu. We rebuild on every right-click
    /// so the list is always fresh.
    private func buildRecentTranscriptsMenu() -> NSMenu {
        let submenu = NSMenu()
        let notes = MainActor.assumeIsolated { appState.statsObserver.notes }
        if notes.isEmpty {
            let empty = NSMenuItem(title: "Нет записей", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
            return submenu
        }
        for note in notes.prefix(5) {
            let prefix = note.title.prefix(40)
            let title = prefix.count < note.title.count
                ? "\(prefix)…"
                : String(prefix)
            let item = NSMenuItem(
                title: title,
                action: #selector(copyRecentTranscript(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = note.body
            submenu.addItem(item)
        }
        return submenu
    }

    @objc private func copyRecentTranscript(_ sender: NSMenuItem) {
        guard let body = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(body, forType: .string)
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
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 86),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            // Phase 21: default to .floating. When we're actively
            // recording we bump to .statusBar so the HUD stays above
            // any other floating window the user might have open
            // (system popovers, third-party HUDs, etc.). For all
            // other states (transcribing, copied, error) we leave it
            // at .floating — being intrusive there would be annoying.
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = false
            panel.contentViewController = NSHostingController(
                rootView: HDThemeRoot {
                    FloatingVoiceHUDView()
                        .environmentObject(self.appState)
                }
            )
            floatingHUDPanel = panel
        }

        // Phase 21: dynamic level boost. Recording is the one state
        // where the user explicitly needs confirmation that audio is
        // being captured — make sure they always see the HUD.
        if let panel = floatingHUDPanel {
            switch appState.status {
            case .recording:
                panel.level = .statusBar
            default:
                panel.level = .floating
            }
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
        let width: CGFloat = 420
        let height: CGFloat = 86
        let x = frame.midX - width / 2
        // Phase 15: respect hudPosition setting. Wispr Flow convention
        // is bottom (close to where the text lands). MyWhi legacy
        // default is top. We pin to a small inset so the panel
        // doesn't crowd the screen edge.
        let yInset: CGFloat = 24
        let y: CGFloat
        switch appState.settings.hudPosition {
        case .top:
            y = frame.maxY - height - yInset
        case .bottom:
            y = frame.minY + yInset
        }
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

    // MARK: - Dock badge (Phase 18)

    /// Update the Dock tile's badge label to reflect the current
    /// recording state. The Dock tile is only visible when MyWhi is
    /// in `.regular` activation policy (desktop mode), so this is a
    /// no-op in `.accessory` mode.
    private func refreshDockBadge(for status: AppStatus) {
        switch status {
        case .recording, .transcribing:
            // Use a red dot — universally recognized as "live" /
            // "active". String is short to fit on the Dock tile.
            NSApp.dockTile.badgeLabel = "●"
        case .error:
            NSApp.dockTile.badgeLabel = "!"
        default:
            NSApp.dockTile.badgeLabel = nil
        }
        NSApp.dockTile.display()
    }
}