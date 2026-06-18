// HotkeyCaptureSheet.swift
// Phase 6.3 — focused sheet that captures a new global hotkey.
// Uses NSEvent.addLocalMonitorForEvents to grab keyDown events
// system-wide while the sheet is open. On Save, the new chord is
// written to AppSettings and GlobalHotKey re-registers with the
// new values.
//
// Lifecycle:
//   - onAppear: install monitor
//   - onDisappear: remove monitor
// The monitor is stored as a property so we can clean it up reliably.

import SwiftUI
import AppKit
import Carbon.HIToolbox

struct HotkeyCaptureSheet: View {

    let initialModifiers: UInt32
    let initialKeyCode: UInt32
    let onSave: (UInt32, UInt32) -> Void   // (carbonMods, keyCode)
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var modifiers: UInt32
    @State private var keyCode: UInt32
    @State private var monitor: Any?
    @State private var hasChord: Bool

    init(
        initialModifiers: UInt32,
        initialKeyCode: UInt32,
        onSave: @escaping (UInt32, UInt32) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialModifiers = initialModifiers
        self.initialKeyCode = initialKeyCode
        self.onSave = onSave
        self.onCancel = onCancel
        // Start in a "press any key" state — clear the key code so
        // the user has to press something to enable Save.
        self._modifiers = State(initialValue: initialModifiers)
        self._keyCode = State(initialValue: 0)
        self._hasChord = State(initialValue: initialKeyCode != 0)
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Новый hotkey")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HDColor.ink)
                Text("Нажми любую комбинацию клавиш.\nEsc — отмена.")
                    .font(.system(size: 11))
                    .foregroundStyle(HDColor.muted)
                    .multilineTextAlignment(.center)
            }

            // Big chord display
            Text(displayString)
                .font(.system(size: 28, weight: .medium, design: .monospaced))
                .foregroundStyle(hasChord ? HDColor.ink : HDColor.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: HDRadius.md.rawValue, style: .continuous)
                        .fill(HDColor.softStone)
                )

            if hasChord {
                Button {
                    // Reset
                    keyCode = 0
                    hasChord = false
                } label: {
                    Label("Сбросить", systemImage: "arrow.uturn.left")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(HDColor.muted)
            }

            HStack(spacing: 12) {
                Button("Отмена") { onCancel(); dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Сохранить") {
                    onSave(modifiers, keyCode)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!hasChord)
            }
        }
        .padding(24)
        .frame(width: 360, height: 240)
        .background(HDColor.canvas)
        .onAppear { installMonitor() }
        .onDisappear { removeMonitor() }
    }

    // MARK: - Display

    private var displayString: String {
        if !hasChord {
            return formatModifiers(modifiers) + "  …"
        }
        return formatModifiers(modifiers) + " " + keyCodeToString(keyCode)
    }

    private func formatModifiers(_ mods: UInt32) -> String {
        var parts: [String] = []
        if mods & UInt32(controlKey) != 0 { parts.append("⌃") }
        if mods & UInt32(optionKey)  != 0 { parts.append("⌥") }
        if mods & UInt32(shiftKey)   != 0 { parts.append("⇧") }
        if mods & UInt32(cmdKey)     != 0 { parts.append("⌘") }
        return parts.joined()
    }

    private func keyCodeToString(_ code: UInt32) -> String {
        // Map common virtual key codes to display names. Anything we
        // don't know about is shown as a hex.
        switch code {
        case 0x00: return "A"
        case 0x01: return "S"
        case 0x02: return "D"
        case 0x03: return "F"
        case 0x04: return "H"
        case 0x05: return "G"
        case 0x06: return "Z"
        case 0x07: return "X"
        case 0x08: return "C"
        case 0x09: return "V"
        case 0x0B: return "B"
        case 0x0C: return "Q"
        case 0x0D: return "W"
        case 0x0E: return "E"
        case 0x0F: return "R"
        case 0x10: return "Y"
        case 0x11: return "T"
        case 0x1D: return "0"
        case 0x1E: return "1"
        case 0x1F: return "2"
        case 0x20: return "3"
        case 0x21: return "4"
        case 0x22: return "6"
        case 0x23: return "5"
        case 0x25: return "9"
        case 0x26: return "7"
        case 0x28: return "8"
        case 0x2A: return "—"
        case 0x2C: return "Space"
        case 0x7A: return "F1"
        case 0x78: return "F2"
        case 0x63: return "F3"
        case 0x76: return "F4"
        case 0x60: return "F5"
        case 0x61: return "F6"
        case 0x62: return "F7"
        case 0x64: return "F8"
        case 0x65: return "F9"
        case 0x6D: return "F10"
        case 0x67: return "F11"
        case 0x6F: return "F12"
        default:  return String(format: "0x%02X", code)
        }
    }

    // MARK: - Monitor

    private func installMonitor() {
        // Capture keyDown events globally. Returning nil consumes the
        // event so it doesn't trigger anything else (e.g. menu
        // shortcuts) while the sheet is open.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels.
            if event.keyCode == 53 {  // kVK_Escape
                self.onCancel()
                self.dismiss()
                return nil
            }

            // Skip if the user is hitting Enter/Return while focused
            // on a button (the Save / Cancel handlers will deal with
            // those). Actually we want to capture those too — they
            // become the new hotkey chord.
            let carbonMods = toCarbonFlags(event.modifierFlags)
            self.modifiers = carbonMods
            self.keyCode = UInt32(event.keyCode)
            self.hasChord = true
            return nil
        }
    }

    private func removeMonitor() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func toCarbonFlags(_ mods: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if mods.contains(.control) { carbon |= UInt32(controlKey) }
        if mods.contains(.option)  { carbon |= UInt32(optionKey) }
        if mods.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if mods.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }
}