// LiveDecodingIndicatorTests.swift
// Phase 18 — verifies the live-decoding indicator state machine on
// AppState.isLiveDecoding. The actual "транскрибирую…" label is a
// view concern; here we verify the boolean flips correctly via the
// public setIsLiveDecoding(_:) method (private(set) preserves
// encapsulation; the LiveTranscriber uses this API).

import XCTest
@testable import MyWhi

@MainActor
final class LiveDecodingIndicatorTests: XCTestCase {

    /// Phase 18: isLiveDecoding must default to false. The LiveTranscriber
    /// is responsible for flipping it true/false around a decode —
    /// if it's accidentally left true at init time, the UI would
    /// show "транскрибирую…" forever.
    func testIsLiveDecodingDefaultsFalse() {
        let state = AppState()
        XCTAssertFalse(state.isLiveDecoding)
    }

    /// Phase 18: setting the flag via the public method must fire
    /// @Published so SwiftUI can re-render. We verify by subscribing.
    func testIsLiveDecodingPublishedChanges() async {
        let state = AppState()
        let expectation = expectation(description: "isLiveDecoding flips to true")
        var sawTrue = false
        var cancellable: Any?

        cancellable = state.$isLiveDecoding.sink { newValue in
            if newValue && !sawTrue {
                sawTrue = true
                expectation.fulfill()
            }
        }

        state.setIsLiveDecoding(true)
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(state.isLiveDecoding, "setIsLiveDecoding(true) should make the property true")

        state.setIsLiveDecoding(false)
        XCTAssertFalse(state.isLiveDecoding, "setIsLiveDecoding(false) should make the property false")

        _ = cancellable
    }

    /// Phase 18: the flag must be readable from any actor context
    /// without surprises. The AppState is @MainActor; we read on
    /// main here. This is a "compile-check" test that also catches
    /// accidental moves off MainActor.
    func testIsLiveDecodingAccessibleFromMainActor() {
        let state = AppState()
        MainActor.assumeIsolated {
            _ = state.isLiveDecoding
        }
    }

    /// Phase 18: setIsLiveDecoding idempotency — calling twice with
    /// the same value should not crash and should hold the value.
    func testSetIsLiveDecodingIdempotent() {
        let state = AppState()
        state.setIsLiveDecoding(true)
        state.setIsLiveDecoding(true)
        XCTAssertTrue(state.isLiveDecoding)
        state.setIsLiveDecoding(false)
        state.setIsLiveDecoding(false)
        XCTAssertFalse(state.isLiveDecoding)
    }
}