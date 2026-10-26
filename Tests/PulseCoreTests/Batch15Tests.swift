import XCTest
@testable import PulseCore

/// Roadmap batch 15: media trash (#22), speaker colours by default (#236), ducking attack/release (#268), settings.
final class Batch15Tests: XCTestCase {
    func testMediaTrashKeepsClipsPlaying() throws {
        var doc = ProjectDocument(name: "P")
        let main = Fixtures.mediaAsset()
        var spare = MediaAsset(name: "Spare", path: "/tmp/spare.mov", kind: .video)
        spare.id = UUID()
        doc.media = [main, spare]
        doc.primaryAssetID = main.id
        doc.timelines = [Fixtures.simpleTimeline()]
        XCTAssertTrue(doc.trashMedia(id: main.id))
        XCTAssertEqual(doc.visibleMedia.map(\.name), ["Spare"])
        XCTAssertEqual(doc.primaryAssetID, spare.id, "the main recording moves to what's left")
        XCTAssertNotNil(doc.asset(id: main.id), "clips still find it")
        XCTAssertTrue(doc.usedAssetIDs.contains(main.id))
        XCTAssertTrue(doc.emptyMediaTrash().isEmpty, "a used file stays in the trash")
        XCTAssertTrue(doc.trashMedia(id: spare.id))
        XCTAssertEqual(doc.emptyMediaTrash().map(\.name), ["Spare"], "an unused one goes")
        XCTAssertTrue(doc.restoreMedia(id: main.id))
        XCTAssertFalse(doc.restoreMedia(id: main.id))
        XCTAssertEqual(doc.primaryAssetID, main.id)
        let back = try ProjectStore.makeDecoder().decode(ProjectDocument.self, from: ProjectStore.makeEncoder().encode(doc))
        XCTAssertFalse(back.media[0].isTrashed)
        XCTAssertFalse(try JSONDecoder().decode(MediaAsset.self, from: Data(#"{"id":"11111111-2222-3333-4444-555555555555","path":"/x"}"#.utf8)).isTrashed)
    }

    func testTwoVoicesAreColouredFromTheStart() {
        var words: [TranscriptWord] = []
        for i in 0..<12 { words.append(TranscriptWord(text: "w\(i)", start: Double(i), end: Double(i) + 0.5, speaker: (i / 3) % 2)) }
        let two = CaptionTrack.make(from: Transcript(words: words, speakers: [Speaker(id: 0, name: "Host"), Speaker(id: 1, name: "Guest")], source: .demo),
                                    range: TimeRange(start: 0, end: 12), assetID: Fixtures.assetID, style: .bold, emphasize: false)
        XCTAssertTrue(two.isColoredBySpeaker)
        XCTAssertTrue(two.showSpeakerLabels)
        XCTAssertEqual(two.style(forSpeaker: 0), two.style)
        let one = CaptionTrack.make(from: Transcript(words: words.map { TranscriptWord(text: $0.text, start: $0.start, end: $0.end, speaker: 0) }, source: .demo),
                                    range: TimeRange(start: 0, end: 12), assetID: Fixtures.assetID, style: .bold, emphasize: false)
        XCTAssertFalse(one.isColoredBySpeaker)
        XCTAssertFalse(one.showSpeakerLabels)
    }

    func testDuckTimingAndSettingsDecode() throws {
        let audio = try JSONDecoder().decode(AudioSettings.self, from: Data(#"{"duckAttack":0.001,"duckRelease":9}"#.utf8))
        XCTAssertEqual(audio.duckAttack, 0.02, accuracy: 1e-9)
        XCTAssertEqual(audio.duckRelease, 3, accuracy: 1e-9)
        XCTAssertEqual(AudioSettings().duckAttack, 0.15, accuracy: 1e-9)
        var clip = Fixtures.simpleTimeline(clipDuration: 10).tracks[3].clips[0]
        clip.audio.duckUnderDialogue = true
        clip.audio.duckAmountDB = -12
        clip.audio.duckRelease = 1.5
        let ramps = DuckingPlanner.envelope(for: clip, dialogue: [TimeRange(start: 2, end: 4)], attack: clip.audio.duckAttack, release: clip.audio.duckRelease)
        // The planner keeps a 0.1 s margin around the words; the release runs after it.
        XCTAssertTrue(ramps.contains { abs($0.time - 5.6) < 1e-9 && $0.gain == 1 }, "comes back a slow 1.5 s after the words: \(ramps)")
        XCTAssertTrue(ramps.contains { abs($0.time - 1.75) < 1e-9 && $0.gain == 1 }, "starts going down 0.15 s before the words")
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(settings.timelineFollowsPlayhead)
        XCTAssertTrue(settings.batchPausesOnLowBattery)
    }
}
