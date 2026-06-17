// MyWhiApp.swift
// Entry point. NSStatusItem via AppDelegate (macOS 26 safe), with
// AppSceneRouter managing activation policy for the optional desktop
// window (added in Phase 3).

import SwiftUI
import AppKit
import Combine

@main
struct MyWhiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // SwiftUI requires at least one Scene. SwiftUI.Settings with EmptyView
    // never opens a window — the menu bar UI lives in the NSStatusItem
    // popover. The desktop WindowGroup is added in Phase 3.
    var body: some Scene {
        SwiftUI.Settings { EmptyView() }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var appState: AppState!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only — no Dock icon.
        NSApp.setActivationPolicy(.accessory)

        // Single source of truth, shared with the popover's SwiftUI host.
        appState = AppState()

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
            rootView: MainPopoverView().environmentObject(appState)
        )

        // Re-render status icon whenever AppState.status changes.
        appState.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.refreshIcon(for: status)
            }
            .store(in: &cancellables)
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
        alert.informativeText = """
        Local-only voice dictation for macOS.
        Powered by WhisperKit (on-device) with faster-whisper fallback.

        Model: \(model)
        Language: \(lang)
        """
        alert.runModal()
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
