import XCTest
@testable import PulseCore

/// Roadmap batch 19: slip / slide / roll (#143), recording size estimates and presets (#319), transcription
/// time per model (#38).
final class Batch19Tests: XCTestCase {
    func threeClips() throws -> Timeline {
        var timeline = Fixtures.simpleTimeline(clipDuration: 30)   // source 100…130, V1 + linked A1
        _ = try timeline.split(at: 10)
        _ = try timeline.split(at: 20)
        return timeline
    }

    func testSlipMovesOnlyWhatPlaysInside() throws {
        var timeline = try threeClips()
        let middle = timeline.tracks[0].clips[1]
        try timeline.slip(clipID: middle.id, by: 3)
        let after = timeline.tracks[0].clips[1]
        XCTAssertEqual(after.start, 10, accuracy: 1e-9)
        XCTAssertEqual(after.duration, 10, accuracy: 1e-9)
        XCTAssertEqual(after.sourceIn, 113, accuracy: 1e-9)
        XCTAssertEqual(timeline.tracks[3].clips[1].sourceIn, 113, accuracy: 1e-9, "linked sound slips too")
        XCTAssertEqual(timeline.duration, 30, accuracy: 1e-9)
        // Clamped to the file.
        let first = timeline.tracks[0].clips[0]
        try timeline.slip(clipID: first.id, by: -5)
        XCTAssertEqual(timeline.tracks[0].clips[0].sourceIn, 95, accuracy: 1e-9, "the file has room before 100")
        try timeline.slip(clipID: first.id, by: -150)
        XCTAssertEqual(timeline.tracks[0].clips[0].sourceIn, 0, accuracy: 1e-9, "can't read before the start of the file")
        try timeline.slip(clipID: timeline.tracks[0].clips[2].id, by: 50, mediaDuration: 135)
        XCTAssertEqual(timeline.tracks[0].clips[2].sourceOut, 135, accuracy: 1e-9, "can't read past the end")
        XCTAssertTrue(EditQualityCheck.blackGaps(in: timeline.tracks[0].clips).isEmpty)
    }

    func testSlideKeepsTheNeighboursTouching() throws {
        var timeline = try threeClips()
        let middle = timeline.tracks[0].clips[1]
        try timeline.slide(clipID: middle.id, by: 2)
        let clips = timeline.tracks[0].clips
        XCTAssertEqual(clips[0].end, 12, accuracy: 1e-9)
        XCTAssertEqual(clips[1].start, 12, accuracy: 1e-9)
        XCTAssertEqual(clips[1].end, 22, accuracy: 1e-9)
        XCTAssertEqual(clips[1].sourceIn, 110, accuracy: 1e-9, "what plays inside the slid clip doesn't change")
        XCTAssertEqual(clips[2].start, 22, accuracy: 1e-9)
        XCTAssertEqual(clips[2].sourceIn, 122, accuracy: 1e-9)
        XCTAssertEqual(clips[2].end, 30, accuracy: 1e-9)
        XCTAssertEqual(timeline.duration, 30, accuracy: 1e-9)
        XCTAssertTrue(EditQualityCheck.blackGaps(in: clips).isEmpty)
        XCTAssertEqual(timeline.tracks[3].clips[1].start, 12, accuracy: 1e-9, "sound follows")
        // Can't push the last clip below its minimum.
        try timeline.slide(clipID: clips[1].id, by: 100)
        XCTAssertGreaterThanOrEqual(timeline.tracks[0].clips[2].duration, Timeline.minimumClipDuration - 1e-9)
        XCTAssertEqual(timeline.duration, 30, accuracy: 1e-9)
    }

    func testRollMovesTheCut() throws {
        var timeline = try threeClips()
        let first = timeline.tracks[0].clips[0]
        try timeline.roll(edgeAfter: first.id, by: 3)
        var clips = timeline.tracks[0].clips
        XCTAssertEqual(clips[0].end, 13, accuracy: 1e-9)
        XCTAssertEqual(clips[0].sourceOut, 113, accuracy: 1e-9)
        XCTAssertEqual(clips[1].start, 13, accuracy: 1e-9)
        XCTAssertEqual(clips[1].sourceIn, 113, accuracy: 1e-9)
        XCTAssertEqual(clips[1].end, 20, accuracy: 1e-9)
        XCTAssertEqual(timeline.duration, 30, accuracy: 1e-9)
        try timeline.roll(edgeAfter: clips[0].id, by: -5)
        clips = timeline.tracks[0].clips
        XCTAssertEqual(clips[0].end, 8, accuracy: 1e-9)
        XCTAssertEqual(clips[1].start, 8, accuracy: 1e-9)
        XCTAssertEqual(clips[1].sourceIn, 108, accuracy: 1e-9)
        XCTAssertTrue(EditQualityCheck.blackGaps(in: clips).isEmpty)
        XCTAssertEqual(timeline.tracks[3].clips[0].end, 8, accuracy: 1e-9, "sound rolls too")
        // The last clip has nothing after it.
        try timeline.roll(edgeAfter: clips[2].id, by: 2)
        XCTAssertEqual(timeline.tracks[0].clips[2].end, 30, accuracy: 1e-9)
    }

    func testRecordingEstimatesAndPresets() {
        let hevc = RecordingEstimate.bytesPerHour(width: 1920, height: 1080, fps: 60, codec: .hevc)
        let h264 = RecordingEstimate.bytesPerHour(width: 1920, height: 1080, fps: 60, codec: .h264)
        XCTAssertGreaterThan(hevc, 2_000_000_000)
        XCTAssertLessThan(hevc, 4_000_000_000)
        XCTAssertGreaterThan(h264, hevc)
        XCTAssertTrue(RecordingEstimate.perHourText(width: 1920, height: 1080, fps: 60, codec: .hevc).hasSuffix("GB an hour"))
        XCTAssertTrue(RecordingEstimate.perHourText(width: 640, height: 360, fps: 30, codec: .hevc).hasSuffix("MB an hour"))
        XCTAssertEqual(RecordingPreset.gameAndCam.frameRate, 60)
        XCTAssertFalse(RecordingPreset.podcast.captureSystemAudio)
        XCTAssertEqual(RecordingPreset.screencast.codec, .h264)
    }

    func testTranscriptionMinutesPerModel() {
        var profile = AnalysisSpeedProfile()
        profile.transcription = 4
        XCTAssertEqual(profile.transcriptionMinutesPerHour(), 4, accuracy: 1e-9)
        XCTAssertEqual(profile.transcriptionMinutesPerHour(modelFactor: 3), 12, accuracy: 1e-9)
        XCTAssertEqual(profile.transcriptionMinutesPerHour(modelFactor: 1, learnedFactor: 3), 4.0 / 3, accuracy: 1e-9)
    }
}
