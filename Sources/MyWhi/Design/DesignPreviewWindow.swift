// DesignPreviewWindow.swift
// WindowGroup content for the design system preview. Listens for
// AppDelegate's "Open Design Preview" notification (posted from the
// menu bar right-click menu) and invokes SwiftUI's openWindow to
// show the catalog.

import SwiftUI

struct DesignPreviewWindow: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        DesignSystemPreviewView()
            .onReceive(NotificationCenter.default.publisher(for: .mywhiOpenDesignPreview)) { _ in
                openWindow(id: "design-preview")
            }
    }
}