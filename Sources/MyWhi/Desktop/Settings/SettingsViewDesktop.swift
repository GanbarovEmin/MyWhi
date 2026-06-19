// SettingsViewDesktop.swift
// Settings pane inside the desktop sidebar. Covers engine, model,
// language, behavior toggles, storage info, and Obsidian integration.
//
// Phase 7: HDTheme migration, hardcoded fonts → HDFont tokens.
//   Performance: removed redundant MainActor.run hop in refreshStorage().

import SwiftUI
import AppKit
import Carbon.HIToolbox

struct SettingsViewDesktop: View {

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var statsObserver: StatsObserver
    @Environment(\.hdTheme) private var theme

    @State private var vaultSize: Int64 = 0
    @State private var obsidianStatus: ObsidianStatus = .unknown
    @State private var showingHotkeySheet: Bool = false

    enum ObsidianStatus {
        case unknown
        case installed(URL)
        case notInstalled
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HDSpacing.xxl.rawValue) {
                header
                engineSection
                behaviorSection
                storageSection
                aboutSection
            }
            .padding(HDSpacing.xxl.rawValue)
            .frame(maxWidth: 720)
        }
        .background(theme.canvas)
        .task {
            await refreshStorage()
            obsidianStatus = detectObsidian()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: HDSpacing.xs.rawValue) {
            Text("НАСТРОЙКИ")
                .font(HDFont.monoLabel(size: 12))
                .hdTracking(0.5)
                .foregroundStyle(theme.muted)
            Text("Как MyWhi работает")
                .font(HDFont.cardHeading)
                .hdTracking(-0.32)
                .foregroundStyle(theme.ink)
        }
    }

    // MARK: - Engine

    private var engineSection: some View {
        HDCard(.canvas) {
            VStack(alignment: .leading, spacing: HDSpacing.lg.rawValue) {
                sectionTitle("Модель")

                HStack {
                    Text("Движок")
                        .font(HDFont.formLabel)
                        .foregroundStyle(theme.ink)
                    Spacer()
                    Text("WhisperKit")
                        .font(HDFont.monoLabel(size: 12, weight: .medium))
                        .padding(.horizontal, HDSpacing.sm.rawValue)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(theme.surfacePaleGreen)
                        )
                        .foregroundStyle(theme.deepGreen)
                }

                Picker("Model", selection: modelBinding) {
                    ForEach(AppSettings.availableModels, id: \.code) { entry in
                        Text(entry.label).tag(entry.code)
                    }
                }
                .pickerStyle(.menu)
                .disabled(appState.engineManager.isLoading)
                .onChange(of: appState.settings.modelSize) { _, _ in
                    Task { await appState.reloadEngine() }
                }

                if let entry = AppSettings.availableModels.first(where: { $0.code == appState.settings.modelSize }) {
                    Text(entry.description)
                        .font(HDFont.micro)
                        .foregroundStyle(theme.muted)
                }

                Picker("Language", selection: languageBinding) {
                    ForEach(AppSettings.availableLanguages, id: \.code) { lang in
                        Text(lang.label).tag(lang.code)
                    }
                }
                .pickerStyle(.segmented)

                if appState.engineManager.isLoading {
                    HStack(spacing: HDSpacing.sm.rawValue) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Загружается \(appState.settings.modelSize)…")
                            .font(HDFont.caption)
                            .foregroundStyle(theme.muted)
                    }
                    .padding(.vertical, HDSpacing.xs.rawValue)
                }
            }
        }
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { appState.settings.modelSize },
            set: { appState.settings.modelSize = $0 }
        )
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { appState.settings.language },
            set: { appState.settings.language = $0 }
        )
    }

    // MARK: Behavior

    private var behaviorSection: some View {
        HDCard(.canvas) {
            VStack(alignment: .leading, spacing: HDSpacing.md.rawValue) {
                sectionTitle("Поведение")

                Toggle("Копировать в буфер после записи", isOn: autoCopyBinding)
                Toggle("Сохранять в vault", isOn: saveHistoryBinding)
                Toggle("Авто-вставка в активное приложение (Cmd+V)", isOn: autoPasteBinding)
                    .help("Phase 6.2: требует Accessibility permission")

                Divider()
                    .padding(.vertical, HDSpacing.xs.rawValue)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Глобальный hotkey")
                            .font(HDFont.formLabel)
                            .foregroundStyle(theme.ink)
                        Text("Работает из любого приложения")
                            .font(HDFont.caption)
                            .foregroundStyle(theme.muted)
                    }
                    Spacer()
                    Text(hotkeyDisplay)
                        .font(HDFont.monoLabel(size: 14, weight: .medium))
                        .padding(.horizontal, HDSpacing.md.rawValue)
                        .padding(.vertical, HDSpacing.xs.rawValue)
                        .background(
                            RoundedRectangle(cornerRadius: HDRadius.xs.rawValue, style: .continuous)
                                .fill(theme.surfaceStone)
                        )
                        .foregroundStyle(theme.ink)
                    Button("Изменить…") {
                        showingHotkeySheet = true
                    }
                    .buttonStyle(.borderless)
                }
                .sheet(isPresented: $showingHotkeySheet) {
                    HotkeyCaptureSheet(
                        initialModifiers: appState.settings.hotkeyModifiers,
                        initialKeyCode: appState.settings.hotkeyKeyCode,
                        onSave: { mods, key in
                            appState.settings.hotkeyModifiers = mods
                            appState.settings.hotkeyKeyCode = key
                            NotificationCenter.default.post(
                                name: .mywhiHotkeyChanged,
                                object: nil,
                                userInfo: ["modifiers": mods, "keyCode": key]
                            )
                        },
                        onCancel: {}
                    )
                }

                if appState.settings.autoPaste {
                    HStack(spacing: HDSpacing.sm.rawValue) {
                        if AutoPasteService.isAccessibilityGranted() {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(theme.deepGreen)
                            Text("Accessibility permission выдана")
                                .font(HDFont.caption)
                                .foregroundStyle(theme.muted)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(theme.coral)
                            Text("Нужно разрешение Accessibility в Системных настройках")
                                .font(HDFont.caption)
                                .foregroundStyle(theme.coral)
                        }
                        Spacer()
                        HDButtonSecondary(title: "Открыть настройки") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }

                Divider()

                Toggle("Тёмная тема (override system)", isOn: darkModeBinding)
                    .help("Принудительно включить тёмную тему независимо от системных настроек macOS")

                // Phase 8 / 9 — surface the new toggles in Settings so
                // users can opt out of features that aren't for them.
                Divider()

                Toggle("Показывать текст во время записи (live streaming)", isOn: liveStreamingBinding)
                    .help("Слова появляются по мере того, как ты говоришь. Требует больше CPU.")

                Toggle("Звуковой сигнал старт/стоп", isOn: soundFeedbackBinding)
                    .help("Мягкий chime при начале и конце записи.")

                Divider()

                Toggle("Редактировать перед вставкой", isOn: inlineEditorBinding)
                    .help("После транскрибации показывать редактор вместо авто-копирования. Нажми «Вставить» чтобы скопировать отредактированный текст.")

                Toggle("Push-to-talk (hold-to-record)", isOn: pushToTalkBinding)
                    .help("Удерживай горячую клавишу чтобы записать, отпусти чтобы остановить. По умолчанию — toggle.")

                HStack(spacing: HDSpacing.sm.rawValue) {
                    Text("Окно live-декода:")
                        .font(HDFont.formLabel)
                        .foregroundStyle(theme.ink)
                    Picker("", selection: liveWindowBinding) {
                        Text("4 сек").tag(4)
                        Text("6 сек").tag(6)
                        Text("8 сек (стандарт)").tag(8)
                        Text("12 сек").tag(12)
                        Text("20 сек").tag(20)
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220)
                    Spacer()
                }
                .help("Сколько секунд последнего аудио декодировать в каждом live-тике. Меньше — отзывчивее, больше — стабильнее.")

                HStack(spacing: HDSpacing.sm.rawValue) {
                    Text("Позиция floating HUD:")
                        .font(HDFont.formLabel)
                        .foregroundStyle(theme.ink)
                    Picker("", selection: hudPositionBinding) {
                        Text("Сверху (по умолчанию)").tag(AppSettings.HUDPosition.top)
                        Text("Снизу (Wispr Flow)").tag(AppSettings.HUDPosition.bottom)
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 240)
                    Spacer()
                }
                .help("Где показывать плавающее окно во время записи.")
            }
        }
    }

    private var darkModeBinding: Binding<Bool> {
        Binding(get: { appState.settings.useDarkMode }, set: { appState.settings.useDarkMode = $0 })
    }

    private var liveStreamingBinding: Binding<Bool> {
        Binding(get: { appState.settings.liveStreamingEnabled },
                set: { appState.settings.liveStreamingEnabled = $0 })
    }

    private var soundFeedbackBinding: Binding<Bool> {
        Binding(get: { appState.settings.soundFeedbackEnabled },
                set: { appState.settings.soundFeedbackEnabled = $0 })
    }

    private var inlineEditorBinding: Binding<Bool> {
        Binding(get: { appState.settings.inlineEditorMode },
                set: { appState.settings.inlineEditorMode = $0 })
    }

    private var pushToTalkBinding: Binding<Bool> {
        Binding(get: { appState.settings.pushToTalkMode },
                set: { appState.settings.pushToTalkMode = $0 })
    }

    private var liveWindowBinding: Binding<Int> {
        Binding(
            get: { appState.settings.liveWindowSeconds },
            set: { appState.settings.liveWindowSeconds = $0 }
        )
    }

    private var hudPositionBinding: Binding<AppSettings.HUDPosition> {
        Binding(
            get: { appState.settings.hudPosition },
            set: { appState.settings.hudPosition = $0 }
        )
    }

    private var hotkeyDisplay: String {
        let mods = appState.settings.hotkeyModifiers
        var parts: [String] = []
        if mods & UInt32(controlKey) != 0 { parts.append("⌃") }
        if mods & UInt32(optionKey)  != 0 { parts.append("⌥") }
        if mods & UInt32(shiftKey)   != 0 { parts.append("⇧") }
        if mods & UInt32(cmdKey)     != 0 { parts.append("⌘") }
        let modStr = parts.joined()

        let key = keyCodeToDisplay(appState.settings.hotkeyKeyCode)
        return modStr.isEmpty ? key : "\(modStr)\(key)"
    }

    private func keyCodeToDisplay(_ code: UInt32) -> String {
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
        case 0x1D...0x2A: return String(["0","1","2","3","4","5","6","7","8","9"][Int(code) - 0x1D])
        case 0x2C: return "Space"
        default:  return String(format: "0x%02X", code)
        }
    }

    private var autoCopyBinding: Binding<Bool> {
        Binding(get: { appState.settings.autoCopy }, set: { appState.settings.autoCopy = $0 })
    }
    private var saveHistoryBinding: Binding<Bool> {
        Binding(get: { appState.settings.saveHistory }, set: { appState.settings.saveHistory = $0 })
    }
    private var autoPasteBinding: Binding<Bool> {
        Binding(get: { appState.settings.autoPaste }, set: { appState.settings.autoPaste = $0 })
    }

    // MARK: - Storage

    private var storageSection: some View {
        HDCard(.canvas) {
            VStack(alignment: .leading, spacing: HDSpacing.md.rawValue) {
                sectionTitle("Хранение")

                row("Vault", value: VaultPaths.root.path, mono: true)
                row("Записей", value: "\(statsObserver.notes.count)")
                row("Размер на диске", value: formatBytes(vaultSize))

                HStack(spacing: HDSpacing.md.rawValue) {
                    HDButtonSecondary(title: "Открыть в Finder", icon: "folder") {
                        NSWorkspace.shared.open(VaultPaths.root)
                    }
                    switch obsidianStatus {
                    case .installed(let url):
                        HDButtonSecondary(title: "Открыть в Obsidian", icon: "book") {
                            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                        }
                    case .notInstalled:
                        HDButtonSecondary(title: "Obsidian не установлен", icon: "book") {
                            // no-op
                        }
                        .disabled(true)
                    case .unknown:
                        EmptyView()
                    }
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        HDCard(.stone) {
            VStack(alignment: .leading, spacing: HDSpacing.sm.rawValue) {
                Text("MyWhi")
                    .font(HDFont.featureHeading)
                    .foregroundStyle(theme.ink)
                Text("v2.0.0-alpha · Native macOS dictation powered by WhisperKit")
                    .font(HDFont.caption)
                    .foregroundStyle(theme.muted)
                Text("100% local. Audio stays on your Mac.")
                    .font(HDFont.micro)
                    .foregroundStyle(theme.muted)
            }
        }
    }

    // MARK: - Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(HDFont.monoLabel(size: 11))
            .hdTracking(0.5)
            .foregroundStyle(theme.muted)
    }

    private func row(_ label: String, value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(HDFont.bodySmall)
                .foregroundStyle(theme.muted)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(mono ? HDFont.monoLabel(size: 11) : HDFont.bodySmall)
                .foregroundStyle(theme.ink)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func refreshStorage() async {
        // `vaultSizeOnDisk` is already async on the actor; assign
        // directly without a redundant MainActor.run hop.
        let bytes = (try? await appState.vaultStore.sizeOnDisk()) ?? 0
        vaultSize = bytes
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func detectObsidian() -> ObsidianStatus {
        let candidates = [
            URL(fileURLWithPath: "/Applications/Obsidian.app"),
            URL(fileURLWithPath: "/Applications/Obsidian Helper.app"),
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return .installed(url)
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        task.arguments = ["kMDItemCFBundleIdentifier == \"md.obsidian\""]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let s = String(data: data, encoding: .utf8), !s.isEmpty {
                let first = s.components(separatedBy: "\n").first ?? ""
                return .installed(URL(fileURLWithPath: first))
            }
        } catch {
            // ignore
        }
        return .notInstalled
    }
}