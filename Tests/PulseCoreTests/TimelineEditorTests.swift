import XCTest
@testable import PulseCore

final class TimelineEditorTests: XCTestCase {
    let asset = Fixtures.assetID

    func testSplitLinkedClipsKeepsLinkAndSourceContinuity() throws {
        var t = Fixtures.simpleTimeline(clipDuration: 10)
        let videoID = t.tracks[0].clips[0].id
        let created = try t.split(at: 4, clipIDs: [videoID])
        XCTAssertEqual(created.count, 2, "video and linked audio should both split")
        XCTAssertEqual(t.tracks[0].clips.count, 2)
        XCTAssertEqual(t.tracks[3].clips.count, 2)
        let left = t.tracks[0].clips[0]
        let right = t.tracks[0].clips[1]
        XCTAssertEqual(left.end, 4, accuracy: 1e-9)
        XCTAssertEqual(right.start, 4, accuracy: 1e-9)
        XCTAssertEqual(right.sourceIn, 104, accuracy: 1e-9)
        XCTAssertEqual(left.sourceOut, right.sourceIn, accuracy: 1e-9)
        // Right halves share a NEW link group, distinct from the left halves.
        XCTAssertNotNil(right.linkGroup)
        XCTAssertNotEqual(right.linkGroup, left.linkGroup)
        XCTAssertEqual(t.tracks[3].clips[1].linkGroup, right.linkGroup)
    }

    func testSplitOutsideClipThrows() {
        var t = Fixtures.simpleTimeline(clipDuration: 10)
        let id = t.tracks[0].clips[0].id
        XCTAssertThrowsError(try t.split(at: 20, clipIDs: [id]))
    }

    func testRippleDeleteClosesGapOnAllLinkedTracks() throws {
        var t = Fixtures.simpleTimeline(clipDuration: 10)
        let id = t.tracks[0].clips[0].id
        try t.split(at: 3, clipIDs: [id])
        try t.split(at: 6, clipIDs: [t.tracks[0].clips[1].id])
        XCTAssertEqual(t.tracks[0].clips.count, 3)
        let middle = t.tracks[0].clips[1].id
        t.delete(clipIDs: [middle], ripple: true)
        XCTAssertEqual(t.tracks[0].clips.count, 2)
        XCTAssertEqual(t.tracks[3].clips.count, 2)
        XCTAssertEqual(t.tracks[0].clips[1].start, 3, accuracy: 1e-9)
        XCTAssertEqual(t.tracks[3].clips[1].start, 3, accuracy: 1e-9)
        XCTAssertEqual(t.duration, 7, accuracy: 1e-9)
    }

    func testTrimStartClampsAtSourceZeroAndPreviousClip() throws {
        var t = Timeline.empty(name: "T", canvas: .vertical1080)
        let clip = TimelineClip(name: "C", content: .media(assetID: asset), start: 5, sourceIn: 2, sourceDuration: 10)
        try t.insert(clip, onTrack: t.tracks[0].id)
        // Try to extend the head by 5 s — only 2 s of source exist before sourceIn.
        try t.trimStart(clipID: clip.id, to: 0)
        let trimmed = try XCTUnwrap(t.clip(id: clip.id))
        XCTAssertEqual(trimmed.sourceIn, 0, accuracy: 1e-9)
        XCTAssertEqual(trimmed.start, 3, accuracy: 1e-9)
        XCTAssertEqual(trimmed.end, 15, accuracy: 1e-9)
    }

    func testTrimEndRespectsMediaDurationAndNextClip() throws {
        var t = Timeline.empty(name: "T", canvas: .vertical1080)
        let a = TimelineClip(name: "A", content: .media(assetID: asset), start: 0, sourceIn: 0, sourceDuration: 5)
        let b = TimelineClip(name: "B", content: .media(assetID: asset), start: 8, sourceIn: 50, sourceDuration: 5)
        try t.insert(a, onTrack: t.tracks[0].id)
        try t.insert(b, onTrack: t.tracks[0].id)
        try t.trimEnd(clipID: a.id, to: 20, mediaDuration: 100)
        XCTAssertEqual(t.clip(id: a.id)!.end, 8, accuracy: 1e-9, "should stop at the next clip")
        try t.trimEnd(clipID: b.id, to: 100, mediaDuration: 57)
        XCTAssertEqual(t.clip(id: b.id)!.sourceOut, 57, accuracy: 1e-9, "should stop at media end")
    }

    func testTrimStartShiftsKeyframesToStayLockedToContent() throws {
        var t = Timeline.empty(name: "T", canvas: .vertical1080)
        var clip = TimelineClip(name: "C", content: .media(assetID: asset), start: 0, sourceIn: 10, sourceDuration: 10)
        clip.transform.zoom.setKeyframe(at: 5, value: 1.2)
        try t.insert(clip, onTrack: t.tracks[0].id)
        try t.trimStart(clipID: clip.id, to: 2)
        let trimmed = t.clip(id: clip.id)!
        XCTAssertEqual(trimmed.transform.zoom.keyframes.first!.time, 3, accuracy: 1e-9)
    }

    func testInsertModeRipplesAndOverwriteReplaces() throws {
        var t = Timeline.empty(name: "T", canvas: .vertical1080)
        let a = TimelineClip(name: "A", content: .media(assetID: asset), start: 0, sourceDuration: 10)
        try t.insert(a, onTrack: t.tracks[0].id)
        let b = TimelineClip(name: "B", content: .media(assetID: asset), start: 4, sourceIn: 50, sourceDuration: 2)
        try t.insert(b, onTrack: t.tracks[0].id, mode: .insert)
        XCTAssertEqual(t.tracks[0].clips.count, 3)
        XCTAssertEqual(t.duration, 12, accuracy: 1e-9)
        let c = TimelineClip(name: "C", content: .media(assetID: asset), start: 1, sourceIn: 80, sourceDuration: 2)
        try t.insert(c, onTrack: t.tracks[0].id, mode: .overwrite)
        XCTAssertEqual(t.duration, 12, accuracy: 1e-9)
        // No overlaps.
        let clips = t.tracks[0].clips
        for (x, y) in zip(clips, clips.dropFirst()) {
            XCTAssertLessThanOrEqual(x.end, y.start + 1e-9)
        }
    }

    func testIncompatibleTrackIsRejected() {
        var t = Timeline.empty(name: "T", canvas: .vertical1080)
        let text = TimelineClip(name: "Title", content: .text(TextElement(text: "Hi")), start: 0, sourceDuration: 2)
        XCTAssertThrowsError(try t.insert(text, onTrack: t.tracks[3].id))
    }

    func testMoveLinkedClipsTogether() throws {
        var t = Fixtures.simpleTimeline(clipDuration: 5)
        let v = t.tracks[0].clips[0].id
        try t.move(clipID: v, toStart: 3)
        XCTAssertEqual(t.tracks[0].clips[0].start, 3, accuracy: 1e-9)
        XCTAssertEqual(t.tracks[3].clips[0].start, 3, accuracy: 1e-9)
        try t.move(clipID: v, toStart: -10)
        XCTAssertEqual(t.tracks[0].clips[0].start, 0, accuracy: 1e-9)
    }

    func testSetSpeedChangesDurationAndRipples() throws {
        var t = Timeline.empty(name: "T", canvas: .vertical1080)
        let a = TimelineClip(name: "A", content: .media(assetID: asset), start: 0, sourceDuration: 10)
        let b = TimelineClip(name: "B", content: .media(assetID: asset), start: 10, sourceIn: 20, sourceDuration: 5)
        try t.insert(a, onTrack: t.tracks[0].id)
        try t.insert(b, onTrack: t.tracks[0].id)
        try t.setSpeed(clipID: a.id, speed: 2)
        XCTAssertEqual(t.clip(id: a.id)!.duration, 5, accuracy: 1e-9)
        XCTAssertEqual(t.clip(id: b.id)!.start, 5, accuracy: 1e-9)
    }

    func testRemoveSourceRangesAndRestore() throws {
        var t = Fixtures.simpleTimeline(clipDuration: 20) // source 100…120
        let removed = t.removeSourceRanges([TimeRange(start: 105, end: 108)], assetID: asset, reason: .silence, aiGenerated: true)
        XCTAssertEqual(removed, 3, accuracy: 1e-6)
        XCTAssertEqual(t.duration, 17, accuracy: 1e-6)
        XCTAssertEqual(t.tracks[0].clips.count, 2)
        XCTAssertEqual(t.tracks[3].clips.count, 2)
        XCTAssertEqual(t.removedSections.count, 1)
        // Source continuity around the cut.
        XCTAssertEqual(t.tracks[0].clips[0].sourceOut, 105, accuracy: 1e-6)
        XCTAssertEqual(t.tracks[0].clips[1].sourceIn, 108, accuracy: 1e-6)

        try t.restore(removedSectionID: t.removedSections[0].id)
        XCTAssertEqual(t.duration, 20, accuracy: 1e-6)
        XCTAssertTrue(t.removedSections.isEmpty)
        XCTAssertEqual(t.tracks[0].clips.count, 1, "restored halves should merge back")
        XCTAssertEqual(t.tracks[0].clips[0].sourceRange, TimeRange(start: 100, end: 120))
    }

    func testTimelineRangesForSourceFollowEdits() {
        var t = Fixtures.simpleTimeline(clipDuration: 20)
        t.removeSourceRanges([TimeRange(start: 102, end: 104)], assetID: asset, reason: .manual)
        let ranges = t.timelineRanges(forSource: TimeRange(start: 110, end: 111), assetID: asset)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].start, 8, accuracy: 1e-6)
    }

    func testSnapping() {
        let points: [Seconds] = [0, 2, 5]
        XCTAssertEqual(Timeline.snap(4.95, to: points, tolerance: 0.1), 5)
        XCTAssertEqual(Timeline.snap(3.5, to: points, tolerance: 0.1), 3.5)
    }

    func testCloseGapsMagnetic() throws {
        var t = Timeline.empty(name: "T", canvas: .vertical1080)
        try t.insert(TimelineClip(name: "A", content: .media(assetID: asset), start: 2, sourceDuration: 3), onTrack: t.tracks[0].id)
        try t.insert(TimelineClip(name: "B", content: .media(assetID: asset), start: 9, sourceDuration: 1), onTrack: t.tracks[0].id)
        t.closeGaps(trackID: t.tracks[0].id)
        XCTAssertEqual(t.tracks[0].clips.map(\.start), [0, 3])
    }

    func testDuplicateLinkedGroup() throws {
        var t = Fixtures.simpleTimeline(clipDuration: 4)
        let created = try t.duplicate(clipIDs: [t.tracks[0].clips[0].id])
        XCTAssertEqual(created.count, 2)
        XCTAssertEqual(t.duration, 8, accuracy: 1e-9)
        let copies = created.compactMap { t.clip(id: $0) }
        XCTAssertEqual(Set(copies.compactMap(\.linkGroup)).count, 1)
    }
}
