// MainPopoverView.swift
// The single window the user ever sees — anchored to the menu bar icon.

import SwiftUI

struct MainPopoverView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let err = appState.errorMessage, !err.isEmpty {
                errorBanner(err)
            }

            recordingControls
            quickActions

            Divider()

            HistoryView()

            Divider()

            SettingsDisclosure()
        }
        .padding(16)
        .frame(width: 380)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: appState.status.iconName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(appState.status.color)
                .symbolEffect(.pulse, options: .repeating, isActive: appState.status == .recording)

            VStack(alignment: .leading, spacing: 1) {
                Text(appState.status.rawValue)
                    .font(.headline)
                Text("Hermes Dictate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.white)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
            .lineLimit(4)
    }

    // MARK: - Recording controls

    private var recordingControls: some View {
        HStack(spacing: 8) {
            if appState.status == .recording {
                Button(action: appState.stopRecording) {
                    Label("Stop Recording", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.return, modifiers: [])
                .controlSize(.large)
            } else {
                Button(action: appState.startRecording) {
                    Label("Start Recording", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .keyboardShortcut(.return, modifiers: [])
                .controlSize(.large)
                .disabled(appState.status == .transcribing)
            }
        }
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        HStack(spacing: 8) {
            Button {
                appState.transcribeLastRecording()
            } label: {
                Label("Transcribe Last", systemImage: "waveform")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(appState.recorder.lastRecordingURL == nil
                      || appState.status == .recording
                      || appState.status == .transcribing)

            Button {
                appState.clipboard.copy(appState.lastTranscript)
                if !appState.lastTranscript.isEmpty {
                    appState.objectWillChange.send()
                }
            } label: {
                Label("Copy Last", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(appState.lastTranscript.isEmpty)
        }
    }
}
