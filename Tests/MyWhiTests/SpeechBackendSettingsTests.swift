import XCTest
@testable import MyWhi

final class SpeechBackendSettingsTests: XCTestCase {
    func testSpeechBackendDefaults() {
        let settings = AppSettings()
        XCTAssertEqual(settings.transcriptionBackend, "whisperkit")
        XCTAssertEqual(settings.soniqoModel, AppSettings.recommendedSoniqoModel)
        XCTAssertEqual(settings.meetingModel, AppSettings.recommendedSoniqoModel)
        XCTAssertTrue(settings.meetingRecordSystemAudio)
        XCTAssertTrue(settings.meetingDenoiseAudio)
        XCTAssertTrue(settings.meetingDiarizationEnabled)
    }

    func testSpeechBackendRoundTrip() throws {
        let settings = AppSettings()
        settings.transcriptionBackend = "soniqo"
        settings.soniqoModel = "nemotron"
        settings.meetingModel = "parakeet"
        settings.meetingContext = "Project MyWhi, Emin, roadmap"
        settings.meetingRecordSystemAudio = false
        settings.meetingDenoiseAudio = false
        settings.meetingDiarizationEnabled = false

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.transcriptionBackend, "soniqo")
        XCTAssertEqual(decoded.soniqoModel, "nemotron")
        XCTAssertEqual(decoded.meetingModel, "parakeet")
        XCTAssertEqual(decoded.meetingContext, "Project MyWhi, Emin, roadmap")
        XCTAssertFalse(decoded.meetingRecordSystemAudio)
        XCTAssertFalse(decoded.meetingDenoiseAudio)
        XCTAssertFalse(decoded.meetingDiarizationEnabled)
    }
}
