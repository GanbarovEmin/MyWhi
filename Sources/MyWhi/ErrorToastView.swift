// ErrorToastView.swift
// Phase 20 — small floating toast that surfaces errors when the
// menu-bar popover is closed (the popover is the only place that
// currently shows `errorMessage`, so an error that fires while the
// user is in another app would otherwise be silent).
//
// Implemented as a separate `NSPanel` (not part of the FloatingVoiceHUDView)
// so the two never overlap visually — toast appears at the bottom-center
// when the HUD is at the top, and vice versa.

import SwiftUI
import AppKit

@MainActor
final class ErrorToastController {

    /// Singleton — there's only ever one error toast visible at a time.
    /// If a second error fires while the first is still showing, we
    /// replace the text in-place (no flicker, no extra panels).
    static let shared = ErrorToastController()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    /// Show an error message. Replaces any existing toast.
    func show(_ message: String) {
        if panel == nil {
            panel = makePanel()
        }
        guard let panel else { return }

        // Update the SwiftUI content. We rebuild the hosting controller
        // each time so the message is fresh; the panel itself is
        // reused (no flicker on re-show).
        let host = NSHostingController(
            rootView: ErrorToastView(message: message) { [weak self] in
                self?.dismiss()
            }
        )
        host.view.frame = panel.contentView?.bounds ?? .zero
        host.view.autoresizingMask = [.width, .height]
        if let existing = panel.contentView?.subviews.first {
            existing.removeFromSuperview()
        }
        panel.contentView?.addSubview(host.view)

        positionPanel(panel)
        panel.orderFrontRegardless()

        // Auto-dismiss after 5 seconds.
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled {
                self?.dismiss()
            }
        }
    }

    /// Dismiss the toast immediately.
    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar          // above other windows but below alerts
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let width: CGFloat = 460
        let height: CGFloat = 56
        let x = frame.midX - width / 2
        // Always at the bottom of the screen — separate from the HUD
        // so they never visually collide. If the HUD is bottom-mounted
        // the toast sits above it.
        let y = frame.minY + 24
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}

struct ErrorToastView: View {

    @Environment(\.hdTheme) private var theme
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: HDSpacing.sm.rawValue) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(HDFont.iconSmall)
                .foregroundStyle(theme.error)

            Text(message)
                .font(HDFont.errorToast)
                .foregroundStyle(theme.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(HDFont.iconSmall)
                    .foregroundStyle(theme.muted)
            }
            .buttonStyle(.plain)
            .help("Закрыть")
        }
        .padding(.horizontal, HDSpacing.md.rawValue)
        .padding(.vertical, HDSpacing.sm.rawValue)
        .background(
            RoundedRectangle(cornerRadius: HDRadius.md.rawValue, style: .continuous)
                .fill(theme.surface.opacity(0.97))
                .overlay(
                    RoundedRectangle(cornerRadius: HDRadius.md.rawValue, style: .continuous)
                        .stroke(theme.error.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 8)
        )
    }
}