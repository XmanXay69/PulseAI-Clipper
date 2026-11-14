import XCTest
@testable import PulseCore

/// #661: a cut trimmed a frame at a time while the edit loops around it.
final class TrimLoopTests: XCTestCase {
    /// Two linked picture+sound pairs meeting at 10 s: the first shows 100…110 s of the recording, the second 200…210 s.
    private func twoShots() -> Timeline {
        var t = Timeline.empty(name: "Cut", canvas: .vertical1080)
        let first = UUID(), second = UUID()
        t.tracks[0].clips = [TimelineClip(name: "V1", content: .media(assetID: Fixtures.assetID), start: 0, sourceIn: 100, sourceDuration: 10, linkGroup: first, role: .gameplay),
                             TimelineClip(name: "V2", content: .media(assetID: Fixtures.assetID), start: 10, sourceIn: 200, sourceDuration: 10, linkGroup: second, role: .gameplay)]
        t.tracks[3].clips = [TimelineClip(name: "A1", content: .media(assetID: Fixtures.assetID), start: 0, sourceIn: 100, sourceDuration: 10, linkGroup: first, role: .microphone),
                             TimelineClip(name: "A2", content: .media(assetID: Fixtures.assetID), start: 10, sourceIn: 200, sourceDuration: 10, linkGroup: second, role: .microphone)]
        return t
    }

    func testTheNearestCutIsFoundAndTheLoopSitsAroundIt() throws {
        let timeline = twoShots()
        let cut = try XCTUnwrap(TrimLoop.nearestCut(in: timeline, to: 8.2))
        XCTAssertEqual(cut.time, 10, accuracy: 0.001)
        XCTAssertEqual(cut.clipID, timeline.tracks[0].clips[0].id)
        XCTAssertEqual(TrimLoop.range(around: cut.time, in: timeline), TimeRange(start: 8, end: 12))
        XCTAssertEqual(TrimLoop.range(around: 0.5, in: timeline).start, 0, "the loop never leaves the edit")
        // One clip has no cut; neither does a gap between two.
        XCTAssertNil(TrimLoop.nearestCut(in: Fixtures.simpleTimeline(clipDuration: 20), to: 5))
        var gapped = twoShots()
        gapped.tracks[0].clips[1].start = 12
        XCTAssertNil(TrimLoop.nearestCut(in: gapped, to: 10))
        // A cut too far from the playhead isn't the one you meant.
        XCTAssertNil(TrimLoop.nearestCut(in: timeline, to: 30, reach: 5))
        XCTAssertNotNil(TrimLoop.nearestCut(in: timeline, to: 14, reach: 5))
    }

    func testEachPressMovesTheCutOneFrameAndPictureAndSoundMoveTogether() throws {
        var timeline = twoShots()
        let frame = 1.0 / timeline.canvas.frameRate
        let cut = try XCTUnwrap(TrimLoop.nearestCut(in: timeline, to: 10))

        // Three frames later: the first shot runs longer, the second starts later in the recording, nothing shifts.
        let later = try XCTUnwrap(TrimLoop.roll(&timeline, after: cut.clipID, frames: 3))
        XCTAssertEqual(later, 10 + 3 * frame, accuracy: 1e-6)
        XCTAssertEqual(timeline.tracks[0].clips[0].end, later, accuracy: 1e-6)
        XCTAssertEqual(timeline.tracks[0].clips[1].start, later, accuracy: 1e-6)
        XCTAssertEqual(timeline.tracks[0].clips[1].sourceIn, 200 + 3 * frame, accuracy: 1e-6)
        XCTAssertEqual(timeline.duration, 20, accuracy: 1e-6, "a roll never changes the edit's length")
        // The sound's cut moved with the picture's.
        XCTAssertEqual(timeline.tracks[3].clips[0].end, later, accuracy: 1e-6)
        XCTAssertEqual(timeline.tracks[3].clips[1].start, later, accuracy: 1e-6)
        XCTAssertEqual(timeline.tracks[3].clips[1].sourceIn, 200 + 3 * frame, accuracy: 1e-6)

        // Five frames earlier from there.
        let earlier = try XCTUnwrap(TrimLoop.roll(&timeline, after: cut.clipID, frames: -5))
        XCTAssertEqual(earlier, 10 - 2 * frame, accuracy: 1e-6)
        XCTAssertEqual(timeline.tracks[3].clips[0].end, earlier, accuracy: 1e-6)
        // No frames, no change.
        XCTAssertEqual(TrimLoop.roll(&timeline, after: cut.clipID, frames: 0), earlier)
    }

    func testTheCutStopsWhereTheRecordingOrAClipRunsOut() throws {
        var timeline = twoShots()
        let cut = try XCTUnwrap(TrimLoop.nearestCut(in: timeline, to: 10))
        // The second shot can't start before the start of its recording... it has 200 s of room, but the first
        // clip can only shrink to almost nothing: a huge roll earlier stops just short of swallowing it.
        let floor = try XCTUnwrap(TrimLoop.roll(&timeline, after: cut.clipID, frames: -100_000))
        XCTAssertGreaterThan(floor, 0)
        XCTAssertLessThan(floor, 0.1)
        XCTAssertEqual(timeline.tracks[3].clips[0].end, floor, accuracy: 1e-6, "sound stopped with the picture")
        // With the recording 205 s long the first shot can't play past its end: five seconds later at most.
        var limited = twoShots()
        limited.tracks[0].clips[0].sourceIn = 195
        limited.tracks[3].clips[0].sourceIn = 195
        let ceiling = try XCTUnwrap(TrimLoop.roll(&limited, after: limited.tracks[0].clips[0].id, frames: 100_000, mediaDuration: 205))
        XCTAssertEqual(ceiling, 10, accuracy: 1e-6, "195 + 10 already reaches the end of a 205 s recording")
        // The last clip has no cut after it.
        XCTAssertNil(TrimLoop.roll(&timeline, after: timeline.tracks[0].clips[1].id, frames: 1))
    }
}
