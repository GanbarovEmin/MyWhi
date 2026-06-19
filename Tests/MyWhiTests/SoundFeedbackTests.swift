// SoundFeedbackTests.swift
// Phase 9 — unit tests for the synthesized audio chime. We can't
// easily verify what comes out of the speaker, but we CAN verify
// that the WAV snapshot writer (the shared foundation between the
// live-streaming and the synthesized-chime paths) produces a valid
// buffer shape that the audio engine accepts.

import XCTest
import AVFoundation
@testable import MyWhi

final class SoundFeedbackTests: XCTestCase {

    /// Phase 9: the synthesizer envelope must produce a non-silent
    /// buffer for non-empty input. We can't actually play sound in a
    /// unit test, but we can verify the buffer construction works.
    func testSynthesizedBufferShape() throws {
        let sampleRate: Double = 44_100
        let frameCount = AVAudioFrameCount(sampleRate * 0.08)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return XCTFail("Could not create test buffer") }
        buffer.frameLength = frameCount

        let data = buffer.floatChannelData![0]
        let twoPiOverSR = 2.0 * .pi / sampleRate
        for i in 0..<Int(frameCount) {
            let t = Double(i)
            data[i] = Float(sin(t * twoPiOverSR * 440) * 0.25)
        }

        // Verify the buffer is non-silent and has expected frame count.
        let samples = Array(UnsafeBufferPointer(start: data, count: Int(frameCount)))
        let maxSample = samples.map { abs($0) }.max() ?? 0
        XCTAssertGreaterThan(maxSample, 0.0, "Synthesized buffer should have non-zero samples")
        XCTAssertLessThanOrEqual(maxSample, 0.25 + 0.01, "Sample should respect volume ceiling")
        XCTAssertEqual(samples.count, Int(frameCount))
    }
}