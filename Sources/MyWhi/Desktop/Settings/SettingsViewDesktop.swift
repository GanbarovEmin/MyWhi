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
    @State private var downloadedModels: Set<String> = []

    enum ObsidianStatus {
        case unknown
        case installed(URL)
        case notInstalled
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HDSpacing.xl.rawValue) {
                header
                engineSection
                recordingSection
                meetingSection
                insertionSection
                appearanceSection
                textCleanupSection
                personalDictionarySection
                postProcessingSection
                storageSection
                aboutSection
            }
            .padding(HDSpacing.xxl.rawValue)
            .frame(maxWidth: 760, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.canvas)
        .task {
            await refreshStorage()
            refreshDownloadedModels()
            obsidianStatus = detectObsidian()
        }
        .onChange(of: appState.engineManager.isLoading) { _, isLoading in
            if !isLoading {
                refreshDownloadedModels()
            }
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

                settingsPickerRow(title: "Движок диктовки") {
                    Picker("", selection: backendBinding) {
                        ForEach(AppSettings.availableBackends, id: \.code) { backend in
                            Text(backend.label).tag(backend.code)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)
                }

                if appState.settings.transcriptionBackend == "whisperkit" {
                    VStack(spacing: HDSpacing.xs.rawValue) {
                        ForEach(AppSettings.availableModels, id: \.code) { entry in
                            modelStatusRow(entry)
                        }
                    }
                    .disabled(appState.engineManager.isLoading)
                } else {
                    VStack(spacing: HDSpacing.xs.rawValue) {
                        ForEach(AppSettings.availableSoniqoModels, id: \.code) { entry in
                            soniqoModelStatusRow(entry)
                        }
                    }
                    .disabled(appState.engineManager.isLoading)
                    Text(SoniqoTranscriber.isAvailable()
                         ? "speech CLI установлен. Этот backend работает локально через Soniqo."
                         : "speech CLI не найден. Установи через brew install speech.")
                        .font(HDFont.caption)
                        .foregroundStyle(SoniqoTranscriber.isAvailable() ? theme.muted : theme.coral)
                }

                Picker("Язык", selection: languageBinding) {
                    ForEach(AppSettings.availableLanguages, id: \.code) { lang in
                        Text(LocalizedStringKey(lang.label)).tag(lang.code)
                    }
                }
                .pickerStyle(.segmented)

                if appState.engineManager.isLoading {
                    HStack(spacing: HDSpacing.sm.rawValue) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Загружается \(activeModelLabel)…")
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
            set: { newValue in
                guard appState.settings.modelSize != newValue else { return }
                appState.settings.modelSize = newValue
                Task { await appState.reloadEngine() }
            }
        )
    }

    private var backendBinding: Binding<String> {
        Binding(
            get: { appState.settings.transcriptionBackend },
            set: { newValue in
                guard appState.settings.transcriptionBackend != newValue else { return }
                appState.settings.transcriptionBackend = newValue
                Task { await appState.reloadEngine() }
            }
        )
    }

    private var soniqoModelBinding: Binding<String> {
        Binding(
            get: { appState.settings.soniqoModel },
            set: { newValue in
                guard appState.settings.soniqoModel != newValue else { return }
                appState.settings.soniqoModel = newValue
                Task { await appState.reloadEngine() }
            }
        )
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { appState.settings.language },
            set: { appState.settings.language = $0 }
        )
    }

    private var activeModelLabel: String {
        if appState.settings.transcriptionBackend == "soniqo" {
            return AppSettings.availableSoniqoModels
                .first { $0.code == appState.settings.soniqoModel }?
                .label ?? appState.settings.soniqoModel
        }
        return appState.settings.modelSize
    }

    private func modelStatusRow(_ entry: (code: String, label: String, description: String)) -> some View {
        let isSelected = appState.settings.modelSize == entry.code
        let isDownloaded = downloadedModels.contains(entry.code)

        return Button {
            guard appState.settings.modelSize != entry.code else { return }
            modelBinding.wrappedValue = entry.code
        } label: {
            HStack(spacing: HDSpacing.md.rawValue) {
                Image(systemName: isDownloaded ? "checkmark.circle.fill" : "icloud.and.arrow.down")
                    .font(HDFont.iconSmall)
                    .foregroundStyle(isDownloaded ? theme.deepGreen : theme.muted)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(entry.label))
                        .font(HDFont.formLabel)
                        .foregroundStyle(theme.ink)
                    Text(LocalizedStringKey(entry.description))
                        .font(HDFont.micro)
                        .foregroundStyle(theme.muted)
                }

                Spacer(minLength: HDSpacing.md.rawValue)

                if appState.engineManager.isLoading && isSelected {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(LocalizedStringKey(isDownloaded ? "Скачано" : "Нужно скачать"))
                    .font(HDFont.monoLabel(size: 10, weight: .medium))
                    .padding(.horizontal, HDSpacing.sm.rawValue)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(isDownloaded ? theme.surfacePaleGreen : theme.surfaceStone)
                    )
                    .foregroundStyle(isDownloaded ? theme.deepGreen : theme.muted)
            }
            .padding(.horizontal, HDSpacing.md.rawValue)
            .padding(.vertical, HDSpacing.sm.rawValue)
            .background(
                RoundedRectangle(cornerRadius: HDRadius.sm.rawValue, style: .continuous)
                    .fill(isSelected ? theme.surfaceStone.opacity(0.85) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HDRadius.sm.rawValue, style: .continuous)
                    .stroke(isSelected ? theme.border : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: HDRadius.sm.rawValue, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func soniqoModelStatusRow(_ entry: (code: String, label: String, description: String)) -> some View {
        let isSelected = appState.settings.soniqoModel == entry.code
        let isAvailable = SoniqoTranscriber.isAvailable()

        return Button {
            soniqoModelBinding.wrappedValue = entry.code
        } label: {
            HStack(spacing: HDSpacing.md.rawValue) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "waveform")
                    .font(HDFont.iconSmall)
                    .foregroundStyle(isSelected ? theme.deepGreen : theme.muted)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(entry.label))
                        .font(HDFont.formLabel)
                        .foregroundStyle(theme.ink)
                    Text(LocalizedStringKey(entry.description))
                        .font(HDFont.micro)
                        .foregroundStyle(theme.muted)
                }

                Spacer(minLength: HDSpacing.md.rawValue)

                if appState.engineManager.isLoading && isSelected {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(LocalizedStringKey(isAvailable ? "Готово" : "Нет CLI"))
                    .font(HDFont.monoLabel(size: 10, weight: .medium))
                    .padding(.horizontal, HDSpacing.sm.rawValue)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(isAvailable ? theme.surfacePaleGreen : theme.surfaceStone)
                    )
                    .foregroundStyle(isAvailable ? theme.deepGreen : theme.muted)
            }
            .padding(.horizontal, HDSpacing.md.rawValue)
            .padding(.vertical, HDSpacing.sm.rawValue)
            .background(
                RoundedRectangle(cornerRadius: HDRadius.sm.rawValue, style: .continuous)
                    .fill(isSelected ? theme.surfaceStone.opacity(0.85) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HDRadius.sm.rawValue, style: .continuous)
                    .stroke(isSelected ? theme.border : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: HDRadius.sm.rawValue, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Recording

    private var recordingSection: some View {
        HDCard(.canvas) {
            VStack(alignment: .leading, spacing: HDSpacing.md.rawValue) {
                sectionTitle("Запись")

                Toggle("Показывать текст во время записи", isOn: liveStreamingBinding)
                    .help("Слова появляются по мере того, как ты говоришь. Требует больше CPU.")

                Toggle("Звуковой сигнал старт/стоп", isOn: soundFeedbackBinding)
                    .help("Мягкий chime при начале и конце записи.")

                Toggle("Удерживать hotkey для записи", isOn: pushToTalkBinding)
                    .help("Удерживай горячую клавишу чтобы записать, отпусти чтобы остановить. По умолчанию — toggle.")

                Divider()

                settingsPickerRow(title: "Окно live-декода") {
                    Picker("", selection: liveWindowBinding) {
                        Text("4 сек").tag(4)
                        Text("6 сек").tag(6)
                        Text("8 сек (стандарт)").tag(8)
                        Text("12 сек").tag(12)
                        Text("20 сек").tag(20)
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220)
                }
                .help("Сколько секунд последнего аудио декодировать в каждом live-тике. Меньше — отзывчивее, больше — стабильнее.")
            }
        }
    }

    private var meetingSection: some View {
        HDCard(.canvas) {
            VStack(alignment: .leading, spacing: HDSpacing.md.rawValue) {
                sectionTitle("Meeting Mode")

                settingsPickerRow(title: "ASR для встреч") {
                    Picker("", selection: meetingModelBinding) {
                        ForEach(AppSettings.availableSoniqoModels, id: \.code) { model in
                            Text(model.label).tag(model.code)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 260)
                }

                Toggle("Записывать системный звук звонка", isOn: meetingSystemAudioBinding)
                    .help("Требует Screen Recording/System Audio permission. Если доступ не выдан, Meeting Mode продолжит запись микрофона.")
                Toggle("Шумоподавление через DeepFilterNet3", isOn: meetingDenoiseBinding)
                Toggle("Разделять по говорящим", isOn: meetingDiarizationBinding)

                VStack(alignment: .leading, spacing: HDSpacing.xs.rawValue) {
                    Text("Контекст для распознавания")
                        .font(HDFont.formLabel)
                        .foregroundStyle(theme.ink)
                    TextField("Участники, проект, имена, термины", text: meetingContextBinding, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    // MARK: Insertion

    private var insertionSection: some View {
        HDCard(.canvas) {
            VStack(alignment: .leading, spacing: HDSpacing.md.rawValue) {
                sectionTitle("Вставка и hotkey")

                Toggle("Копировать в буфер после записи", isOn: autoCopyBinding)
                Toggle("Сохранять в vault", isOn: saveHistoryBinding)
                Toggle("Авто-вставка в активное приложение (⌘V)", isOn: autoPasteBinding)
                    .help("Требует разрешение Accessibility")

                hotkeyRow

                if appState.settings.autoPaste {
                    accessibilityRow
                }

                Divider()

                Toggle("Редактировать перед вставкой", isOn: inlineEditorBinding)
                    .help("После транскрибации показывать редактор вместо авто-копирования. Нажми «Вставить» чтобы скопировать отредактированный текст.")

                Toggle("Посимвольный ввод в активное приложение", isOn: phantomCursorBinding)
                    .help("Ввод текста посимвольно прямо в активное приложение — текст появляется где курсор. Требует разрешения Accessibility.")
            }
        }
    }

    private var hotkeyRow: some View {
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
    }

    private var accessibilityRow: some View {
        HStack(spacing: HDSpacing.sm.rawValue) {
            if AutoPasteService.isAccessibilityGranted() {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.deepGreen)
                Text("Accessibility разрешение выдано")
                    .font(HDFont.caption)
                    .foregroundStyle(theme.muted)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.coral)
                Text("Для авто-вставки нужно Accessibility разрешение")
                    .font(HDFont.caption)
                    .foregroundStyle(theme.coral)
            }
            Spacer()
            HDButtonSecondary(title: "Открыть настройки") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
        .padding(.vertical, HDSpacing.xs.rawValue)
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        HDCard(.canvas) {
            VStack(alignment: .leading, spacing: HDSpacing.md.rawValue) {
                sectionTitle("Окно и внешний вид")

                Toggle("Тёмная тема вместо системной", isOn: darkModeBinding)
                    .help("Принудительно включить тёмную тему независимо от системных настроек macOS")

                Toggle("Показывать idle-плашку на рабочем столе", isOn: showIdleFloatingHUDBinding)
                    .help("Когда включено, MyWhi показывает плавающую кнопку записи даже до старта. По умолчанию выключено.")

                settingsPickerRow(title: "Позиция плавающего HUD") {
                    Picker("", selection: hudPositionBinding) {
                        Text("Снизу").tag(AppSettings.HUDPosition.bottom)
                        Text("Сверху").tag(AppSettings.HUDPosition.top)
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 320)
                }
                .help("Где показывать плавающее окно во время записи.")
            }
        }
    }

    // MARK: Text cleanup

    private var textCleanupSection: some View {
        HDCard(.canvas) {
            VStack(alignment: .leading, spacing: HDSpacing.md.rawValue) {
                sectionTitle("Текст")

                Toggle("Пост-обработка текста", isOn: postProcessingBinding)
                    .help("Удаление слов-паразитов, исправление пунктуации и заглавных букв, ручные regex-правила.")

                Toggle("Голосовые команды пунктуации", isOn: voiceCommandsBinding)
                    .help("Биас декодера на распознавание голосовых команд. «точка» → «.», «запятая» → «,», «новая строка» → перенос.")
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

    /// Phase 23: opt-in toggle for phantom cursor mode. Bound to
    /// `appState.settings.phantomCursorMode`. When the user flips
    /// this on, AppState will start typing dictated text into the
    /// focused app character-by-character instead of pasting it.
    private var phantomCursorBinding: Binding<Bool> {
        Binding(get: { appState.settings.phantomCursorMode },
                set: { appState.settings.phantomCursorMode = $0 })
    }

    private var liveWindowBinding: Binding<Int> {
        Binding(
            get: { appState.settings.liveWindowSeconds },
            set: { appState.settings.liveWindowSeconds = $0 }
        )
    }

    private var meetingModelBinding: Binding<String> {
        Binding(get: { appState.settings.meetingModel }, set: { appState.settings.meetingModel = $0 })
    }

    private var meetingSystemAudioBinding: Binding<Bool> {
        Binding(get: { appState.settings.meetingRecordSystemAudio }, set: { appState.settings.meetingRecordSystemAudio = $0 })
    }

    private var meetingDenoiseBinding: Binding<Bool> {
        Binding(get: { appState.settings.meetingDenoiseAudio }, set: { appState.settings.meetingDenoiseAudio = $0 })
    }

    private var meetingDiarizationBinding: Binding<Bool> {
        Binding(get: { appState.settings.meetingDiarizationEnabled }, set: { appState.settings.meetingDiarizationEnabled = $0 })
    }

    private var meetingContextBinding: Binding<String> {
        Binding(get: { appState.settings.meetingContext }, set: { appState.settings.meetingContext = $0 })
    }

    private var hudPositionBinding: Binding<AppSettings.HUDPosition> {
        Binding(
            get: { appState.settings.hudPosition },
            set: { appState.settings.hudPosition = $0 }
        )
    }

    private var showIdleFloatingHUDBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.showIdleFloatingHUD },
            set: { appState.settings.showIdleFloatingHUD = $0 }
        )
    }

    private var voiceCommandsBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.voiceCommandsEnabled },
            set: { appState.settings.voiceCommandsEnabled = $0 }
        )
    }

    private var postProcessingBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.postProcessingEnabled },
            set: { appState.settings.postProcessingEnabled = $0 }
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
        case 0x2C: return "Пробел"
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

    // MARK: - Personal Dictionary (Phase 19)

    private var personalDictionarySection: some View {
        PersonalDictionaryView()
    }

    // MARK: - Post-Processing Rules

    private var postProcessingSection: some View {
        PostProcessingRulesView()
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
                Text("v2.0.0-alpha · локальная диктовка на macOS через WhisperKit")
                    .font(HDFont.caption)
                    .foregroundStyle(theme.muted)
                Text("100% локально. Аудио остаётся на этом Mac.")
                    .font(HDFont.micro)
                    .foregroundStyle(theme.muted)
                HStack(spacing: HDSpacing.md.rawValue) {
                    HDButtonSecondary(title: "Проверить обновления", icon: "arrow.down.circle") {
                        appState.sceneRouter?.setMode(.desktop)
                        AppContainer.shared.updateController.checkForUpdates(nil)
                    }
                    Text("Обновления приходят через GitHub Releases.")
                        .font(HDFont.micro)
                        .foregroundStyle(theme.muted)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(LocalizedStringKey(text.uppercased()))
            .font(HDFont.monoLabel(size: 11))
            .hdTracking(0.5)
            .foregroundStyle(theme.muted)
    }

    private func settingsPickerRow<Control: View>(
        title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: HDSpacing.sm.rawValue) {
            Text(LocalizedStringKey(title))
                .font(HDFont.formLabel)
                .foregroundStyle(theme.ink)
            control()
            Spacer(minLength: 0)
        }
    }

    private func row(_ label: String, value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(LocalizedStringKey(label))
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

    private func refreshDownloadedModels() {
        downloadedModels = WhisperKitModelStore.shared.downloadedModels(
            from: AppSettings.availableModels.map(\.code)
        )
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
