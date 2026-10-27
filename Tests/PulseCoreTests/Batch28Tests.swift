import XCTest
@testable import PulseCore

final class Batch28Tests: XCTestCase {
    func testProRes4444KeepsAlphaAndMov() throws {
        XCTAssertTrue(VideoCodec.proRes4444.supportsAlpha)
        XCTAssertTrue(VideoCodec.proRes4444.isProRes)
        XCTAssertFalse(VideoCodec.h264.supportsAlpha)
        XCTAssertEqual(VideoCodec.proRes4444.fileExtension, "mov")
        XCTAssertEqual(VideoCodec.proRes422.fileExtension, "mov")
        XCTAssertEqual(VideoCodec.hevc.fileExtension, "mp4")
        var settings = ExportSettings()
        XCTAssertFalse(settings.transparentBackground)
        settings.codec = .proRes4444
        settings.transparentBackground = true
        let back = try JSONDecoder().decode(ExportSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(back.codec, .proRes4444)
        XCTAssertTrue(back.transparentBackground)
        XCTAssertEqual(back.outputExtension, "mov")
        XCTAssertGreaterThan(RecordingEstimate.bytesPerHour(width: 1920, height: 1080, fps: 30, codec: .proRes4444),
                             RecordingEstimate.bytesPerHour(width: 1920, height: 1080, fps: 30, codec: .proRes422))
    }

    func testTrackHeightsAndAudioScrubDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.trackHeight, .medium)
        XCTAssertFalse(settings.audioScrub)
        XCTAssertEqual(TrackHeightPreset.small.scale, 0.75)
        XCTAssertGreaterThan(TrackHeightPreset.large.scale, 1)
        XCTAssertEqual(TrackHeightPreset.allCases.map(\.scale), TrackHeightPreset.allCases.map(\.scale).sorted())
    }

    func testProjectOverridesDecodeAndCount() throws {
        let doc = try JSONDecoder().decode(ProjectDocument.self, from: Data(#"{"id":"\#(UUID().uuidString)","name":"Old"}"#.utf8))
        XCTAssertTrue(doc.overrides.isEmpty)
        var overrides = ProjectOverrides()
        XCTAssertEqual(overrides.count, 0)
        overrides.exportPresetID = ExportPreset.youtube4K.id
        overrides.loudnessTarget = -16
        XCTAssertEqual(overrides.count, 2)
        XCTAssertFalse(overrides.isEmpty)
        let back = try JSONDecoder().decode(ProjectOverrides.self, from: JSONEncoder().encode(overrides))
        XCTAssertEqual(back, overrides)
    }
}
