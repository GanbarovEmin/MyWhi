// AudioRecorder.swift
// Thin wrapper around AVAudioRecorder. Produces 16 kHz mono PCM WAV
// (the format faster-whisper expects). All recorder interaction is on
// the main actor; AVFoundation's audio thread handles the actual IO.

import Foundation
import AVFoundation

@MainActor
final class AudioRecorder: NSObject, ObservableObject {

    private var recorder: AVAudioRecorder?
    private(set) var lastRecordingURL: URL?

    /// Wav files land here. Created lazily on first start().
    private static var recordingsDir: URL {
        let url = URL(fileURLWithPath: "/tmp/hermes-dictate", isDirectory: true)
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

        let filename = "recording-\(Int(Date().timeIntervalSince1970)).wav"
        let url = Self.recordingsDir.appendingPathComponent(filename)

        let rec = try AVAudioRecorder(url: url, settings: Self.wavSettings)
        rec.delegate = self
        rec.prepareToRecord()
        guard rec.record() else {
            throw NSError(
                domain: "HermesDictate.AudioRecorder",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "AVAudioRecorder.record() returned false"]
            )
        }
        recorder = rec
    }

    @discardableResult
    func stop() throws -> URL {
        guard let rec = recorder else {
            throw NSError(
                domain: "HermesDictate.AudioRecorder",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Recorder is not running"]
            )
        }
        rec.stop()
        let url = rec.url
        recorder = nil
        lastRecordingURL = url
        return url
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // We drive stop() explicitly; this is informational.
        if !flag {
            NSLog("HermesDictate: AVAudioRecorder finished unsuccessfully")
        }
    }
}
