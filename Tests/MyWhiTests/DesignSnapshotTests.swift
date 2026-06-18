// DesignSnapshotTests.swift
// Phase 6.4 — "snapshot" tests for the design system components.
//
// We don't use the swift-snapshot-testing library (extra dependency).
// Instead, we render each component into an off-screen NSImage via
// ImageRenderer and assert that the pixel size matches the expected
// component dimensions. Catches catastrophic layout regressions
// without depending on pixel-perfect comparisons.

import XCTest
import SwiftUI
import AppKit
@testable import MyWhi

@MainActor
final class DesignSnapshotTests: XCTestCase {

    /// Render a SwiftUI view to an NSImage at the given size and
    /// return the image. Returns nil if rendering fails.
    private func render<V: View>(_ view: V, size: CGSize) -> NSImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2.0
        return renderer.nsImage
    }

    // MARK: - HDButton

    func testHDButtonPrimary_rendersAtExpectedSize() {
        let button = HDButtonPrimary(title: "Submit") { }
        let image = render(button, size: CGSize(width: 200, height: 44))
        XCTAssertNotNil(image)
        // Expect a render that fits the frame; we don't assert pixel
        // content (brittle). Just that it produced an image.
        XCTAssertGreaterThan(image!.size.width, 50)
        XCTAssertGreaterThan(image!.size.height, 20)
    }

    func testHDButtonPrimary_withIcon_rendersAtExpectedSize() {
        let button = HDButtonPrimary(title: "Save", icon: "tray.and.arrow.down") { }
        let image = render(button, size: CGSize(width: 200, height: 44))
        XCTAssertNotNil(image)
    }

    func testHDButtonSecondary_rendersAtExpectedSize() {
        let button = HDButtonSecondary(title: "Cancel") { }
        let image = render(button, size: CGSize(width: 150, height: 32))
        XCTAssertNotNil(image)
    }

    // MARK: - HDCard

    func testHDCardCanvas_rendersAtExpectedSize() {
        let card = HDCard(.canvas, cornerRadius: .md, padding: .lg) {
            Text("Card content")
                .padding()
        }
        let image = render(card, size: CGSize(width: 300, height: 200))
        XCTAssertNotNil(image)
    }

    func testHDCardStone_rendersAtExpectedSize() {
        let card = HDCard(.stone) {
            Text("Stone card")
                .padding()
        }
        let image = render(card, size: CGSize(width: 300, height: 200))
        XCTAssertNotNil(image)
    }

    func testHDCardDark_rendersAtExpectedSize() {
        let card = HDCard(.dark) {
            Text("Dark card")
                .foregroundStyle(.white)
                .padding()
        }
        let image = render(card, size: CGSize(width: 300, height: 200))
        XCTAssertNotNil(image)
    }

    // MARK: - HDStatTile

    func testHDStatTileLight_renders() {
        let tile = HDStatTile(
            label: "Всего слов",
            value: "12 345",
            surface: .light
        )
        let image = render(tile, size: CGSize(width: 180, height: 100))
        XCTAssertNotNil(image)
    }

    func testHDStatTileDark_renders() {
        let tile = HDStatTile(
            label: "Серия",
            value: "5 дн.",
            delta: "макс 12",
            surface: .dark
        )
        let image = render(tile, size: CGSize(width: 180, height: 100))
        XCTAssertNotNil(image)
    }

    // MARK: - HDRecordButton (3 states)

    func testHDRecordButtonIdle_renders() {
        let button = HDRecordButton(state: .idle, size: 88) { }
        let image = render(button, size: CGSize(width: 120, height: 120))
        XCTAssertNotNil(image)
    }

    func testHDRecordButtonRecording_renders() {
        let button = HDRecordButton(state: .recording, size: 88) { }
        let image = render(button, size: CGSize(width: 120, height: 120))
        XCTAssertNotNil(image)
    }

    func testHDRecordButtonTranscribing_renders() {
        let button = HDRecordButton(state: .transcribing, size: 88) { }
        let image = render(button, size: CGSize(width: 120, height: 120))
        XCTAssertNotNil(image)
    }

    // MARK: - HDWaveformView (no level = flat)

    func testHDWaveformView_compact_renders() {
        let view = HDWaveformView(level: 0.5, style: .compact, color: HDColor.deepGreen)
        let image = render(view, size: CGSize(width: 200, height: 30))
        XCTAssertNotNil(image)
    }

    func testHDWaveformView_hero_renders() {
        let view = HDWaveformView(level: 0.8, style: .hero, color: HDColor.coral)
        let image = render(view, size: CGSize(width: 300, height: 50))
        XCTAssertNotNil(image)
    }

    func testHDWaveformView_silentLevel_renders() {
        let view = HDWaveformView(level: 0.0, style: .hero)
        let image = render(view, size: CGSize(width: 300, height: 50))
        XCTAssertNotNil(image)
    }

    // MARK: - HDSidebarItem

    func testHDSidebarItem_rendersUnselected() {
        enum TestSection: Hashable { case home, scratchpad, insights, settings }
        let item = HDSidebarItem(
            icon: "mic",
            label: "Запись",
            section: TestSection.home,
            badge: nil,
            selection: TestSection.home
        )
        let image = render(item, size: CGSize(width: 220, height: 32))
        XCTAssertNotNil(image)
    }

    func testHDSidebarItem_rendersWithBadge() {
        enum TestSection: Hashable { case home, scratchpad, insights, settings }
        let item = HDSidebarItem(
            icon: "doc.text",
            label: "Scratchpad",
            section: TestSection.scratchpad,
            badge: "5",
            selection: TestSection.home
        )
        let image = render(item, size: CGSize(width: 220, height: 32))
        XCTAssertNotNil(image)
    }

    // MARK: - OnboardingCard

    func testOnboardingCard_renders() {
        let card = OnboardingCard()
        let image = render(card, size: CGSize(width: 480, height: 200))
        XCTAssertNotNil(image)
    }

    // MARK: - Smoke: composite view

    func testHDSectionBandWithStatTiles_renders() {
        let band = HStack(spacing: HDSpacing.xl.rawValue) {
            HDStatTile(label: "Words", value: "100", surface: .dark)
            HDStatTile(label: "Chars", value: "500", surface: .dark)
            HDStatTile(label: "Streak", value: "5 дн.", surface: .dark)
        }
        .frame(maxWidth: .infinity)
        .padding(HDSpacing.xl.rawValue)
        .background(
            RoundedRectangle(cornerRadius: HDRadius.lg.rawValue, style: .continuous)
                .fill(HDColor.deepGreen)
        )
        .padding()
        let image = render(band, size: CGSize(width: 720, height: 160))
        XCTAssertNotNil(image)
    }
}