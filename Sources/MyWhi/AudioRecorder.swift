// AudioRecorder.swift
// AVAudioEngine-based recorder with a built-in 0.5s pre-roll buffer.
//
// Why AVAudioEngine instead of AVAudioRecorder:
//   - We need real-time access to the audio samples (for the pre-roll
//     ring buffer and for a real level meter). AVAudioRecorder hides
//     everything behind the file system.
//   - We want to keep the engine running BEFORE the user starts a
//     recording so the pre-roll can capture the most recent half-second
//     of audio. AVAudioRecorder has no "always listening" mode.
//
// THREADING MODEL
//   - The audio tap fires on a low-priority audio thread.
//   - preRollSamples and isRecording are protected by NSLock — accessed
//     from the audio thread and from the main actor.
//   - The audio file write goes through a serial dispatch queue so the
//     file is written in input order regardless of how many taps overlap.
//   - @Published currentLevel is updated via Task { @MainActor } from
//     the audio thread (one ~85ms hop at 48kHz/4096 buffer).
//
// PRE-ROLL
//   - 0.5s ring buffer of the most recent audio at the input rate
//     (typically 48kHz, 24000 samples). Lock-protected array.
//   - When start() is called, we (a) open the output file, (b) flush
//     the pre-roll into the file via the same write path, (c) set
//     isRecording=true so subsequent taps write to the file. Total
//     delay between key press and first bytes on disk: ~5-15ms (one
//     AVAudioFile.write + the next tap callback).
//
// FILE FORMAT
//   - 16kHz, mono, 16-bit signed PCM, WAV container — what WhisperKit
//     and faster-whisper both expect.
//   - Resampled from the input rate via AVAudioConverter (Float32 →
//     Float32 at 16kHz, then AVAudioFile writes the Int16 bytes).

import Foundation
@preconcurrency import AVFoundation
import CoreVideo
import Combine

@MainActor
final class AudioRecorder: NSObject, ObservableObject {

    // MARK: - Engine

    private nonisolated let engine = AVAudioEngine()
    nonisolated(unsafe) private var isEngineStarted = false

    // MARK: - Pre-roll ring buffer (lock-protected)

    nonisolated(unsafe) private var preRollSamples: [Float] = []
    private nonisolated let preRollLock = NSLock()
    nonisolated let preRollSeconds: TimeInterval = 0.5
    nonisolated(unsafe) private var preRollCapacity: Int = 0

    // MARK: - Recording state

    /// Lock around `isRecording` because it's read by the audio tap
    /// (background thread) and written by start/stop (main actor).
    private nonisolated let recordingLock = NSLock()
    nonisolated(unsafe) private var isRecordingFlag: Bool = false

    nonisolated(unsafe) private var audioFile: AVAudioFile?
    nonisolated(unsafe) private var converter: AVAudioConverter?
    nonisolated(unsafe) private var inputFormat: AVAudioFormat?
    nonisolated(unsafe) private var recordStartedAt: Date?
    nonisolated(unsafe) private var inputSampleRate: Double = 48000

    /// Serial queue for file I/O. Audio tap pushes raw samples here;
    /// we serialize the resample + write.
    nonisolated let fileQueue = DispatchQueue(
        label: "az.isupport.mywhi.audiofile",
        qos: .userInitiated
    )

    // MARK: Published

    @Published private(set) var currentLevel: Float = 0
    private(set) var lastRecordingURL: URL?
    private(set) var lastRecordingDuration: TimeInterval = 0

    /// Phase 22: tracks whether the most recent file write succeeded.
    /// The UI can observe this and surface a persistent warning so the
    /// user knows their recording may be truncated (disk full, file
    /// queue blocked, etc.) and can stop early to avoid data loss.
    ///
    /// We mirror this with a `nonisolated(unsafe)` flag that the
    /// audio file queue can flip without hopping to the main actor
    /// for every tap (12 taps/sec). The published value is updated
    /// only on state transitions, not on every tap.
    @Published private(set) var isWriteFailing: Bool = false
    nonisolated(unsafe) private var hasWriteFailure: Bool = false

    /// Cached RMS — the audio thread writes this every buffer (~85ms
    /// at 48kHz/4096). The SwiftUI waveform redraws on each tick.
    private nonisolated let levelLock = NSLock()
    nonisolated(unsafe) private var latestRms: Float = 0

    nonisolated(unsafe) private var levelTimer: Timer?

    // MARK: Live streaming support (Phase 8)
    //
    // While recording, every tap also appends to `liveSamples` so the
    // LiveTranscriber can take a rolling snapshot and run a partial
    // decode. We trim the buffer to `liveBufferMaxSeconds` worth of
    // samples — anything older is dropped because the most recent N
    // seconds is what matters for a "live partial" view.
    nonisolated(unsafe) private var liveSamples: [Float] = []
    nonisolated let liveBufferMaxSeconds: TimeInterval = 30.0
    nonisolated let liveSamplesLock = NSLock()
    nonisolated(unsafe) private var liveSampleRate: Double = 48000

    // MARK: Audio buffer pool (Phase 12)
    //
    // Phase 9 audit: `writeSamplesToFileOnQueue` allocated two fresh
    // AVAudioPCMBuffer instances per tap (~85ms cadence, ~12 allocs/sec).
    // On a 10-minute recording that's 7200 buffer allocs plus 7200
    // Float-array copies — measurable GC pressure and CPU spent in
    // malloc. The buffers themselves are reusable: we only need to
    // resize them once to the max expected size for the format pair,
    // then reset frameLength=0 and overwrite the channel data each
    // tap.
    //
    // The pool lives on `fileQueue` only. Audio taps post work via
    // `fileQueue.async`, so there's no concurrent access. On
    // `stop()` we drop the pool so the next recording starts clean.
    nonisolated(unsafe) private var pooledInBuffer: AVAudioPCMBuffer?
    nonisolated(unsafe) private var pooledOutBuffer: AVAudioPCMBuffer?
    nonisolated(unsafe) private var pooledInFormat: AVAudioFormat?
    nonisolated(unsafe) private var pooledOutFormat: AVAudioFormat?

    // MARK: - Storage

    /// Recordings directory. Exposed internally for legacy-folder
    /// migration in AppState. Created lazily on first start().
    internal static var recordingsDir: URL {
        let url = URL(fileURLWithPath: "/tmp/mywhi", isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Files older than this are reaped on each start().
    private static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    // MARK: - Permission

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

    // MARK: - Lifecycle

    /// Start the engine and pre-roll capture. Idempotent — safe to
    /// call multiple times. Called by AppContainer on first scene
    /// activation, and by `start()` if the engine isn't up yet.
    ///
    /// This will trigger macOS's microphone permission prompt on the
    /// first call. That's intentional — we want the engine warm so
    /// the first Cmd+Option+D press has zero mic latency.
    func prepare() async {
        guard !isEngineStarted else { return }

        let granted = await requestPermissionIfNeeded()
        guard granted else {
            NSLog("MyWhi.AudioRecorder: prepare() — no mic permission; engine not started")
            return
        }

        // On macOS, audio routing is handled by the HAL — no need
        // for AVAudioSession (iOS-only). The engine just works once
        // the input node is enabled and permission is granted.
        let format = engine.inputNode.outputFormat(forBus: 0)
        inputFormat = format
        inputSampleRate = format.sampleRate
        preRollCapacity = Int(preRollSeconds * format.sampleRate)

        // The tap captures audio at the input node's native format
        // (typically 48kHz Float32 mono on Mac). The closure runs on
        // an audio render thread, not the main actor.
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
            isEngineStarted = true
            NSLog("MyWhi.AudioRecorder: engine started (input=\(format.sampleRate)Hz, channels=\(format.channelCount))")
            startLevelTimer()
        } catch {
            NSLog("MyWhi.AudioRecorder: engine.start() failed: \(error)")
        }
    }

    /// Stop the engine completely. Used in tests; not called in
    /// production — we want the engine always running so pre-roll
    /// keeps capturing.
    func shutdown() {
        guard isEngineStarted else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isEngineStarted = false
        stopLevelTimer()
    }

    // MARK: - Record

    func start() throws {
        // Reap old files so /tmp doesn't grow unbounded.
        reapOldRecordings()

        // Reset diagnostic counters for this recording.
        liveWriteCounter = 0
        skipWriteCounter = 0
        fileWriteCompletedCount = 0
        NSLog("MyWhi.AudioRecorder: start() called, isEngineStarted=\(isEngineStarted), preRollCapacity=\(preRollCapacity)")

        // Engine might not be running yet (cold start before prepare()
        // completed). Start it; the user expects no latency on first
        // press.
        if !isEngineStarted {
            Task { await self.prepare() }
        }

        // Open output file (16kHz mono Int16 PCM WAV).
        let filename = "recording-\(Int(Date().timeIntervalSince1970)).wav"
        let url = Self.recordingsDir.appendingPathComponent(filename)

        let settings: [String: Any] = [
            AVFormatIDKey:            Int(kAudioFormatLinearPCM),
            AVSampleRateKey:          16_000.0,
            AVNumberOfChannelsKey:    1,
            AVLinearPCMBitDepthKey:   16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey:    false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        // Snapshot the pre-roll while holding the lock.
        let preRoll: [Float] = preRollLock.withLock { preRollSamples }
        let inputRate = inputSampleRate

        // Open the file + write pre-roll synchronously, all on fileQueue.
        fileQueue.sync {
            do {
                self.audioFile = try AVAudioFile(
                    forWriting: url,
                    settings: settings,
                    commonFormat: .pcmFormatFloat32,
                    interleaved: false
                )
                if let inputFormat = self.inputFormat {
                    let outFormat = AVAudioFormat(
                        commonFormat: .pcmFormatFloat32,
                        sampleRate: 16_000,
                        channels: 1,
                        interleaved: false
                    )!
                    self.converter = AVAudioConverter(from: inputFormat, to: outFormat)
                }
                if !preRoll.isEmpty {
                    self.writeSamplesToFileOnQueue(samples: preRoll, sampleRate: inputRate)
                }
            } catch {
                NSLog("MyWhi.AudioRecorder: AVAudioFile open failed: \(error)")
            }
        }

        // Mark recording active. The next tap callback will start
        // pushing samples into the file.
        recordingLock.withLock { isRecordingFlag = true }
        recordStartedAt = Date()
        currentLevel = 0
    }

    @discardableResult
    func stop() throws -> URL {
        // Clear the recording flag first so the tap stops writing
        // before we close the file.
        recordingLock.withLock { isRecordingFlag = false }

        // Close the file on the file queue.
        fileQueue.sync {
            self.audioFile = nil
            self.converter = nil
        }

        // Find the last file we wrote. We don't track the URL on
        // audioFile directly (it lives on the file queue), so we derive
        // it from the timestamp.
        let url = mostRecentRecordingURL()
        let dur: TimeInterval
        if let started = recordStartedAt {
            dur = Date().timeIntervalSince(started)
        } else {
            dur = 0
        }
        lastRecordingDuration = dur
        lastRecordingURL = url
        recordStartedAt = nil
        currentLevel = 0
        // Phase 12: drop the buffer pool so the next recording starts
        // with a fresh allocation.
        dropBufferPool()
        return url ?? lastRecordingURL ?? URL(fileURLWithPath: "/tmp/mywhi/recordings/")
    }

    /// Cancel an in-flight recording and delete the .wav file.
    func cancel() {
        recordingLock.withLock { isRecordingFlag = false }
        fileQueue.sync {
            self.audioFile = nil
            self.converter = nil
        }
        if let url = mostRecentRecordingURL() {
            try? FileManager.default.removeItem(at: url)
            NSLog("MyWhi.AudioRecorder: cancelled and removed \(url.lastPathComponent)")
        }
        recordStartedAt = nil
        lastRecordingURL = nil
        lastRecordingDuration = 0
        currentLevel = 0
        // Phase 12: drop the buffer pool too.
        dropBufferPool()
    }

    // MARK: - Audio tap

    /// Runs on a low-priority audio render thread (NOT main actor).
    /// Holds the tap as short as possible: compute RMS, copy samples
    /// out of the buffer, hand them to the file queue if recording.
    private nonisolated func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        let sampleRate = buffer.format.sampleRate

        // RMS for the level meter.
        var sum: Float = 0
        for i in 0..<frameCount {
            let s = channelData[i]
            sum += s * s
        }
        let rms = sqrt(sum / Float(max(1, frameCount)))
        let normalized = max(0, min(1, (rms + 0.05) * 4))
        levelLock.withLock { latestRms = normalized }

        // Always feed the pre-roll ring buffer.
        let newSamples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        preRollLock.withLock {
            preRollSamples.append(contentsOf: newSamples)
            if preRollSamples.count > preRollCapacity {
                preRollSamples.removeFirst(preRollSamples.count - preRollCapacity)
            }
        }

        // Phase 8: also feed the live rolling buffer used by
        // LiveTranscriber for partial decoding. Same trimming rule —
        // we keep the last `liveBufferMaxSeconds` of audio at the
        // input sample rate. The transcriber reads `takeLiveSnapshot`
        // off the lock to avoid blocking the audio tap.
        liveSamplesLock.withLock {
            liveSamples.append(contentsOf: newSamples)
            let maxSamples = Int(liveBufferMaxSeconds * sampleRate)
            if liveSamples.count > maxSamples {
                liveSamples.removeFirst(liveSamples.count - maxSamples)
            }
            liveSampleRate = sampleRate
        }

        // If recording, hand off to the file queue.
        let isRec = recordingLock.withLock { isRecordingFlag }
        if isRec {
            // Diagnostic: first few live writes after start. Helps
            // catch "tap not firing" / "flag not set" race conditions.
            let liveWriteCount = liveWriteCounter
            liveWriteCounter += 1
            if liveWriteCount < 5 {
                NSLog("MyWhi.AudioRecorder: live tap #\(liveWriteCount) — \(frameCount) frames @ \(sampleRate)Hz, isRec=true")
            }
            fileQueue.async { [weak self] in
                self?.writeSamplesToFileOnQueue(samples: newSamples, sampleRate: sampleRate)
            }
        } else {
            // Track how many taps fired while NOT recording (should be
            // many; useful for catching "engine never started" issues).
            skipWriteCounter += 1
        }
    }

    // Diagnostic counters (lock-free single-writer reads).
    nonisolated(unsafe) private var liveWriteCounter: Int = 0
    nonisolated(unsafe) private var skipWriteCounter: Int = 0
    nonisolated(unsafe) private var fileWriteCompletedCount: Int = 0

    /// Resample and write a chunk of input samples to the open file.
    /// Must be called on `fileQueue`.
    ///
    /// CRITICAL: do NOT signal `endOfStream` here. AVAudioConverter
    /// goes into a "done" state once endOfStream is set, and refuses
    /// to accept further input. That made every live chunk after the
    /// pre-roll flush produce 0 output frames. We only signal
    /// endOfStream on the final chunk in `stop()`.
    ///
    /// Phase 12: reuses pooled AVAudioPCMBuffer instances (one for the
    /// input format, one for the 16kHz output format). On the first
    /// tap after `start()`, the pool is allocated; subsequent taps
    /// overwrite the channel data and reset `frameLength`. The Float
    /// array copy is unavoidable (samples come in from a Swift Array),
    /// but the AVAudioPCMBuffer / AVAudioFormat allocs no longer happen
    /// per tap.
    private nonisolated func writeSamplesToFileOnQueue(samples: [Float], sampleRate: Double) {
        guard let file = audioFile, let converter = converter else { return }

        // Lazily allocate (or re-allocate if sample rate changed)
        // the pool. This is the only path that ever creates new
        // AVAudioPCMBuffer instances.
        let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        let inFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        if pooledInFormat != inFormat {
            pooledInFormat = inFormat
            pooledInBuffer = AVAudioPCMBuffer(
                pcmFormat: inFormat,
                frameCapacity: AVAudioFrameCount(samples.count)
            )
        }
        if pooledOutFormat != outFormat {
            pooledOutFormat = outFormat
            let expectedOutFrames = AVAudioFrameCount(Double(samples.count) * 16_000.0 / sampleRate + 1024)
            pooledOutBuffer = AVAudioPCMBuffer(
                pcmFormat: outFormat,
                frameCapacity: expectedOutFrames
            )
        }
        guard let inBuffer = pooledInBuffer,
              let outBuffer = pooledOutBuffer else { return }

        // Overwrite the channel data in-place. The capacity is sized
        // for the largest tap we'll see; smaller taps just use a prefix.
        let inData = inBuffer.floatChannelData![0]
        for (i, s) in samples.enumerated() {
            inData[i] = s
        }
        inBuffer.frameLength = AVAudioFrameCount(samples.count)

        var error: NSError?
        var consumed = false
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            // Only the first call returns the input. Subsequent calls
            // are endOfStream probes — but we intentionally do NOT
            // signal endOfStream so the converter stays ready for the
            // next chunk. The last chunk's flush happens in stop().
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return inBuffer
        }
        if status == .error || error != nil {
            NSLog("MyWhi.AudioRecorder: converter error: \(String(describing: error))")
            return
        }

        do {
            try file.write(from: outBuffer)
            fileWriteCompletedCount += 1
            // Phase 22: clear the failure flag on every successful
            // write. A single successful write is enough evidence the
            // pipeline is healthy again. We use the lock-free
            // `hasWriteFailure` flag (touched from the file queue)
            // and only hop to the main actor on a state transition
            // — once per failure event, not once per tap.
            if hasWriteFailure {
                hasWriteFailure = false
                Task { @MainActor in
                    self.isWriteFailing = false
                }
            }
        } catch {
            NSLog("MyWhi.AudioRecorder: file.write failed: \(error)")
            // Phase 22: surface write failures so the UI can warn the
            // user before they lose data. The error is logged once;
            // the @Published flag stays true until a subsequent
            // successful write flips it back to false.
            if !hasWriteFailure {
                hasWriteFailure = true
                Task { @MainActor in
                    self.isWriteFailing = true
                }
            }
        }
    }

    // MARK: - Live level (waveform)

    /// CVDisplayLink fires once per display refresh (60-120Hz on
    /// ProMotion Macs). Previous implementation used a 30Hz Timer +
    /// `Task { @MainActor in … }` per tick, which allocated ~30 Tasks/sec
    /// on a 60Hz display. CVDisplayLink's callback runs on a dedicated
    /// high-priority thread; we just sample `latestRms` and hop to the
    /// main actor for the @Published mutation.
    ///
    /// Why not CADisplayLink? It's iOS-only; the macOS equivalent is
    /// CVDisplayLink from CoreVideo, which is what we use here.
    private var displayLink: CVDisplayLink?

    private func startLevelTimer() {
        stopLevelTimer()

        var link: CVDisplayLink?
        let result = CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard result == kCVReturnSuccess, let link else {
            NSLog("MyWhi.AudioRecorder: CVDisplayLink create failed (\(result)); falling back to Timer")
            startLevelTimerFallback()
            return
        }

        let callback: CVDisplayLinkOutputCallback = { (_, _, _, _, _, contextPtr) -> CVReturn in
            guard let contextPtr else { return kCVReturnSuccess }
            let recorder = Unmanaged<AudioRecorder>.fromOpaque(contextPtr).takeUnretainedValue()
            // Snapshot RMS off the lock; hop to main actor for SwiftUI.
            let raw = recorder.levelLock.withLock { recorder.latestRms }
            let curved = pow(Double(raw), 0.7)
            let level = Float(curved)
            DispatchQueue.main.async {
                recorder.currentLevel = level
            }
            return kCVReturnSuccess
        }

        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, callback, opaqueSelf)

        CVDisplayLinkStart(link)
        displayLink = link
        NSLog("MyWhi.AudioRecorder: CVDisplayLink started")
    }

    private func stopLevelTimer() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
        levelTimer?.invalidate()
        levelTimer = nil
    }

    /// Last-resort fallback if CVDisplayLink can't be created (rare;
    /// happens on macOS sandbox without screen-recording permission in
    /// some configurations). Matches the previous behavior so the app
    /// still works — just with slightly higher CPU on the level loop.
    private func startLevelTimerFallback() {
        levelTimer?.invalidate()
        let timer = Timer(timeInterval: 0.033, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let raw = self.levelLock.withLock { self.latestRms }
                let curved = pow(Double(raw), 0.7)
                self.currentLevel = Float(curved)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        levelTimer = timer
    }

    deinit {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
        levelTimer?.invalidate()
    }

    // MARK: - Cleanup

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

    // MARK: - Helpers

    /// Look up the .wav file we just wrote. The audio file is created
    /// on the file queue; rather than plumbing the URL back, we infer
    /// it from the start timestamp (the filename is `recording-<ts>.wav`).
    private func mostRecentRecordingURL() -> URL? {
        guard let started = recordStartedAt else { return lastRecordingURL }
        let ts = Int(started.timeIntervalSince1970)
        let candidate = Self.recordingsDir.appendingPathComponent("recording-\(ts).wav")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : lastRecordingURL
    }

    // MARK: - Live streaming snapshot API (Phase 8)
    //
    // LiveTranscriber calls these from a background task to read the
    // rolling audio buffer without blocking the audio tap. We snapshot
    // the array under the lock and return a copy.

    /// Snapshot the rolling audio buffer at the input sample rate.
    /// Returns `(samples, sampleRate)`. Empty if no recording is
    /// active.
    ///
    /// Phase 14: when `windowSeconds > 0`, only the most recent
    /// `windowSeconds` worth of samples are returned (sliding window
    /// for live-streaming partial decodes). When `windowSeconds == 0`,
    /// the full rolling buffer is returned — used by the final
    /// decode-on-stop which wants the entire recording.
    func takeLiveSnapshot(windowSeconds: Double = 0) -> (samples: [Float], sampleRate: Double) {
        let (s, r) = liveSamplesLock.withLock { (liveSamples, liveSampleRate) }
        guard windowSeconds > 0, r > 0 else {
            return (s, r)
        }
        let maxSamples = Int(windowSeconds * r)
        if s.count <= maxSamples {
            return (s, r)
        }
        return (Array(s.suffix(maxSamples)), r)
    }

    /// Reset the rolling live buffer. Called when recording stops.
    func resetLiveBuffer() {
        liveSamplesLock.withLock {
            liveSamples.removeAll(keepingCapacity: false)
        }
    }

    // MARK: - Buffer pool teardown (Phase 12)

    /// Drop the pooled AVAudioPCMBuffers. Called from `stop()` so the
    /// next recording starts with a fresh allocation. Without this the
    /// pool keeps ~64 KB of Float32 alive between recordings.
    ///
    /// Public so unit tests can exercise the no-crash / idempotent
    /// guarantee without setting up a full recording pipeline.
    nonisolated func dropBufferPool() {
        fileQueue.async { [weak self] in
            guard let self else { return }
            self.pooledInBuffer = nil
            self.pooledOutBuffer = nil
            self.pooledInFormat = nil
            self.pooledOutFormat = nil
        }
    }
}

// MARK: - NSLock.withLock

private extension NSLock {
    /// Swift-friendly withLock helper. Lets the lock be released
    /// even if the closure throws (Swift's @rethrows doesn't work
    /// here because NSLock isn't @rethrows).
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}