// LiveTranscriber.swift
// Phase 8 — partial streaming transcription during recording.
//
// HOW IT WORKS
// During recording the AudioRecorder maintains a rolling buffer of the
// last ~30 seconds of audio at the input sample rate. Every
// `decodeInterval` seconds (default 0.8s), LiveTranscriber:
//
//   1. Snapshots the buffer.
//   2. Writes it to a temp WAV file (16kHz mono, what WhisperKit wants).
//   3. Asks WhisperKit for a decode.
//   4. Fires `onPartial(text)` with the new partial transcript.
//
// The user sees words appear within ~1s of speaking them — close to
// the Wispr Flow experience. The trade-off: each partial decode
// re-processes the entire rolling buffer, so cost grows linearly with
// duration. We cap the buffer at 30 seconds (~1.5s of decode work
// at the small model). For longer recordings, the user just sees
// older text update less frequently.
//
// On `stop()`, the caller (AppState) does the FINAL decode using the
// normal `EngineManager.transcribe(audioPath:)` path against the
// complete file. LiveTranscriber is only for the partial view.

import Foundation
import AVFoundation

@MainActor
final class LiveTranscriber {

    /// How often we run a partial decode. 0.8s gives a nice "typing"
    /// cadence — text updates 1-2 times per second.
    private let decodeInterval: TimeInterval

    private let recorder: AudioRecorder
    private let engineManager: EngineManager
    private weak var appState: AppState?

    private var pollTask: Task<Void, Never>?
    private var lastPartialText: String = ""

    init(
        recorder: AudioRecorder,
        engineManager: EngineManager,
        appState: AppState,
        decodeInterval: TimeInterval = 0.8
    ) {
        self.recorder = recorder
        self.engineManager = engineManager
        self.appState = appState
        self.decodeInterval = decodeInterval
    }

    /// Begin polling. Idempotent — calling while already running is a no-op.
    /// If the user has disabled live streaming in Settings (Phase 8 toggle),
    /// this is a no-op: the final decode on stop is the only transcription.
    func start(model: String, language: String, onPartial: @escaping (String) -> Void) {
        stop()  // cancel any prior task
        guard appState?.settings.liveStreamingEnabled ?? true else {
            NSLog("MyWhi.LiveTranscriber: live streaming disabled in Settings; skipping partial decode loop")
            return
        }
        lastPartialText = ""

        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Wait one interval before the first decode — let some audio
            // accumulate so the result isn't a 100ms fragment.
            try? await Task.sleep(nanoseconds: UInt64(self.decodeInterval * 1_000_000_000))
            while !Task.isCancelled {
                await self.runOnce(model: model, language: language, onPartial: onPartial)
                try? await Task.sleep(nanoseconds: UInt64(self.decodeInterval * 1_000_000_000))
            }
        }
    }

    /// Stop polling. Doesn't run a final decode — that's the caller's
    /// responsibility, since they need to transcribe the FULL file
    /// (not the rolling 30s buffer) for the canonical result.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Internals

    private func runOnce(model: String, language: String, onPartial: (String) -> Void) async {
        let snapshot = recorder.takeLiveSnapshot()
        guard snapshot.samples.count > Int(16_000 * 0.5) else {  // need >= 0.5s
            return
        }

        // Write snapshot to a temp WAV (16kHz mono Int16). Reusing one
        // file avoids spamming /tmp.
        guard let url = writeSnapshotToTempWAV(samples: snapshot.samples, sampleRate: snapshot.sampleRate) else {
            return
        }
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        do {
            let rawText = try await engineManager.transcribe(
                audioPath: url.path,
                model: model,
                language: language
            )
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != lastPartialText else { return }
            lastPartialText = trimmed
            onPartial(trimmed)
        } catch {
            // Partial decode failures are non-fatal — the final decode
            // on stop will retry against the full file. Log quietly.
            NSLog("MyWhi.LiveTranscriber: partial decode failed: \(error.localizedDescription)")
        }
    }

    /// Write a Float32 sample buffer to a temp WAV at 16kHz mono Int16.
    private nonisolated func writeSnapshotToTempWAV(samples: [Float], sampleRate: Double) -> URL? {
        Self.writeSamplesToTempWAV(samples: samples, sampleRate: sampleRate)
    }

    /// Write a Float32 sample buffer to a temp WAV at 16kHz mono Int16.
    /// Exposed as `static` so tests can call it without instantiating
    /// the @MainActor class.
    nonisolated static func writeSamplesToTempWAV(samples: [Float], sampleRate: Double) -> URL? {
        let url = URL(fileURLWithPath: "/tmp/mywhi", isDirectory: true)
            .appendingPathComponent("live-partial-\(UUID().uuidString).wav")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Build the output format at 16kHz Float32 mono (matches
        // WhisperKit's preferred input format).
        guard let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ),
              let inFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
              )
        else { return nil }

        // Resample if the input rate differs from 16kHz.
        let resampled: [Float]
        if abs(sampleRate - 16_000) < 1 {
            resampled = samples
        } else {
            // Build input buffer.
            guard let inBuffer = AVAudioPCMBuffer(
                pcmFormat: inFormat,
                frameCapacity: AVAudioFrameCount(samples.count)
            ) else { return nil }
            let inData = inBuffer.floatChannelData![0]
            for (i, s) in samples.enumerated() {
                inData[i] = s
            }
            inBuffer.frameLength = AVAudioFrameCount(samples.count)

            // Allocate output buffer.
            let expectedOutFrames = AVAudioFrameCount(Double(samples.count) * 16_000.0 / sampleRate + 1024)
            guard let outBuffer = AVAudioPCMBuffer(
                pcmFormat: outFormat,
                frameCapacity: expectedOutFrames
            ) else { return nil }

            guard let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
                return nil
            }

            var consumed = false
            var error: NSError?
            _ = converter.convert(to: outBuffer, error: &error) { _, outStatus in
                if consumed {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                consumed = true
                outStatus.pointee = .haveData
                return inBuffer
            }

            let outCount = Int(outBuffer.frameLength)
            let outData = outBuffer.floatChannelData![0]
            resampled = Array(UnsafeBufferPointer(start: outData, count: outCount))
        }

        // Write WAV file.
        do {
            let file = try AVAudioFile(
                forWriting: url,
                settings: [
                    AVFormatIDKey: Int(kAudioFormatLinearPCM),
                    AVSampleRateKey: 16_000.0,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsNonInterleaved: false,
                ],
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            // Build a buffer from the (possibly resampled) Float32 samples.
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: outFormat,
                frameCapacity: AVAudioFrameCount(resampled.count)
            ) else { return nil }
            let data = buffer.floatChannelData![0]
            for (i, s) in resampled.enumerated() {
                data[i] = s
            }
            buffer.frameLength = AVAudioFrameCount(resampled.count)
            try file.write(from: buffer)
            return url
        } catch {
            NSLog("MyWhi.LiveTranscriber: WAV write failed: \(error)")
            return nil
        }
    }
}