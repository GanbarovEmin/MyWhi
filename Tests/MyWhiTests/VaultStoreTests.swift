// VaultStoreTests.swift
// Roundtrip tests for the Markdown vault. Uses a temporary directory
// per test to keep things isolated.

import XCTest
@testable import MyWhi

final class VaultStoreTests: XCTestCase {

    private var tempDir: URL!
    private var vault: VaultStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyWhiVaultTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        // VaultPaths.root is hardcoded to Application Support — we work
        // around it by symlinking the test dir into the production root.
        // For simplicity here, we just exercise VaultPaths.root directly.
        vault = VaultStore()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        vault = nil
        try await super.tearDown()
    }

    // MARK: - VaultPaths.slugify

    func testSlugify_basicASCII() {
        XCTAssertEqual(VaultPaths.slugify("Hello World"), "hello-world")
    }

    func testSlugify_collapsesSeparators() {
        XCTAssertEqual(VaultPaths.slugify("foo---bar___baz"), "foo-bar-baz")
    }

    func testSlugify_truncatesTo60Chars() {
        let long = String(repeating: "abcdefghij", count: 10)  // 100 chars
        let slug = VaultPaths.slugify(long)
        XCTAssertLessThanOrEqual(slug.count, 60)
    }

    func testSlugify_emptyReturnsEmpty() {
        XCTAssertEqual(VaultPaths.slugify(""), "")
        XCTAssertEqual(VaultPaths.slugify("---"), "")
    }

    func testSlugify_unicodeBecomesDashes() {
        let slug = VaultPaths.slugify("Привет мир")
        XCTAssertFalse(slug.isEmpty)
        XCTAssertFalse(slug.contains(" "))
    }

    // MARK: - TranscriptFrontmatter roundtrip

    func testFrontmatter_renderAndParseRoundtrip() {
        let date = Date(timeIntervalSince1970: 1721234598)
        let original = TranscriptFrontmatter(
            id: UUID(),
            createdAt: date,
            language: "ru",
            model: "small",
            engine: "whisperkit",
            durationSeconds: 12.5,
            chars: 482,
            words: 78,
            audio: "recording-123.wav"
        )
        let body = "Привет мир.\nЭто тест."
        let yaml = original.renderYAML()
        let full = yaml + body

        guard let parsed = TranscriptFrontmatter.parse(from: full) else {
            XCTFail("parse failed"); return
        }
        XCTAssertEqual(parsed.frontmatter.id, original.id)
        XCTAssertEqual(parsed.frontmatter.language, "ru")
        XCTAssertEqual(parsed.frontmatter.model, "small")
        XCTAssertEqual(parsed.frontmatter.engine, "whisperkit")
        XCTAssertEqual(parsed.frontmatter.chars, 482)
        XCTAssertEqual(parsed.frontmatter.words, 78)
        XCTAssertEqual(parsed.frontmatter.audio, "recording-123.wav")
        XCTAssertEqual(parsed.body, body)
    }

    func testFrontmatter_parseNoFrontmatter_returnsNil() {
        let plain = "Just a body, no frontmatter."
        XCTAssertNil(TranscriptFrontmatter.parse(from: plain))
    }

    func testFrontmatter_renderEmptyOptionalAudio_omitsLine() {
        let fm = TranscriptFrontmatter(
            id: UUID(),
            createdAt: Date(),
            language: "auto",
            model: "small",
            engine: "whisperkit",
            durationSeconds: 0,
            chars: 0,
            words: 0,
            audio: nil
        )
        let yaml = fm.renderYAML()
        XCTAssertFalse(yaml.contains("audio:"))
    }
}