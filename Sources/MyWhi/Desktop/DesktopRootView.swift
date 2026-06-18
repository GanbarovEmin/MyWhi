// DesktopRootView.swift
// The main desktop window shell. NavigationSplitView with sidebar
// (Запись / Scratchpad / Insights / Настройки) + a detail pane that
// swaps based on selection.
//
// Listens for .mywhiOpenDesktop notifications to handle the "Open MyWhi"
// menu bar item: switches the activation policy, then opens the
// window via @Environment(\.openWindow).

import SwiftUI

enum SidebarSection: String, Hashable, CaseIterable, Identifiable {
    case home
    case scratchpad
    case insights
    case settings

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home:       return "mic"
        case .scratchpad: return "doc.text"
        case .insights:   return "chart.bar"
        case .settings:   return "gear"
        }
    }

    var label: String {
        switch self {
        case .home:       return "Запись"
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

    @Environment(\.openWindow) private var openWindow

    @State private var selection: SidebarSection? = .home
    @State private var scratchpadSelection: TranscriptNote?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .background(HDColor.canvas)
        .onReceive(NotificationCenter.default.publisher(for: .mywhiOpenDesktop)) { _ in
            openDesktopFromMenuBar()
        }
        .onAppear {
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
                    .font(.system(size: 18, weight: .semibold, design: .default))
                    .foregroundStyle(HDColor.ink)
                Text("v2.0")
                    .font(HDFont.micro)
                    .foregroundStyle(HDColor.muted)
            }
            .padding(.horizontal, HDSpacing.lg.rawValue)
            .padding(.top, HDSpacing.xl.rawValue)
            .padding(.bottom, HDSpacing.md.rawValue)

            Divider()
                .padding(.horizontal, HDSpacing.lg.rawValue)

            // Section list
            List(selection: $selection) {
                ForEach(SidebarSection.allCases) { section in
                    HDSidebarItem(
                        icon: section.icon,
                        label: section.label,
                        section: section,
                        badge: badge(for: section),
                        selection: selection
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: HDSpacing.xs.rawValue, leading: HDSpacing.sm.rawValue, bottom: HDSpacing.xs.rawValue, trailing: HDSpacing.sm.rawValue))
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Spacer()

            // v2.0: no engine switcher / fallback indicator. WhisperKit
            // is always the engine. We show the engine name and the
            // current model in the footer for reference.
            VStack(alignment: .leading, spacing: HDSpacing.xs.rawValue) {
                HStack(spacing: HDSpacing.xs.rawValue) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(HDColor.muted)
                    Text("\(appState.activeEngineName) · \(appState.settings.modelSize)")
                        .font(HDFont.micro)
                        .foregroundStyle(HDColor.muted)
                }
            }
            .padding(.horizontal, HDSpacing.lg.rawValue)
            .padding(.bottom, HDSpacing.lg.rawValue)
            .padding(.top, HDSpacing.sm.rawValue)
        }
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)
        .background(HDColor.canvas)
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
    }

    // MARK: - Notification handler

    private func openDesktopFromMenuBar() {
        // Switch the activation policy to .desktop so the Dock icon shows.
        container.sceneRouter.setMode(.desktop)
        // Open (or focus) the desktop window.
        openWindow(id: "desktop")
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
    var body: some View {
        VStack(spacing: HDSpacing.lg.rawValue) {
            Image(systemName: "doc.text")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(HDColor.muted)
            Text("Выбери транскрибацию слева")
                .font(HDFont.featureHeading)
                .foregroundStyle(HDColor.muted)
            Text("или запиши новую во вкладке «Запись».")
                .font(HDFont.caption)
                .foregroundStyle(HDColor.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HDColor.canvas)
    }
}