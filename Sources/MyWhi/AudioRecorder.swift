// AudioRecorder.swift
// Thin wrapper around AVAudioRecorder. Produces 16 kHz mono PCM WAV
// (the format faster-whisper expects). All recorder interaction is on
// the main actor; AVFoundation's audio thread handles the actual IO.
//
// STORAGE
// Recordings land in /tmp/mywhi/recordings/. Old files (>7 days) are
// reaped on every start() to keep the directory bounded. The folder
// was renamed from "hermes-dictate" in the v2.0.0-alpha audit.

import Foundation
import AVFoundation

@MainActor
final class AudioRecorder: NSObject, ObservableObject {

    private var recorder: AVAudioRecorder?
    private(set) var lastRecordingURL: URL?
    private(set) var lastRecordingDuration: TimeInterval = 0
    private var recordStartedAt: Date?

    /// Recordings directory. Exposed internally for legacy-folder
    /// migration in AppState. Created lazily on first start().
    /// Renamed from "hermes-dictate" → "mywhi" in audit Phase 1.5.
    internal static var recordingsDir: URL {
        let url = URL(fileURLWithPath: "/tmp/mywhi", isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Format chosen to match faster-whisper's preferred input:
    /// 16 kHz, mono, 16-bit signed little-endian PCM in a WAV container.
    private static let wavSettings: [String: Any] = [
        AVFormatIDKey:            Int(kAudioFormatLinearPCM),
        AVSampleRateKey:          16_000.0,
        AVNumberOfChannelsKey:    1,
        AVLinearPCMBitDepthKey:   16,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsFloatKey:    false,
        AVLinearPCMIsNonInterleaved: false,
    ]

    /// Files older than this are reaped on each start() (audit #6).
    private static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    // MARK: - Permission

    /// Returns true if we already have mic access, or prompts the user
    /// and returns their choice. macOS shows the standard TCC dialog.
    func requestPermissionIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Record

    func start() throws {
        // Stop any in-flight recording first; should not happen in MVP
        // (we gate the menu on status) but be defensive.
        recorder?.stop()

        // Reap old files so /tmp doesn't grow unbounded.
        reapOldRecordings()

        let filename = "recording-\(Int(Date().timeIntervalSince1970)).wav"
        let url = Self.recordingsDir.appendingPathComponent(filename)

        let rec = try AVAudioRecorder(url: url, settings: Self.wavSettings)
        rec.delegate = self
        rec.prepareToRecord()
        guard rec.record() else {
            throw NSError(
                domain: "MyWhi.AudioRecorder",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "AVAudioRecorder.record() returned false"]
            )
        }
        recorder = rec
        recordStartedAt = Date()
    }

    @discardableResult
    func stop() throws -> URL {
        guard let rec = recorder else {
            throw NSError(
                domain: "MyWhi.AudioRecorder",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Recorder is not running"]
            )
        }
        rec.stop()
        let url = rec.url
        // Use AVAudioRecorder.currentTime for sub-second precision; falls
        // back to wall-clock delta if recorder returns 0 (e.g. paused).
        let dur = rec.currentTime
        lastRecordingDuration = dur > 0 ? dur : Date().timeIntervalSince(recordStartedAt ?? Date())
        recorder = nil
        recordStartedAt = nil
        lastRecordingURL = url
        return url
    }

    // MARK: - Cleanup

    /// Remove recordings older than `maxAge`. Called on each start() to
    /// bound disk usage. Cheap because the directory only ever holds a
    /// few recent .wav files (a few hundred KB to a few MB each).
    private func reapOldRecordings() {
        let dir = Self.recordingsDir
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        for url in contents {
            guard url.pathExtension == "wav" else { continue }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            if mtime < cutoff {
                try? fm.removeItem(at: url)
                NSLog("MyWhi.AudioRecorder: reaped old recording \(url.lastPathComponent)")
            }
        }
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // We drive stop() explicitly; this is informational.
        if !flag {
            NSLog("MyWhi: AVAudioRecorder finished unsuccessfully")
        }
    }
}
