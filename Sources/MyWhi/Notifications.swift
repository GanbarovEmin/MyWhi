// Notifications.swift
// App-wide Notification.Name values for cross-layer communication.
//
// AppDelegate (AppKit) posts these via NotificationCenter; SwiftUI scenes
// subscribe via .onReceive and act on them. This is the simplest bridge
// between AppKit actions (NSMenu items, NSStatusItem button targets) and
// SwiftUI scenes (WindowGroup with id:) without coupling them.

import Foundation

extension Notification.Name {
    /// Posted by AppDelegate when the user picks "Open Design Preview"
    /// from the right-click menu. The DesignPreviewWindow listens and
    /// invokes openWindow(id: "design-preview").
    static let mywhiOpenDesignPreview = Notification.Name("MyWhi.openDesignPreview")

    /// Posted by AppDelegate when the user picks "Open MyWhi" from the
    /// menu bar right-click menu. The DesktopRootView listens, switches
    /// the AppSceneRouter to .desktop, and invokes openWindow(id: "desktop").
    static let mywhiOpenDesktop = Notification.Name("MyWhi.openDesktop")

    /// Posted by AppDelegate when the user picks "Open MyWhi" from the
    /// menu bar right-click menu. The DesktopRootView listens, switches
    /// the AppSceneRouter to .desktop, and invokes openWindow(id: "desktop").
    static let mywhiNavigateToScratchpad = Notification.Name("MyWhi.navigateToScratchpad")

    /// Phase 5.2 — App menu commands.
    /// Cmd+Option+D from any focus context (no menu bar popover open).
    static let mywhiToggleRecording = Notification.Name("MyWhi.toggleRecording")
    static let mywhiDiscardRecording = Notification.Name("MyWhi.discardRecording")

    /// Phase 6.3 — Posted by Settings when the user saves a new
    /// hotkey chord. AppContainer re-registers GlobalHotKey with
    /// the new values. userInfo: ["modifiers": UInt32, "keyCode": UInt32]
    static let mywhiHotkeyChanged = Notification.Name("MyWhi.hotkeyChanged")
}