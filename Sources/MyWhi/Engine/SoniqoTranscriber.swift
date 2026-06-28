import Foundation

final class SoniqoTranscriber: Transcriber, @unchecked Sendable {
    let name = "Soniqo Speech"

    func loadModel(_ modelName: String) async throws {
        guard Self.findSpeechCLI() != nil else {
            throw NSError(
                domain: "MyWhi.SoniqoTranscriber",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Soniqo speech CLI is not installed. Run: brew install speech"]
            )
        }
    }

    func transcribe(audioPath: String, model: String, language: String) async throws -> String {
        try await Self.transcribeFile(
            URL(fileURLWithPath: audioPath),
            model: model,
            language: language,
            context: nil
        )
    }

    static func transcribeFile(
        _ url: URL,
        model: String,
        language: String,
        context: String?
    ) async throws -> String {
        guard let speech = findSpeechCLI() else {
            throw NSError(
                domain: "MyWhi.SoniqoTranscriber",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Soniqo speech CLI is not installed. Run: brew install speech"]
            )
        }

        var args = ["transcribe", url.path]
        args.append(contentsOf: cliArgs(for: model))

        if language != "auto", !language.isEmpty {
            args.append(contentsOf: ["--language", language])
        }
        if let context, !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args.append(contentsOf: ["--context", context])
        }

        let output = try await runSpeechCLI(executable: speech, arguments: args)
        return cleanTranscriptOutput(output)
    }

    static func denoise(_ input: URL, output: URL) async throws -> URL {
        guard let speech = findSpeechCLI() else {
            throw NSError(
                domain: "MyWhi.SoniqoTranscriber",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Soniqo speech CLI is not installed. Run: brew install speech"]
            )
        }
        _ = try await runSpeechCLI(
            executable: speech,
            arguments: ["denoise", input.path, "--output", output.path]
        )
        return output
    }

    static func diarize(_ input: URL) async throws -> String {
        guard let speech = findSpeechCLI() else {
            throw NSError(
                domain: "MyWhi.SoniqoTranscriber",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Soniqo speech CLI is not installed. Run: brew install speech"]
            )
        }
        return try await runSpeechCLI(
            executable: speech,
            arguments: ["diarize", input.path, "--json", "--vad-filter"]
        )
    }

    static func isAvailable() -> Bool {
        findSpeechCLI() != nil
    }

    private static func cliArgs(for model: String) -> [String] {
        switch model {
        case "qwen3-1.7b-8bit":
            return ["--engine", "qwen3", "--model", "1.7B"]
        case "qwen3-1.7b-4bit":
            return ["--engine", "qwen3", "--model", "1.7B-4bit"]
        case "qwen3-0.6b-8bit":
            return ["--engine", "qwen3", "--model", "0.6B-8bit"]
        case "qwen3-0.6b-4bit", "qwen3":
            return ["--engine", "qwen3", "--model", "0.6B"]
        case "parakeet":
            return ["--engine", "parakeet"]
        case "nemotron":
            return ["--engine", "nemotron"]
        case "omnilingual":
            return ["--engine", "omnilingual"]
        default:
            return ["--engine", "qwen3", "--model", "0.6B-8bit"]
        }
    }

    private static func runSpeechCLI(executable: URL, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            process.terminationHandler = { process in
                let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: NSError(
                        domain: "MyWhi.SoniqoTranscriber",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: err.isEmpty ? out : err]
                    ))
                    return
                }
                continuation.resume(returning: out.isEmpty ? err : out)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func findSpeechCLI() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/speech",
            "/usr/local/bin/speech",
            "/usr/bin/speech",
        ]
        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func cleanTranscriptOutput(_ raw: String) -> String {
        let lines = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !$0.hasPrefix("[") && !$0.hasPrefix("Loading ") && !$0.hasPrefix("Downloading ") }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
