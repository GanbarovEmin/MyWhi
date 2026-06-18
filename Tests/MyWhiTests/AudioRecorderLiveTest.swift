import XCTest
import AVFoundation
@testable import MyWhi

/// Reproduce the user's "live audio not captured" issue.
/// Engine starts → wait 200ms → start() → wait 500ms → stop() → check file.
///
/// If the file is only ~0.5s (the pre-roll), live audio is broken.
@MainActor
final class AudioRecorderLiveTest: XCTestCase {

    func testLiveAudioReachesFile() async throws {
        let recorder = AudioRecorder()
        defer { recorder.shutdown() }

        // Make sure we have mic permission. If not, skip the test —
        // we can't programmatically grant it from XCTest.
        let granted = await recorder.requestPermissionIfNeeded()
        try XCTSkipUnless(granted, "Microphone permission not granted; cannot run live test.")

        print("[Test] preparing engine…")
        await recorder.prepare()

        // Wait for the engine to actually start and capture some pre-roll.
        try await Task.sleep(nanoseconds: 300_000_000)
        print("[Test] engine should be running now")

        print("[Test] starting recording…")
        try recorder.start()

        // Speak-nothing window — but the tap should still be writing
        // audio buffers to the file. We verify by file duration.
        try await Task.sleep(nanoseconds: 500_000_000)
        print("[Test] stopping…")
        let url = try recorder.stop()

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs[.size] as? Int ?? 0
        print("[Test] file: \(url.lastPathComponent), size: \(size) bytes")

        // Use afinfo to get duration
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/afinfo")
        task.arguments = [url.path]
        let pipe = Pipe()
        task.standardOutput = pipe
        try task.run()
        task.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let durLine = output.split(separator: "\n").first(where: { $0.contains("duration") }) ?? ""
        print("[Test] \(durLine)")

        // 500ms of sleep + pre-roll (~0.5s) = at least ~1s of audio.
        // If we see ~0.5s, live audio was lost.
        let durationSeconds = parseDuration(durLine)
        print("[Test] parsed duration: \(durationSeconds)s")
        XCTAssertGreaterThan(durationSeconds, 0.7,
                             "Expected >0.7s of audio (0.5s pre-roll + 0.5s live), got \(durationSeconds)s")
    }

    private func parseDuration(_ line: Substring) -> Double {
        // "estimated duration: 0.834 sec"
        let pattern = "duration: "
        guard let range = line.range(of: pattern) else { return 0 }
        let rest = line[range.upperBound...]
        let parts = rest.split(separator: " ")
        if let first = parts.first, let d = Double(first) { return d }
        return 0
    }
}