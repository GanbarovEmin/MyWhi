// LiveTranscriberTests.swift
// Phase 8 — unit tests for the partial-streaming decode path. We don't
// load WhisperKit here (that requires models); we test the snapshot
// WAV-writer, which is the part of LiveTranscriber with non-trivial
// logic that doesn't depend on a loaded model.

import XCTest
import AVFoundation
@testable import MyWhi

final class LiveTranscriberTests: XCTestCase {

    /// Phase 8: snapshot writer must produce a non-empty 16kHz mono
    /// WAV from a Float32 mono buffer at the input rate.
    func testSnapshotWAVIsProducedAndReadable() throws {
        // 1 second of silence at 48kHz mono Float32.
        let samples = [Float](repeating: 0, count: 48_000)
        let url = LiveTranscriber.writeSamplesToTempWAV(
            samples: samples,
            sampleRate: 48_000
        )
        XCTAssertNotNil(url, "Snapshot URL should not be nil")
        guard let url else { return }
        defer { try? FileManager.default.removeItem(at: url) }

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 44, "WAV should be larger than the header")

        // Verify it's a well-formed 16kHz mono file.
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.processingFormat.sampleRate, 16_000, accuracy: 0.5)
        XCTAssertEqual(file.processingFormat.channelCount, 1)
    }

    /// Phase 8: empty input must produce a valid (small) WAV, not crash.
    func testEmptySamplesProducesEmptyWAV() throws {
        let url = LiveTranscriber.writeSamplesToTempWAV(samples: [], sampleRate: 48_000)
        XCTAssertNotNil(url)
        guard let url else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 44, "Even empty WAV must have the 44-byte header")
    }

    /// Phase 8: 16kHz passthrough must work (no resampling).
    func testPassthroughAt16kHz() throws {
        // 0.5s of a 440Hz sine wave at 16kHz.
        let sr: Double = 16_000
        let samples = (0..<8_000).map { i in
            Float(sin(2.0 * .pi * 440 * Double(i) / sr))
        }
        let url = LiveTranscriber.writeSamplesToTempWAV(samples: samples, sampleRate: sr)
        XCTAssertNotNil(url)
        guard let url else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.processingFormat.sampleRate, 16_000, accuracy: 0.5)
        XCTAssertGreaterThan(file.length, 0)
    }
}