import Foundation

struct WhisperKitModelStore {
    static let shared = WhisperKitModelStore()

    static var defaultDownloadBase: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        return documents.appendingPathComponent("huggingface", isDirectory: true)
    }

    let downloadBase: URL
    private let fileManager: FileManager

    init(downloadBase: URL = Self.defaultDownloadBase, fileManager: FileManager = .default) {
        self.downloadBase = downloadBase
        self.fileManager = fileManager
    }

    var repositoryRoot: URL {
        downloadBase
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
    }

    func isModelDownloaded(_ modelCode: String) -> Bool {
        modelFolders(for: modelCode).contains { folder in
            requiredModelComponents.allSatisfy { component in
                let mlmodelc = folder.appendingPathComponent("\(component).mlmodelc", isDirectory: true)
                let mlpackage = folder.appendingPathComponent("\(component).mlpackage", isDirectory: true)
                return fileManager.fileExists(atPath: mlmodelc.path)
                    || fileManager.fileExists(atPath: mlpackage.path)
            }
        }
    }

    func downloadedModels(from modelCodes: [String]) -> Set<String> {
        Set(modelCodes.filter { isModelDownloaded($0) })
    }

    func modelFolders(for modelCode: String) -> [URL] {
        let candidates = folderNameCandidates(for: modelCode)
        let direct = candidates.map { repositoryRoot.appendingPathComponent($0, isDirectory: true) }
        let existingDirect = direct.filter { fileManager.fileExists(atPath: $0.path) }
        if !existingDirect.isEmpty {
            return existingDirect
        }

        let children = (try? fileManager.contentsOfDirectory(
            at: repositoryRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return children.filter { child in
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return false
            }
            let normalizedName = normalize(child.lastPathComponent)
            return folderName(normalizedName, matches: modelCode, candidates: candidates)
        }
    }

    private var requiredModelComponents: [String] {
        ["MelSpectrogram", "AudioEncoder", "TextDecoder"]
    }

    private func folderNameCandidates(for modelCode: String) -> [String] {
        switch modelCode {
        case "tiny":
            return ["openai_whisper-tiny", "whisper-tiny"]
        case "base":
            return ["openai_whisper-base", "whisper-base"]
        case "small":
            return ["openai_whisper-small", "whisper-small"]
        case "medium":
            return ["openai_whisper-medium", "whisper-medium"]
        case "large-v3":
            return ["openai_whisper-large-v3", "whisper-large-v3", "openai_whisper-largev3", "whisper-largev3"]
        case "large-v3-turbo":
            return [
                "openai_whisper-large-v3-turbo",
                "whisper-large-v3-turbo",
                "openai_whisper-largev3_turbo",
                "whisper-largev3_turbo",
                "large-v3-turbo",
                "largev3_turbo",
            ]
        default:
            return ["openai_whisper-\(modelCode)", "whisper-\(modelCode)", modelCode]
        }
    }

    private func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }

    private func folderName(_ normalizedName: String, matches modelCode: String, candidates: [String]) -> Bool {
        switch modelCode {
        case "large-v3-turbo":
            return (normalizedName.contains("large-v3") || normalizedName.contains("largev3"))
                && normalizedName.contains("turbo")
        case "large-v3":
            return (normalizedName.contains("large-v3") || normalizedName.contains("largev3"))
                && !normalizedName.contains("turbo")
        default:
            return candidates.map(normalize).contains { normalizedName.contains($0) }
        }
    }
}
