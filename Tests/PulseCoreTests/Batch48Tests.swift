import XCTest
@testable import PulseCore

final class Batch48Tests: XCTestCase {
    // MARK: #322 — recordings split under a size limit, joined back together

    func testSplitPlanKeepsPartsUnderTheLimit() {
        let gb = RecordingSplitter.bytes(gigabytes: 4)
        XCTAssertEqual(gb, 4_000_000_000)
        XCTAssertEqual(RecordingSplitter.bytes(gigabytes: 0), 0)
        // 10 GB over two hours into 4 GB parts: three parts, whole seconds, no gaps.
        let plan = RecordingSplitter.plan(fileSize: 10_000_000_000, duration: 7200, maxBytes: gb)
        XCTAssertEqual(plan.count, 3)
        XCTAssertEqual(plan.first?.start, 0)
        XCTAssertEqual(plan.last?.end, 7200)
        for i in 1..<plan.count { XCTAssertEqual(plan[i].start, plan[i - 1].end) }
        for r in plan { XCTAssertEqual(r.start, r.start.rounded()); XCTAssertLessThanOrEqual(Double(10_000_000_000) * r.duration / 7200, Double(gb) * 1.02) }
        // Already under the limit: the whole file as one stretch. No limit: the same.
        XCTAssertEqual(RecordingSplitter.plan(fileSize: 1_000_000_000, duration: 600, maxBytes: gb), [TimeRange(start: 0, end: 600)])
        XCTAssertEqual(RecordingSplitter.plan(fileSize: 50_000_000_000, duration: 600, maxBytes: 0), [TimeRange(start: 0, end: 600)])
        // A short but huge file never gets parts under a minute.
        let short = RecordingSplitter.plan(fileSize: 30_000_000_000, duration: 150, maxBytes: gb)
        XCTAssertEqual(short.count, 2)
        XCTAssertTrue(short.allSatisfy { $0.duration >= 60 })
        XCTAssertTrue(RecordingSplitter.plan(fileSize: 1, duration: 0, maxBytes: gb).isEmpty)
        XCTAssertEqual(RecordingSplitter.partName(base: "ranked night", index: 1, count: 5, extension: "mov"), "ranked night part 2 of 5.mov")
    }

    private func part(_ index: Int, group: UUID, duration: Seconds, name: String) -> MediaAsset {
        var a = MediaAsset(name: name, path: "/tmp/\(name).mov", kind: .video, role: .gameplay)
        a.metadata = MediaMetadata(duration: duration, width: 1920, height: 1080, frameRate: 60, hasVideo: true, hasAudio: true)
        a.sequenceGroupID = group
        a.sequenceIndex = index
        return a
    }

    func testSequencePartsAndJoinedTimeline() throws {
        let group = UUID()
        let p1 = part(0, group: group, duration: 3600, name: "stream part 1 of 3")
        let p2 = part(1, group: group, duration: 3600, name: "stream part 2 of 3")
        let p3 = part(2, group: group, duration: 1800, name: "stream part 3 of 3")
        var doc = ProjectDocument(name: "Split")
        doc.media = [p3, MediaAsset(name: "other", path: "/tmp/o.mov", kind: .video), p1, p2]
        XCTAssertEqual(doc.sequenceParts(of: p2).map(\.name), [p1.name, p2.name, p3.name])
        XCTAssertEqual(doc.sequenceParts(of: doc.media[1]).count, 1, "a lone file is its own sequence")

        let timeline = try XCTUnwrap(SequenceJoiner.timeline(parts: doc.sequenceParts(of: p1)))
        XCTAssertEqual(timeline.name, "stream — joined")
        XCTAssertEqual(timeline.canvas.frameRate, 60)
        XCTAssertEqual(timeline.tracks[0].clips.map(\.start), [0, 3600, 7200])
        XCTAssertEqual(timeline.tracks[1].clips.map(\.start), [0, 3600, 7200])
        XCTAssertEqual(timeline.duration, 9000, accuracy: 0.001)
        XCTAssertEqual(timeline.markers.map(\.time), [3600, 7200], "a marker at every join")
        XCTAssertEqual(timeline.tracks[0].clips[0].linkGroup, timeline.tracks[1].clips[0].linkGroup, "video and audio of a part are linked")
        XCTAssertEqual(timeline.tracks[0].clips[1].role, .gameplay)
        XCTAssertNil(SequenceJoiner.timeline(parts: []))
        // Old project files decode without the sequence fields.
        let back = try JSONDecoder().decode(MediaAsset.self, from: JSONEncoder().encode(p1))
        XCTAssertEqual(back.sequenceIndex, 0)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p1)) as! [String: Any]
        json["sequenceGroupID"] = nil
        json["sequenceIndex"] = nil
        let old = try JSONDecoder().decode(MediaAsset.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.sequenceGroupID)
        XCTAssertNil(old.sequenceIndex)
    }

    func testSplitSettingDecodesWithADefault() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(old.recordingSplitGB, 0)
        var settings = AppSettings()
        settings.recordingSplitGB = 4
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(back.recordingSplitGB, 4)
    }

    // MARK: #271 — the voice leans toward the facecam

    func testPanIsZeroInTheMiddleAndSubtleAtTheEdges() {
        XCTAssertEqual(AutoPan.pan(forPictureX: 0.5), 0)
        XCTAssertEqual(AutoPan.pan(forPictureX: 0.6), 0, "the middle third stays centred")
        XCTAssertEqual(AutoPan.pan(forPictureX: 0), -AutoPan.strength, accuracy: 1e-9)
        XCTAssertEqual(AutoPan.pan(forPictureX: 1), AutoPan.strength, accuracy: 1e-9)
        XCTAssertLessThan(AutoPan.pan(forPictureX: 0.15), 0)
        XCTAssertGreaterThan(AutoPan.pan(forPictureX: 0.85), 0)
        XCTAssertLessThan(abs(AutoPan.pan(forPictureX: 0.85)), AutoPan.strength)
        XCTAssertEqual(AutoPan.pan(forPictureX: 1, strength: 0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(AutoPan.pan(forPictureX: 7), AutoPan.strength, accuracy: 1e-9, "clamped")
    }

    func testApplyLeansLinkedAudioTowardTheFacecam() {
        var timeline = Timeline.empty(name: "Short", canvas: .vertical1080)
        let game = UUID(), cam = UUID()
        var camClip = TimelineClip(name: "Cam", content: .media(assetID: cam), start: 0, sourceDuration: 20, linkGroup: group1, role: .webcam)
        camClip.transform.positionX = AnimatedDouble(0.12)   // top-left facecam
        let gameClip = TimelineClip(name: "Game", content: .media(assetID: game), start: 0, sourceDuration: 20, role: .gameplay)
        let voice = TimelineClip(name: "Mic", content: .media(assetID: cam), start: 0, sourceDuration: 20, linkGroup: group1, role: .microphone)
        let gameAudio = TimelineClip(name: "Game audio", content: .media(assetID: game), start: 0, sourceDuration: 20, role: .gameplay)
        timeline.tracks[0].clips = [gameClip]
        timeline.tracks[1].clips = [camClip]
        timeline.tracks[3].clips = [voice]
        timeline.tracks[4].clips = [gameAudio]
        XCTAssertEqual(AutoPan.apply(to: &timeline), 1)
        XCTAssertLessThan(timeline.tracks[3].clips[0].audio.pan, 0, "the voice leans left")
        XCTAssertEqual(timeline.tracks[4].clips[0].audio.pan, 0, "game audio is not the facecam's")
        // Running it again changes nothing; a centred facecam puts it back.
        XCTAssertEqual(AutoPan.apply(to: &timeline), 0)
        timeline.tracks[1].clips[0].transform.positionX = AnimatedDouble(0.5)
        XCTAssertEqual(AutoPan.apply(to: &timeline), 1)
        XCTAssertEqual(timeline.tracks[3].clips[0].audio.pan, 0)
        var none = Timeline.empty(name: "No cam", canvas: .vertical1080)
        none.tracks[0].clips = [gameClip]
        XCTAssertEqual(AutoPan.apply(to: &none), 0)
    }

    private let group1 = UUID()
}
