// ScratchpadDetailView.swift
// Right pane of the Scratchpad section. Renders one transcript note
// with a header (frontmatter meta + coral pill), a monospaced
// TextEditor for editing the body, and a toolbar (Copy / Save / Delete).

import SwiftUI

struct ScratchpadDetailView: View {

    let note: TranscriptNote
    @EnvironmentObject private var statsObserver: StatsObserver
    @EnvironmentObject private var appState: AppState

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
        .background(HDColor.canvas)
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
                    .foregroundStyle(HDColor.muted)

                Text(enginePill(note.frontmatter.engine))
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, HDSpacing.xs.rawValue + 2)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(note.frontmatter.engine == "whisperkit" ? HDColor.paleGreen : HDColor.paleBlue)
                    )
                    .foregroundStyle(note.frontmatter.engine == "whisperkit" ? HDColor.deepGreen : HDColor.actionBlue)

                Text("· \(note.frontmatter.model)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(HDColor.muted)

                Spacer()

                if isDirty {
                    Text("не сохранено")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(HDColor.coral)
                } else {
                    Text("сохранено")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(HDColor.muted)
                }
            }
            HStack(spacing: HDSpacing.md.rawValue) {
                Text("\(note.frontmatter.words) слов")
                    .font(HDFont.micro)
                    .foregroundStyle(HDColor.muted)
                Text("\(note.frontmatter.chars) символов")
                    .font(HDFont.micro)
                    .foregroundStyle(HDColor.muted)
                if let audio = note.frontmatter.audio {
                    Text(audio)
                        .font(HDFont.micro)
                        .foregroundStyle(HDColor.muted)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(HDSpacing.xl.rawValue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HDColor.canvas)
    }

    // MARK: - Editor

    private var editor: some View {
        TextEditor(text: $bodyText)
            .font(.system(size: 14, design: .monospaced))
            .foregroundStyle(HDColor.ink)
            .scrollContentBackground(.hidden)
            .background(HDColor.canvas)
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

            Button {
                Task { await saveNow() }
            } label: {
                Label("Сохранить", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!isDirty)

            Spacer()

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Удалить", systemImage: "trash")
                    .foregroundStyle(HDColor.error)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, HDSpacing.xl.rawValue)
        .padding(.vertical, HDSpacing.md.rawValue)
        .background(HDColor.canvas)
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
        f.locale = Locale(identifier: "ru_RU")
        return f.string(from: date)
    }

    private func enginePill(_ engine: String) -> String {
        engine == "whisperkit" ? "WhisperKit" : "Python"
    }
}