// PythonTranscriber.swift
// Fallback engine — spawns the Python venv + transcribe.py as a child
// process and returns the transcribed text. Used only if the user
// explicitly switches away from WhisperKit (or as a fallback when
// WhisperKit fails to load a model).
//
// transcribe.py wraps faster-whisper (CTranslate2) and reads/writes
// stdout/stderr as plain text. See transcribe.py for the CLI contract.

import Foundation

final class PythonTranscriber: Transcriber, @unchecked Sendable {

    let name = "faster-whisper"

    private let pythonPath: String
    private let scriptPath: String

    init(pythonPath: String) {
        self.pythonPath = pythonPath
        // transcribe.py is bundled into Contents/Resources/ at build time.
        // Bundle.main.resourcePath may be nil in tests, so fall back to the
        // project path used during local dev.
        if let bundled = Bundle.main.path(forResource: "transcribe", ofType: "py") {
            self.scriptPath = bundled
        } else {
            self.scriptPath = "\(NSHomeDirectory())/Documents/MyWhi/transcribe.py"
        }
    }

    /// Python is a stateless invocation — the model is loaded inside the
    /// Python process per call. This is a no-op for parity with the
    /// WhisperKitTranscriber API.
    func loadModel(_ modelName: String) async throws {
        // No-op: Python subprocess loads the model itself.
    }

    /// Run the Python transcribe.py and return the plain text result.
    /// Throws if the process exits non-zero or the script is missing.
    func transcribe(audioPath: String, model: String, language: String) async throws -> String {
        // Capture inputs by value to avoid Sendable issues in the detached task.
        let py = pythonPath
        let script = scriptPath

        return try await Task.detached(priority: .userInitiated) { () -> String in
            try Self.run(
                pythonPath: py,
                scriptPath: script,
                audioPath: audioPath,
                model: model,
                language: language
            )
        }.value
    }

    // MARK: - Process plumbing

    private static func run(
        pythonPath: String,
        scriptPath: String,
        audioPath: String,
        model: String,
        language: String
    ) throws -> String {
        let fm = FileManager.default
        if !fm.fileExists(atPath: pythonPath) {
            throw NSError(
                domain: "MyWhi.PythonTranscriber",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey:
                    "Python interpreter not found at: \(pythonPath). Re-run build.sh to recreate the venv."]
            )
        }
        if !fm.fileExists(atPath: scriptPath) {
            throw NSError(
                domain: "MyWhi.PythonTranscriber",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey:
                    "transcribe.py not found at: \(scriptPath)."]
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [
            scriptPath,
            audioPath,
            "--model", model,
            "--language", language,
        ]

        // Inherit PATH minimally so the venv can find system libs.
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        env["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()

        // Read fully (script is short-lived; output is bounded by audio length).
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            // Surface a trimmed stderr to the UI; full traceback stays in Console.app.
            let trimmed = stderr
                .split(separator: "\n")
                .suffix(20)
                .joined(separator: "\n")
            throw NSError(
                domain: "MyWhi.PythonTranscriber",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey:
                    "Python exited with status \(process.terminationStatus):\n\(trimmed)"]
            )
        }

        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}