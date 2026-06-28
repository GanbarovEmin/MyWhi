import Foundation
import AVFoundation
import ScreenCaptureKit

@MainActor
final class SystemAudioRecorder: NSObject, ObservableObject {
    enum RecorderState: Equatable {
        case idle
        case recording
        case unavailable(String)
    }

    @Published private(set) var state: RecorderState = .idle

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private let queue = DispatchQueue(label: "az.isupport.mywhi.system-audio")
    private var currentURL: URL?
    private var didStartSession = false

    static var recordingsDir: URL {
        let url = URL(fileURLWithPath: "/tmp/mywhi", isDirectory: true)
            .appendingPathComponent("meetings", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func start() async throws -> URL {
        stopDiscardingWriter()

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first else {
            state = .unavailable("No display available for system audio capture.")
            throw NSError(
                domain: "MyWhi.SystemAudioRecorder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No display available for system audio capture."]
            )
        }

        let url = Self.recordingsDir
            .appendingPathComponent("system-\(Int(Date().timeIntervalSince1970)).m4a")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000,
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw NSError(
                domain: "MyWhi.SystemAudioRecorder",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Cannot create system audio writer input."]
            )
        }
        writer.add(input)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)

        self.writer = writer
        self.input = input
        self.stream = stream
        self.currentURL = url
        self.didStartSession = false

        try await stream.startCapture()
        state = .recording
        return url
    }

    func stop() async -> URL? {
        let url = currentURL
        let stream = stream
        self.stream = nil
        currentURL = nil
        state = .idle

        try? await stream?.stopCapture()

        guard let writer else {
            stopDiscardingWriter()
            return url
        }
        input?.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
        self.writer = nil
        self.input = nil
        didStartSession = false
        return url.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    func cancel() {
        Task { @MainActor in
            let url = currentURL
            try? await stream?.stopCapture()
            stopDiscardingWriter()
            if let url {
                try? FileManager.default.removeItem(at: url)
            }
            state = .idle
        }
    }

    private func stopDiscardingWriter() {
        writer?.cancelWriting()
        writer = nil
        input = nil
        stream = nil
        currentURL = nil
        didStartSession = false
    }
}

extension SystemAudioRecorder: SCStreamOutput, SCStreamDelegate {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio, sampleBuffer.isValid else { return }
        Task { @MainActor in
            guard let writer, let input else { return }
            if writer.status == .unknown {
                writer.startWriting()
                writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
                didStartSession = true
            }
            guard writer.status == .writing, didStartSession, input.isReadyForMoreMediaData else { return }
            _ = input.append(sampleBuffer)
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.state = .unavailable(error.localizedDescription)
        }
    }
}
