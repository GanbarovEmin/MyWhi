// ScratchpadDetailView.swift
// Right pane of the Scratchpad section. Renders one transcript note
// with a header (frontmatter meta + coral pill), a monospaced
// TextEditor for editing the body, and a toolbar (Copy / Save / Delete).
//
// Phase 7: HDTheme migration, hardcoded fonts → HDFont tokens.

import SwiftUI

struct ScratchpadDetailView: View {

    let note: TranscriptNote
    @EnvironmentObject private var statsObserver: StatsObserver
    @EnvironmentObject private var appState: AppState
    @Environment(\.hdTheme) private var theme

    @State private var bodyText: String = ""
    @State private var isDirty: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            editor
            Divider()
            toolbar
        }
        .background(theme.canvas)
        .onAppear {
            bodyText = note.body
            isDirty = false
        }
        .onChange(of: note.id) { _, _ in
            // Switched to a different note — flush any pending changes
            // and reset the editor.
            flushPendingSave()
            bodyText = note.body
            isDirty = false
        }
        .onDisappear {
            flushPendingSave()
        }
        .confirmationDialog(
            "Удалить эту транскрибацию?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                Task {
                    flushPendingSave()
                    await statsObserver.delete(note: note)
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Файл будет удалён из vault безвозвратно.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: HDSpacing.sm.rawValue) {
            HStack(spacing: HDSpacing.sm.rawValue) {
                Text(dateString(note.frontmatter.createdAt))
                    .font(HDFont.monoLabel(size: 11))
                    .hdTracking(0.4)
                    .foregroundStyle(theme.muted)

                Text(enginePillName)
                    .font(HDFont.badge)
                    .padding(.horizontal, HDSpacing.xs.rawValue + 2)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(enginePillColor.0)
                    )
                    .foregroundStyle(enginePillColor.1)

                Text("· \(note.frontmatter.model)")
                    .font(HDFont.badge)
                    .foregroundStyle(theme.muted)

                Spacer()

                if isDirty {
                    Text("не сохранено")
                        .font(HDFont.badge)
                        .foregroundStyle(theme.coral)
                } else {
                    Text("сохранено")
                        .font(HDFont.badge)
                        .foregroundStyle(theme.muted)
                }
            }
            HStack(spacing: HDSpacing.md.rawValue) {
                Text("\(note.frontmatter.words) слов")
                    .font(HDFont.micro)
                    .foregroundStyle(theme.muted)
                Text("\(note.frontmatter.chars) символов")
                    .font(HDFont.micro)
                    .foregroundStyle(theme.muted)
                if let audio = note.frontmatter.audio {
                    Text(audio)
                        .font(HDFont.micro)
                        .foregroundStyle(theme.muted)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(HDSpacing.xl.rawValue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.canvas)
    }

    // MARK: - Editor

    private var editor: some View {
        TextEditor(text: $bodyText)
            .font(HDFont.editorBody)
            .foregroundStyle(theme.ink)
            .scrollContentBackground(.hidden)
            .background(theme.canvas)
            .padding(HDSpacing.lg.rawValue)
            .onChange(of: bodyText) { _, _ in
                isDirty = true
                scheduleAutoSave()
            }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: HDSpacing.md.rawValue) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(bodyText, forType: .string)
            } label: {
                Label("Копировать", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            // Phase 10: ⌘⇧C is a less-obvious alternative to the menu bar
            // Copy. Some users prefer it; harmless to keep both.

            Button {
                Task { await saveNow() }
            } label: {
                Label("Сохранить", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!isDirty)

            Spacer()

            // Phase 10: Duplicate — clones the note with a new id and a
            // timestamp suffix in the title. Keyboard shortcut ⌘D. Useful
            // for templates / recurring dictations.
            Button {
                duplicate()
            } label: {
                Label("Дублировать", systemImage: "plus.square.on.square")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("d", modifiers: .command)

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Удалить", systemImage: "trash")
                    .foregroundStyle(theme.error)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.delete, modifiers: .command)
        }
        .padding(.horizontal, HDSpacing.xl.rawValue)
        .padding(.vertical, HDSpacing.md.rawValue)
        .background(theme.canvas)
    }

    // MARK: - Duplicate (Phase 10)

    private func duplicate() {
        let copyMarker = " — копия \(Self.duplicateStamp())"
        let newBody = bodyText + copyMarker
        Task {
            _ = await statsObserver.recordTranscript(
                text: newBody,
                language: note.frontmatter.language,
                model: note.frontmatter.model,
                engine: note.frontmatter.engine,
                durationSeconds: 0,
                audio: nil
            )
        }
    }

    private static func duplicateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }

    // MARK: - Auto-save

    /// Debounced save: waits 1.5s after the last keystroke.
    private func scheduleAutoSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await saveNow()
        }
    }

    private func saveNow() async {
        guard isDirty else { return }
        let updated = await statsObserver.update(note: note, newBody: bodyText)
        if updated != nil {
            isDirty = false
        }
    }

    private func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        if isDirty {
            Task { await saveNow() }
        }
    }

    // MARK: - Formatting helpers

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = .autoupdatingCurrent
        return f.string(from: date)
    }

    private var enginePillColor: (Color, Color) {
        if note.frontmatter.engine == "WhisperKit" {
            return (theme.surfacePaleGreen, theme.deepGreen)
        }
        return (theme.surfacePaleBlue, theme.actionBlue)
    }

    private var enginePillName: String {
        note.frontmatter.engine
    }
}
