// MainPopoverView.swift
// The single window anchored to the menu bar icon. Reuses shared
// components from the Design System so the visual language matches
// the desktop app exactly.
//
// Phase 2.2 / 2.3 changes:
// - Live HDWaveformView while recording (compact mode, 12 bars)
// - Explicit "Остановить" Stop button when status == .recording
// - Live duration counter in the header
// - "Отменить" Discard button — calls AppState.discardRecording()
//
// Phase 7 changes:
// - Migrated to HDTheme via `@Environment(\.hdTheme)` for full dark-mode
//   coherence. Replaced hardcoded `.font(.system(size:))` and stray
//   `.foregroundStyle(...)` calls with HDFont + theme tokens.
// - Performance: RecordingDurationView now uses SwiftUI's built-in
//   `Text(date, style: .timer)` instead of TimelineView + manual format.
// - Performance: recentNotes cache via @State to avoid recompute on every
//   body re-evaluation.

import SwiftUI

struct MainPopoverView: View {

    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var statsObserver: StatsObserver
    @Environment(\.hdTheme) private var theme
    @Environment(\.openWindow) private var openWindow

    @State private var cachedRecentNotes: [TranscriptNote] = []
    @State private var notesRevision: Int = 0

    // Phase 11: inline editor state. We keep a separate `draftText`
    // so the user can edit without mutating `appState.lastTranscript`
    // (which is also used by HomeView for the desktop transcript card
    // and by StatsObserver for the vault save). The draft seeds
    // itself from lastTranscript on every change, then the user
    // diverges via edits; "Insert" commits it.
    @State private var draftText: String = ""
    @State private var lastSeededTranscript: String = ""
    @FocusState private var isEditorFocused: Bool

    /// Cache the prefix-of-3 list. Recomputes only when statsObserver.notes
    /// changes (we observe via onChange). Previously this was a computed
    /// property → re-evaluated on every body re-render (every level meter
    /// tick, every status change).
    private var recentNotes: [TranscriptNote] { cachedRecentNotes }

    var body: some View {
        VStack(alignment: .leading, spacing: HDSpacing.lg.rawValue) {
            header
            if let err = appState.errorMessage, !err.isEmpty {
                errorBanner(err)
            }
            quickRecord
            if appState.status == .recording {
                recordingControls
            }
            if !appState.lastTranscript.isEmpty && appState.status != .recording {
                lastTranscriptCard
            }
            if !recentNotes.isEmpty {
                recentList
            }
            footer
        }
        .padding(HDSpacing.lg.rawValue)
        .frame(width: 380)
        .background(theme.canvas)
        .onAppear {
            refreshRecentNotes()
            seedDraftIfNeeded()
        }
        .onChange(of: statsObserver.notes) { _, _ in refreshRecentNotes() }
        .onChange(of: appState.lastTranscript) { _, _ in seedDraftIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .mywhiOpenDesktop)) { _ in
            openDesktopWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mywhiOpenDesignPreview)) { _ in
            container.sceneRouter.setMode(.desktop)
            openWindow(id: "design-preview")
        }
    }

    private func refreshRecentNotes() {
        cachedRecentNotes = Array(statsObserver.notes.prefix(3))
    }

    /// Seed the editor's draft text from `lastTranscript` when the
    /// underlying transcript changes (i.e. a new transcription just
    /// finished). We only seed if the user hasn't already diverged —
    /// if `draftText` doesn't match the previous `lastTranscript` it
    /// means the user is mid-edit on an older draft and we leave
    /// them alone.
    private func seedDraftIfNeeded() {
        let next = appState.lastTranscript
        guard !next.isEmpty else { return }
        // If the draft is empty OR already equals the previous
        // transcript, take the new one.
        if draftText.isEmpty || draftText == lastSeededTranscript {
            draftText = next
        }
        lastSeededTranscript = next
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: HDSpacing.md.rawValue) {
            Image(systemName: appState.status.iconName)
                .font(HDFont.titleGlyph)
                .foregroundStyle(statusColor)
                .symbolEffect(.pulse, options: .repeating, isActive: appState.status == .recording)

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.status.rawValue)
                    .font(HDFont.featureHeading)
                    .foregroundStyle(theme.ink)
                HStack(spacing: HDSpacing.xs.rawValue) {
                    Text("MyWhi")
                        .font(HDFont.caption)
                        .foregroundStyle(theme.muted)
                    Text("·")
                        .font(HDFont.caption)
                        .foregroundStyle(theme.muted)
                    Text(appState.activeEngineName)
                        .font(HDFont.monoLabel(size: 11))
                        .foregroundStyle(theme.muted)
                }
            }
            Spacer()
            if appState.status == .recording {
                RecordingDurationView()
            }
        }
    }

    private var statusColor: Color {
        switch appState.status {
        case .recording:    return theme.deepGreen
        case .transcribing: return theme.coral
        case .copied:       return theme.actionBlue
        case .error:        return theme.error
        default:            return theme.muted
        }
    }

    // MARK: - Error

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(HDFont.caption)
            .foregroundStyle(theme.onPrimary)
            .padding(HDSpacing.md.rawValue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: HDRadius.sm.rawValue, style: .continuous)
                    .fill(theme.error)
            )
            .lineLimit(4)
    }

    // MARK: - Quick record (idle / transcribing)

    private var quickRecord: some View {
        let state: HDRecordState = {
            switch appState.status {
            case .recording:    return .recording
            case .transcribing: return .transcribing
            default:            return .idle
            }
        }()

        return HStack(spacing: HDSpacing.md.rawValue) {
            HDRecordButton(state: state, size: 48) {
                appState.toggleRecording()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(actionLabel)
                    .font(HDFont.actionLabel)
                    .foregroundStyle(theme.ink)
                Text(hintLabel)
                    .font(HDFont.micro)
                    .foregroundStyle(theme.muted)
            }

            Spacer()

            Button {
                appState.transcribeLastRecording()
            } label: {
                Image(systemName: "waveform")
                    .font(HDFont.iconSmall)
            }
            .buttonStyle(.borderless)
            .disabled(appState.recorder.lastRecordingURL == nil
                      || appState.status == .recording
                      || appState.status == .transcribing)
        }
    }

    // MARK: - Recording controls (live waveform + stop + discard)

    private var recordingControls: some View {
        VStack(spacing: HDSpacing.md.rawValue) {
            // Live waveform fills the width
            HDWaveformView(
                level: appState.recorderLevel,
                style: .compact,
                color: theme.deepGreen
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, HDSpacing.xs.rawValue)

            HStack(spacing: HDSpacing.md.rawValue) {
                HDButtonPrimary(
                    title: "Остановить",
                    icon: "stop.fill"
                ) {
                    appState.stopRecording()
                }
                .keyboardShortcut(.return, modifiers: [])

                Button {
                    appState.discardRecording()
                } label: {
                    Label("Отменить", systemImage: "xmark")
                        .font(HDFont.discardLabel)
                        .foregroundStyle(theme.muted)
                }
                .buttonStyle(.plain)
                .help("Удалить запись без транскрибации (Esc)")
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(HDSpacing.md.rawValue)
        .background(
            RoundedRectangle(cornerRadius: HDRadius.md.rawValue, style: .continuous)
                .fill(theme.surfacePaleGreen)
        )
    }

    private var actionLabel: String {
        switch appState.status {
        case .recording:    return "Говори…"
        case .transcribing: return "Транскрибация…"
        case .copied:       return "Готово · в буфере"
        default:            return "Готово к записи"
        }
    }

    private var hintLabel: String {
        let model = appState.settings.modelSize
        switch appState.status {
        case .idle:    return "Engine \(appState.activeEngineName) · \(model)"
        case .copied:  return "Cmd+V"
        default:       return ""
        }
    }

    // MARK: - Last transcript

    private var lastTranscriptCard: some View {
        // Phase 11: when inline editor mode is on, the card becomes an
        // editable surface so the user can tweak wording before
        // pasting. When off, we keep the original read-only Text +
        // Copy button.
        let inline = appState.settings.inlineEditorMode

        return HDCard(.stone, cornerRadius: .md, padding: .md) {
            VStack(alignment: .leading, spacing: HDSpacing.sm.rawValue) {
                HStack {
                    Text(inline ? "РЕДАКТОР" : "ПОСЛЕДНЯЯ")
                        .font(HDFont.monoLabel(size: 10))
                        .hdTracking(0.5)
                        .foregroundStyle(theme.muted)
                    Spacer()
                    Text("\(effectiveTranscript.count) символов")
                        .font(HDFont.micro)
                        .foregroundStyle(theme.muted)
                }
                if inline {
                    inlineEditor
                } else {
                    Text(appState.lastTranscript)
                        .font(HDFont.cardBody)
                        .foregroundStyle(theme.ink)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    HStack {
                        HDButtonSecondary(title: "Копировать") {
                            appState.clipboard.copy(appState.lastTranscript)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Inline editor (Phase 11)

    /// The transcript the editor is showing. When inline editor mode
    /// is on, this is the user's draft (which may diverge from
    /// `lastTranscript`); otherwise it's just the read-only transcript.
    private var effectiveTranscript: String {
        appState.settings.inlineEditorMode ? draftText : appState.lastTranscript
    }

    private var inlineEditor: some View {
        VStack(alignment: .leading, spacing: HDSpacing.sm.rawValue) {
            // TextEditor with a fixed max-height so the popover stays
            // a usable size — long transcripts scroll inside the
            // editor rather than blowing up the popover layout.
            TextEditor(text: $draftText)
                .font(HDFont.editorBody)
                .foregroundStyle(theme.ink)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80, maxHeight: 180)
                .padding(HDSpacing.xs.rawValue)
                .background(
                    RoundedRectangle(cornerRadius: HDRadius.xs.rawValue, style: .continuous)
                        .fill(theme.canvas)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: HDRadius.xs.rawValue, style: .continuous)
                        .stroke(isEditorFocused ? theme.focusBlue : theme.border, lineWidth: 1)
                )
                .focused($isEditorFocused)
                .submitLabel(.done)

            HStack(spacing: HDSpacing.sm.rawValue) {
                HDButtonPrimary(title: "Вставить", icon: "arrow.down.to.line") {
                    commitDraft()
                }
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                HDButtonSecondary(title: "Копировать", icon: "doc.on.doc") {
                    appState.clipboard.copy(draftText)
                }
                .disabled(draftText.isEmpty)

                HDButtonSecondary(title: "Сброс", icon: "arrow.uturn.backward") {
                    draftText = appState.lastTranscript
                    lastSeededTranscript = appState.lastTranscript
                }
                .help("Откатить к исходной транскрибации")
                .disabled(draftText == appState.lastTranscript)

                Spacer()
            }

            if appState.settings.autoPaste {
                HStack(spacing: HDSpacing.xs.rawValue) {
                    Image(systemName: "info.circle")
                        .font(HDFont.iconTiny)
                        .foregroundStyle(theme.muted)
                    Text("⌘V сработает в активном приложении")
                        .font(HDFont.micro)
                        .foregroundStyle(theme.muted)
                }
            }
        }
    }

    /// Commit the current draft: copy to clipboard, paste if autoPaste
    /// is on, fire success haptic, and update `lastTranscript` so the
    /// Home view and vault reflect the (possibly edited) final text.
    private func commitDraft() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.clipboard.copy(trimmed)
        if appState.settings.autoPaste {
            AutoPasteService.pasteFromClipboard()
        }
        // Promote the edited text to lastTranscript so:
        //   - The Home view's last transcript card shows the edited text.
        //   - The vault save (already done during transcribeFile) keeps
        //     the original WhisperKit output; if you want the edit in
        //     the vault too, edit the Scratchpad entry.
        appState.promoteLastTranscript(trimmed)
        HapticFeedback.success.fire()
        // Reset the seed marker so a *future* transcription won't be
        // silently overwritten by the editor's residue.
        lastSeededTranscript = trimmed
    }

    // MARK: - Recent

    private var recentList: some View {
        VStack(alignment: .leading, spacing: HDSpacing.xs.rawValue) {
            Text("НЕДАВНИЕ")
                .font(HDFont.monoLabel(size: 10))
                .hdTracking(0.5)
                .foregroundStyle(theme.muted)
            ForEach(recentNotes, id: \.id) { note in
                Button {
                    appState.clipboard.copy(note.body)
                } label: {
                    HStack(alignment: .top, spacing: HDSpacing.sm.rawValue) {
                        Image(systemName: "doc.text")
                            .font(HDFont.iconTiny)
                            .foregroundStyle(theme.muted)
                            .frame(width: 14)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title)
                                .font(HDFont.noteTitle)
                                .foregroundStyle(theme.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text("\(note.frontmatter.words) слов · \(note.frontmatter.createdAt.formatted(date: .omitted, time: .shortened))")
                                .font(HDFont.noteMeta)
                                .foregroundStyle(theme.muted)
                        }
                        Spacer()
                        Image(systemName: "doc.on.doc")
                            .font(HDFont.iconTiny)
                            .foregroundStyle(theme.muted)
                    }
                    .padding(.vertical, HDSpacing.xs.rawValue)
                    .padding(.horizontal, HDSpacing.sm.rawValue)
                    .background(
                        RoundedRectangle(cornerRadius: HDRadius.xs.rawValue, style: .continuous)
                            .fill(theme.surfaceStone.opacity(0.5))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: HDSpacing.sm.rawValue) {
            Divider()

            // Hotkey hint — visible until the user has used the
            // global hotkey at least once.
            if !hotkeyHintDismissed {
                hotkeyHint
            }

            HStack {
                Text("v2.0 · \(statsObserver.stats.totalWords) слов всего")
                    .font(HDFont.micro)
                    .foregroundStyle(theme.muted)
                Spacer()
                HDButtonSecondary(title: "Открыть MyWhi", icon: "arrow.up.right.square") {
                    openDesktopWindow()
                }
            }
        }
    }

    private func openDesktopWindow() {
        container.sceneRouter.setMode(.desktop)
        openWindow(id: "desktop")
    }

    @AppStorage("mywhi.hotkeyHintShown") private var hotkeyHintDismissed: Bool = false

    private var hotkeyHint: some View {
        HStack(spacing: HDSpacing.sm.rawValue) {
            Image(systemName: "keyboard")
                .font(HDFont.iconSmall)
                .foregroundStyle(theme.coral)
            VStack(alignment: .leading, spacing: 1) {
                Text("Глобальный hotkey")
                    .font(HDFont.hotkeyTitle)
                    .foregroundStyle(theme.ink)
                Text("Нажми ⌘⌥D из любого приложения")
                    .font(HDFont.hotkeySub)
                    .foregroundStyle(theme.muted)
            }
            Spacer()
            Button {
                hotkeyHintDismissed = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(HDFont.iconSmall)
                    .foregroundStyle(theme.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(HDSpacing.sm.rawValue)
        .background(
            RoundedRectangle(cornerRadius: HDRadius.xs.rawValue, style: .continuous)
                .fill(theme.surfacePaleGreen)
        )
    }
}

// MARK: - Recording duration counter
//
// Phase 7: use SwiftUI's built-in Text(_:style:.timer) instead of a
// TimelineView + manual format. Same visual output, much less work for
// SwiftUI — no view body re-evaluation 2x/second.

private struct RecordingDurationView: View {
    private let startTime = Date()

    var body: some View {
        Text(timerInterval: Date()...Date.distantFuture, countsDown: false, showsHours: false)
            .font(HDFont.monoLabel(size: 13, weight: .medium))
            .foregroundStyle(HDColor.deepGreen)
            .monospacedDigit()
    }
}