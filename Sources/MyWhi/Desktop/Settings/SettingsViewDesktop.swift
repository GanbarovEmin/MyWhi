// SettingsViewDesktop.swift
// Settings pane inside the desktop sidebar. Covers engine, model,
// language, behavior toggles, storage info, and Obsidian integration.

import SwiftUI

struct SettingsViewDesktop: View {

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var statsObserver: StatsObserver

    @State private var vaultSize: Int64 = 0
    @State private var obsidianStatus: ObsidianStatus = .unknown

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
        .background(HDColor.canvas)
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
                .foregroundStyle(HDColor.muted)
            Text("Как MyWhi работает")
                .font(HDFont.cardHeading)
                .hdTracking(-0.32)
                .foregroundStyle(HDColor.ink)
        }
    }

    // MARK: - Engine

    private var engineSection: some View {
        HDCard(.canvas) {
            VStack(alignment: .leading, spacing: HDSpacing.lg.rawValue) {
                sectionTitle("Движок транскрибации")

                Picker("Engine", selection: engineBinding) {
                    ForEach(EngineManager.availableEngines, id: \.code) { engine in
                        Text(engine.label).tag(engine.code)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(appState.engineManager.isLoading)
                .onChange(of: appState.settings.engine) { _, _ in
                    Task { await appState.reloadEngine() }
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

                // Model description below the picker — .menu style
                // only shows one line per item, so the description
                // lives in a small caption underneath.
                if let entry = AppSettings.availableModels.first(where: { $0.code == appState.settings.modelSize }) {
                    Text(entry.description)
                        .font(HDFont.micro)
                        .foregroundStyle(HDColor.muted)
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
                            .foregroundStyle(HDColor.muted)
                    }
                    .padding(.vertical, HDSpacing.xs.rawValue)
                }

                if appState.engineDidFallback {
                    HStack(spacing: HDSpacing.xs.rawValue) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(HDColor.coral)
                        Text("WhisperKit недоступен — используется fallback.")
                            .font(HDFont.caption)
                            .foregroundStyle(HDColor.coral)
                    }
                }
            }
        }
    }

    private var engineBinding: Binding<String> {
        Binding(
            get: { appState.settings.engine },
            set: { appState.settings.engine = $0 }
        )
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

                // Hotkey display + status (Phase 5.3 — UI surface for
                // the global hotkey. The actual key capture is a
                // future P5.x; for now we just show the current chord
                // and a button to re-register the default).
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Глобальный hotkey")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(HDColor.ink)
                        Text("Работает из любого приложения")
                            .font(HDFont.caption)
                            .foregroundStyle(HDColor.muted)
                    }
                    Spacer()
                    Text("⌘⌥D")
                        .font(HDFont.monoLabel(size: 14, weight: .medium))
                        .padding(.horizontal, HDSpacing.md.rawValue)
                        .padding(.vertical, HDSpacing.xs.rawValue)
                        .background(
                            RoundedRectangle(cornerRadius: HDRadius.xs.rawValue, style: .continuous)
                                .fill(HDColor.softStone)
                        )
                        .foregroundStyle(HDColor.ink)
                }

                if appState.settings.autoPaste {
                    HStack(spacing: HDSpacing.sm.rawValue) {
                        if AutoPasteService.isAccessibilityGranted() {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(HDColor.deepGreen)
                            Text("Accessibility permission выдана")
                                .font(HDFont.caption)
                                .foregroundStyle(HDColor.muted)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(HDColor.coral)
                            Text("Нужно разрешение Accessibility в Системных настройках")
                                .font(HDFont.caption)
                                .foregroundStyle(HDColor.coral)
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
            }
        }
    }

    private var darkModeBinding: Binding<Bool> {
        Binding(get: { appState.settings.useDarkMode }, set: { appState.settings.useDarkMode = $0 })
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
                    .foregroundStyle(HDColor.ink)
                Text("v2.0.0-alpha · Native macOS dictation powered by WhisperKit")
                    .font(HDFont.caption)
                    .foregroundStyle(HDColor.muted)
                Text("100% local. Audio stays on your Mac.")
                    .font(HDFont.micro)
                    .foregroundStyle(HDColor.muted)
            }
        }
    }

    // MARK: - Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(HDFont.monoLabel(size: 11))
            .hdTracking(0.5)
            .foregroundStyle(HDColor.muted)
    }

    private func row(_ label: String, value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(HDColor.muted)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(mono ? HDFont.monoLabel(size: 11) : .system(size: 13))
                .foregroundStyle(HDColor.ink)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func refreshStorage() async {
        let bytes = (try? await appState.vaultStore.sizeOnDisk()) ?? 0
        await MainActor.run { self.vaultSize = bytes }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func detectObsidian() -> ObsidianStatus {
        // Check standard /Applications/Obsidian.app
        let candidates = [
            URL(fileURLWithPath: "/Applications/Obsidian.app"),
            URL(fileURLWithPath: "/Applications/Obsidian Helper.app"),
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return .installed(url)
        }
        // mdfind fallback
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