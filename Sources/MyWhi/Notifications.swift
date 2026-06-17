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
}