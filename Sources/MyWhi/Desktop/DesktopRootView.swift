// DesktopRootView.swift
// The main desktop window shell. Fixed sidebar
// (Запись / Scratchpad / Insights / Настройки) + a detail pane that
// swaps based on selection.
//
// Listens for .mywhiOpenDesktop notifications to handle the "Open MyWhi"
// menu bar item: switches the activation policy, then opens the
// window via @Environment(\.openWindow).
//
// Phase 7: migrated to HDTheme. Hover state on sidebar items.

import SwiftUI

enum SidebarSection: String, Hashable, CaseIterable, Identifiable {
    case home
    case meeting
    case scratchpad
    case insights
    case settings

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home:       return "mic"
        case .meeting:    return "person.2.wave.2"
        case .scratchpad: return "doc.text"
        case .insights:   return "chart.bar"
        case .settings:   return "gear"
        }
    }

    var label: String {
        switch self {
        case .home:       return "Запись"
        case .meeting:    return "Meeting Mode"
        case .scratchpad: return "Scratchpad"
        case .insights:   return "Insights"
        case .settings:   return "Настройки"
        }
    }
}

struct DesktopRootView: View {

    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var statsObserver: StatsObserver
    @Environment(\.hdTheme) private var theme

    @Environment(\.openWindow) private var openWindow

    @State private var selection: SidebarSection? = .home
    @State private var scratchpadSelection: TranscriptNote?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: DesktopShellLayout.sidebarWidth)
            Divider()
                .frame(width: DesktopShellLayout.dividerWidth)
            detail
                .frame(
                    minWidth: DesktopShellLayout.detailMinWidth,
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(theme.canvas)
        .onReceive(NotificationCenter.default.publisher(for: .mywhiOpenDesktop)) { _ in
            openDesktopFromMenuBar()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mywhiNavigateToScratchpad)) { note in
            navigateToScratchpad(note)
        }
        .onAppear {
            if selection == nil {
                selection = .home
            }
            // Refresh stats whenever the desktop window comes forward.
            Task { await statsObserver.refresh() }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header / logo
            VStack(alignment: .leading, spacing: HDSpacing.xs.rawValue) {
                Text("MyWhi")
                    .font(HDFont.brandTitle)
                    .foregroundStyle(theme.ink)
                Text("v2.0")
                    .font(HDFont.micro)
                    .foregroundStyle(theme.muted)
            }
            .padding(.horizontal, HDSpacing.lg.rawValue)
            .padding(.top, HDSpacing.xl.rawValue)
            .padding(.bottom, HDSpacing.md.rawValue)

            Divider()
                .padding(.horizontal, HDSpacing.lg.rawValue)

            // Section list. Plain buttons are more reliable here than
            // macOS List(selection:) inside NavigationSplitView: on some
            // configurations the native sidebar renderer reserved the
            // column but drew no content.
            VStack(spacing: HDSpacing.xs.rawValue) {
                ForEach(SidebarSection.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        HDSidebarItem(
                            icon: section.icon,
                            label: section.label,
                            section: section,
                            badge: badge(for: section),
                            selection: selection
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, HDSpacing.sm.rawValue)
            .padding(.top, HDSpacing.md.rawValue)

            Spacer()

            // v2.0: no engine switcher / fallback indicator. WhisperKit
            // is always the engine. We show the engine name and the
            // current model in the footer for reference.
            VStack(alignment: .leading, spacing: HDSpacing.xs.rawValue) {
                HStack(spacing: HDSpacing.xs.rawValue) {
                    Image(systemName: "bolt.fill")
                        .font(HDFont.engineIcon)
                        .foregroundStyle(theme.muted)
                    Text("\(appState.activeEngineName) · \(appState.activeModelDisplayName)")
                        .font(HDFont.micro)
                        .foregroundStyle(theme.muted)
                }
            }
            .padding(.horizontal, HDSpacing.lg.rawValue)
            .padding(.bottom, HDSpacing.lg.rawValue)
            .padding(.top, HDSpacing.sm.rawValue)
        }
        .frame(maxHeight: .infinity)
        .background(theme.canvas)
    }

    private func badge(for section: SidebarSection) -> String? {
        switch section {
        case .scratchpad:
            let count = statsObserver.notes.count
            return count > 0 ? "\(count)" : nil
        default:
            return nil
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        ZStack {
            // Fade-in transition between sections (audit #21).
            // id() forces SwiftUI to treat each section as a distinct
            // view so the .transition fires on every change.
            switch selection {
            case .home, .none:
                HomeView()
                    .id(SidebarSection.home)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            case .meeting:
                MeetingModeView()
                    .id(SidebarSection.meeting)
                    .transition(.opacity)
            case .scratchpad:
                ScratchpadSplitView(selection: $scratchpadSelection)
                    .id(SidebarSection.scratchpad)
                    .transition(.opacity)
            case .insights:
                InsightsView()
                    .id(SidebarSection.insights)
                    .transition(.opacity)
            case .settings:
                SettingsViewDesktop()
                    .id(SidebarSection.settings)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: selection)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DesktopRecordingPill()
                .padding(.horizontal, HDSpacing.xl.rawValue)
                .padding(.bottom, HDSpacing.md.rawValue)
        }
    }

    // MARK: - Notification handler

    private func openDesktopFromMenuBar() {
        // Switch the activation policy to .desktop so the Dock icon shows.
        container.sceneRouter.setMode(.desktop)
        selection = .home
        // Open (or focus) the desktop window.
        openWindow(id: "desktop")
    }

    private func navigateToScratchpad(_ notification: Notification) {
        selection = .scratchpad
        guard let query = notification.userInfo?["query"] as? String,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            scratchpadSelection = statsObserver.notes.first
            return
        }
        scratchpadSelection = statsObserver.notes.first(where: { $0.body == query })
            ?? statsObserver.notes.first(where: { $0.body.contains(query) })
            ?? statsObserver.notes.first
    }
}

// MARK: - Persistent recording entry point

/// Wispr Flow-style control that is always visible in the desktop
/// window. Recording must never depend on the sidebar being open or on
/// the user finding the "Запись" section first.
private struct DesktopRecordingPill: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.hdTheme) private var theme

    var body: some View {
        HStack(spacing: HDSpacing.md.rawValue) {
            Button {
                appState.toggleRecording()
            } label: {
                ZStack {
                    Circle()
                        .fill(glyphFill)
                        .frame(width: 40, height: 40)
                    Image(systemName: glyphIcon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(glyphForeground)
                }
            }
            .buttonStyle(.plain)
            .disabled(appState.status == .transcribing)
            .help(primaryHelp)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: HDSpacing.xs.rawValue) {
                    Text(title)
                        .font(HDFont.actionLabel)
                        .foregroundStyle(theme.ink)
                    if appState.status == .recording {
                        DesktopRecordingDurationView()
                    }
                }

                if appState.status == .recording {
                    if !appState.livePartialTranscript.isEmpty {
                        Text(appState.livePartialTranscript)
                            .font(HDFont.micro)
                            .foregroundStyle(theme.muted)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                    } else {
                        HDWaveformView(
                            level: appState.recorderLevel,
                            style: .compact,
                            color: theme.deepGreen
                        )
                        .frame(width: 180, height: 18)
                    }
                } else {
                    Text(subtitle)
                        .font(HDFont.micro)
                        .foregroundStyle(theme.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: HDSpacing.sm.rawValue)

            if appState.status == .recording {
                Button {
                    appState.discardRecording()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.muted)
                .help("Отменить запись")

                Button {
                    appState.stopRecording()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.onPrimary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(theme.primary))
                }
                .buttonStyle(.plain)
                .help("Остановить и транскрибировать")
            } else {
                Text("⌥⌘")
                    .font(HDFont.monoLabel(size: 11, weight: .medium))
                    .foregroundStyle(theme.muted)
                    .padding(.horizontal, HDSpacing.sm.rawValue)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(theme.surfaceStone)
                    )
            }
        }
        .padding(.horizontal, HDSpacing.md.rawValue)
        .padding(.vertical, HDSpacing.sm.rawValue)
        .frame(maxWidth: 520)
        .background(
            Capsule(style: .continuous)
                .fill(theme.surface.opacity(0.98))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(theme.border, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 22, x: 0, y: 12)
        )
        .contentShape(Capsule(style: .continuous))
        .onTapGesture {
            guard appState.status != .transcribing else { return }
            appState.toggleRecording()
        }
        .animation(.easeInOut(duration: 0.18), value: appState.status)
        .animation(.easeInOut(duration: 0.18), value: appState.livePartialTranscript)
    }

    private var glyphIcon: String {
        switch appState.status {
        case .recording:
            return "mic.fill"
        case .transcribing:
            return "waveform"
        default:
            return "mic"
        }
    }

    private var glyphFill: Color {
        switch appState.status {
        case .recording:
            return theme.deepGreen
        case .transcribing:
            return theme.coral
        default:
            return theme.primary
        }
    }

    private var glyphForeground: Color {
        switch appState.status {
        case .recording:
            return theme.onDark
        default:
            return theme.onPrimary
        }
    }

    private var title: String {
        switch appState.status {
        case .recording:
            return appState.settings.pushToTalkMode ? "Слушаю (удерживайте)" : "Слушаю"
        case .transcribing:
            return "Преобразую речь"
        case .copied:
            return "Текст готов"
        case .error:
            return "Нужна проверка"
        case .idle:
            return "Нажми, чтобы диктовать"
        }
    }

    private var subtitle: String {
        switch appState.status {
        case .idle:
            return appState.settings.pushToTalkMode
                ? "Клик или удерживай ⌥⌘ для записи"
                : "Клик или ⌥⌘ для старта"
        case .transcribing:
            return "\(appState.activeEngineName) · \(appState.activeModelDisplayName)"
        case .copied:
            return appState.settings.autoPaste ? "Вставлено в активное приложение" : "Скопировано в буфер"
        case .error:
            return appState.errorMessage ?? "Проверь микрофон и разрешения"
        case .recording:
            return "Говори сейчас"
        }
    }

    private var primaryHelp: String {
        switch appState.status {
        case .recording:
            return "Остановить запись"
        case .transcribing:
            return "Идёт транскрибация"
        default:
            return "Начать запись"
        }
    }
}

private struct DesktopRecordingDurationView: View {
    private let startTime = Date()

    var body: some View {
        Text(timerInterval: startTime...Date.distantFuture, countsDown: false, showsHours: false)
            .font(HDFont.monoLabel(size: 12, weight: .medium))
            .foregroundStyle(HDColor.deepGreen)
            .monospacedDigit()
    }
}

// MARK: - Scratchpad split

/// Two-column layout inside the Scratchpad section: list + detail.
struct ScratchpadSplitView: View {
    @Binding var selection: TranscriptNote?
    @EnvironmentObject private var statsObserver: StatsObserver

    var body: some View {
        HSplitView {
            ScratchpadListView(selection: $selection)
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
            if let note = selection {
                ScratchpadDetailView(note: note)
                    .frame(minWidth: 400)
            } else {
                ScratchpadEmptyDetail()
                    .frame(minWidth: 400)
            }
        }
    }
}

private struct ScratchpadEmptyDetail: View {
    @Environment(\.hdTheme) private var theme

    var body: some View {
        VStack(spacing: HDSpacing.lg.rawValue) {
            Image(systemName: "doc.text")
                .font(HDFont.emptyHero)
                .foregroundStyle(theme.muted)
            Text("Выбери транскрибацию слева")
                .font(HDFont.featureHeading)
                .foregroundStyle(theme.muted)
            Text("или запиши новую во вкладке «Запись».")
                .font(HDFont.caption)
                .foregroundStyle(theme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.canvas)
    }
}
