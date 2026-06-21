import XCTest
@testable import MyWhi

final class WhisperKitModelStoreTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyWhiModelStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
    }

    func testDownloadedModelRequiresAllWhisperKitComponents() throws {
        let store = WhisperKitModelStore(downloadBase: tempRoot)
        let folder = store.repositoryRoot.appendingPathComponent("openai_whisper-small", isDirectory: true)

        try createComponent("MelSpectrogram", in: folder)
        try createComponent("AudioEncoder", in: folder)

        XCTAssertFalse(store.isModelDownloaded("small"))

        try createComponent("TextDecoder", in: folder)
        XCTAssertTrue(store.isModelDownloaded("small"))
    }

    func testDownloadedModelsReturnsOnlyCachedModels() throws {
        let store = WhisperKitModelStore(downloadBase: tempRoot)
        let small = store.repositoryRoot.appendingPathComponent("openai_whisper-small", isDirectory: true)
        let medium = store.repositoryRoot.appendingPathComponent("openai_whisper-medium", isDirectory: true)

        for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            try createComponent(component, in: small)
        }
        try createComponent("MelSpectrogram", in: medium)

        XCTAssertEqual(store.downloadedModels(from: ["tiny", "small", "medium"]), Set(["small"]))
    }

    func testLargeV3TurboDoesNotMarkPlainLargeV3AsDownloaded() throws {
        let store = WhisperKitModelStore(downloadBase: tempRoot)
        let turbo = store.repositoryRoot.appendingPathComponent("openai_whisper-large-v3-v20240930_turbo", isDirectory: true)

        for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            try createComponent(component, in: turbo)
        }

        XCTAssertTrue(store.isModelDownloaded("large-v3-turbo"))
        XCTAssertFalse(store.isModelDownloaded("large-v3"))
    }

    private func createComponent(_ name: String, in folder: URL) throws {
        let component = folder.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
        try FileManager.default.createDirectory(at: component, withIntermediateDirectories: true)
        try Data().write(to: component.appendingPathComponent("metadata.json"))
    }
}
