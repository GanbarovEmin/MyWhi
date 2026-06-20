// SoundFeedback.swift
// Soft audio chimes played at recording start and stop. Synthesized
// in-process so the .app bundle doesn't have to ship .aiff files.
//
// Phase 9: Phase 9 polish — sound is a meaningful UX cue alongside
// haptic feedback, especially for users on Macs without force-touch
// trackpads where NSHapticFeedbackManager is a silent no-op.
//
// Two tones:
//   - start: 880 Hz triangle, 60ms with quick attack/decay envelope
//   - stop:  440 Hz triangle, 80ms
//
// Both are below 90ms — a chime, not a beep. Volume is intentionally
// low (~0.25) so it doesn't startle.
//
// Why synthesize rather than ship a file:
//   - Zero asset bundle cost.
//   - Easy to tweak (frequency, duration, envelope) without rebuilding
//     the .icns/.aiff pipeline.
//   - Works even if the .app is moved between machines.
//
// Implementation note: AVAudioEngine + AVAudioPlayerNode is overkill
// for a one-shot 80ms sine. AVAudioPlayer on a generated NSData buffer
// works too but pulls in CoreAudio. AVAudioEngine with a one-shot
// source node is the modern, simple path — and we already link it.

import Foundation
@preconcurrency import AVFoundation

@MainActor
enum SoundFeedback {

    /// Play a short high tone — recording just started.
    static func playStart() {
        playSynthesized(frequency: 880, duration: 0.06, volume: 0.25)
    }

    /// Play a short low tone — recording just stopped.
    static func playStop() {
        playSynthesized(frequency: 440, duration: 0.08, volume: 0.25)
    }

    // MARK: - Synthesizer

    private static func playSynthesized(frequency: Double, duration: Double, volume: Float) {
        let sampleRate: Double = 44_100
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return }
        buffer.frameLength = frameCount

        let data = buffer.floatChannelData![0]
        let twoPiOverSR = 2.0 * .pi / sampleRate

        // Quick attack (5ms) + exponential decay envelope so the chime
        // doesn't click on start or end.
        let attackFrames = Int(0.005 * sampleRate)
        for i in 0..<Int(frameCount) {
            let t = Double(i)
            let envelope: Double
            if i < attackFrames {
                envelope = Double(i) / Double(attackFrames)
            } else {
                let progress = Double(i - attackFrames) / Double(Int(frameCount) - attackFrames)
                envelope = exp(-3.0 * progress)
            }
            let sample = sin(t * twoPiOverSR * frequency) * envelope * Double(volume)
            data[i] = Float(sample)
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: [.interrupts]) { [weak engine] in
                // Stop the engine once the buffer has played out to free
                // the audio session. Dispatch off-main because the
                // completion handler runs on an audio thread.
                DispatchQueue.main.async {
                    engine?.stop()
                    engine?.reset()
                }
            }
            player.play()
        } catch {
            NSLog("MyWhi.SoundFeedback: synth play failed: \(error)")
            // Best effort — fail silently. The user still has haptic.
        }
    }
}
