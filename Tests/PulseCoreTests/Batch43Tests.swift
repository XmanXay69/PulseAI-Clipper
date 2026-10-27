import XCTest
@testable import PulseCore

final class Batch43Tests: XCTestCase {
    // MARK: #282 — raw solo

    func testRawSoloRoundTripsAndOnlyCountsWhileSoloed() throws {
        var track = Track(kind: .audio, name: "A1")
        XCTAssertFalse(track.playsRaw)
        track.rawSolo = true
        XCTAssertFalse(track.playsRaw, "raw solo needs the solo")
        track.isSolo = true
        XCTAssertTrue(track.playsRaw)
        let back = try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(track))
        XCTAssertTrue(back.rawSolo)
        XCTAssertFalse(try JSONDecoder().decode(Track.self, from: Data(#"{"id":"\#(UUID().uuidString)","kind":"audio","name":"old","clips":[]}"#.utf8)).rawSolo)
    }

    // MARK: #116 — hand-made pieces carried into the next build

    func testCarryOverKeepsYourClipsMarkersAndNotes() {
        let primary = UUID(), logo = UUID()
        var old = Timeline.empty(name: "Edit 1", canvas: .landscape1080)
        var ai = TimelineClip(name: "Cut", content: .media(assetID: primary), start: 0, sourceDuration: 100)
        ai.aiGenerated = true
        old.tracks[0].clips = [ai]
        old.tracks[1].clips = [TimelineClip(name: "Logo", content: .media(assetID: logo), start: 10, sourceDuration: 5)]
        var manualCut = TimelineClip(name: "Manual", content: .media(assetID: primary), start: 30, sourceDuration: 5)
        manualCut.aiGenerated = false
        old.tracks[2].clips = [TimelineClip(name: "Title", content: .text(TextElement(text: "HI")), start: 2, sourceDuration: 3)]
        old.markers = [Marker(time: 20, name: "Mine"), Marker(time: 40, name: "AI", aiGenerated: true)]
        old.notes = "Remember the sponsor"
        old.captions = CaptionTrack(sourceAssetID: primary, words: [CaptionWord(text: "hi", start: 0, end: 1)], style: .tiktok)
        old.coverTime = 12
        let carry = TimelineCarryOver.capture(from: old, primaryAssetID: primary)
        XCTAssertEqual(carry.clips.map(\.name).sorted(), ["Logo", "Title"], "the AI cut of the primary recording is not carried")
        XCTAssertEqual(carry.markers.map(\.name), ["Mine"])
        XCTAssertEqual(carry.captionStyle?.presetName, CaptionStyle.tiktok.presetName)
        XCTAssertFalse(carry.isEmpty)

        var fresh = Timeline.empty(name: "Edit 2", canvas: .landscape1080)
        var cut = TimelineClip(name: "Cut", content: .media(assetID: primary), start: 0, sourceDuration: 60)
        cut.aiGenerated = true
        fresh.tracks[0].clips = [cut]
        fresh.markers = [Marker(time: 5, name: "Chapter", aiGenerated: true)]
        fresh.notes = "Built by PULSE"
        fresh.captions = CaptionTrack(sourceAssetID: primary, words: [CaptionWord(text: "hi", start: 0, end: 1)], style: .bold)
        let placed = carry.apply(to: &fresh)
        XCTAssertEqual(placed, 2)
        XCTAssertTrue(fresh.allClips.contains { $0.name == "Logo" && $0.start == 10 })
        XCTAssertTrue(fresh.textTracks.flatMap(\.clips).contains { $0.name == "Title" })
        XCTAssertEqual(fresh.markers.map(\.name), ["Chapter", "Mine"])
        XCTAssertTrue(fresh.notes.hasPrefix("Remember the sponsor"))
        XCTAssertEqual(fresh.captions?.style.presetName, CaptionStyle.tiktok.presetName)
        XCTAssertEqual(fresh.coverTime, 12)
        XCTAssertTrue(TimelineCarryOver.capture(from: fresh, primaryAssetID: primary).clips.count >= 2)
        XCTAssertTrue(TimelineCarryOver(clips: [], markers: [], notes: "", captionStyle: nil, captionsEnabled: nil, coverTime: nil).isEmpty)
    }

    // MARK: #348 — HEVC 10-bit

    func testHEVC10IsAnMP4CodecWithoutAlpha() {
        XCTAssertEqual(VideoCodec.hevc10.fileExtension, "mp4")
        XCTAssertFalse(VideoCodec.hevc10.isProRes)
        XCTAssertFalse(VideoCodec.hevc10.supportsAlpha)
        XCTAssertTrue(VideoCodec.hevc10.displayName.contains("10"))
        XCTAssertTrue(VideoCodec.allCases.contains(.hevc10))
    }
}
