import XCTest
@testable import PulseCore

final class Batch25Tests: XCTestCase {
    // MARK: #149 track colour, rename, reorder

    func testTrackColourRoundTripsAndOldTracksDecode() throws {
        var track = Track(kind: .audio, name: "A2 Music", color: .purple)
        let data = try JSONEncoder().encode(track)
        let back = try JSONDecoder().decode(Track.self, from: data)
        XCTAssertEqual(back.color, .purple)
        let old = try JSONDecoder().decode(Track.self, from: Data(#"{"id":"\#(UUID().uuidString)","kind":"video","name":"V1","clips":[]}"#.utf8))
        XCTAssertNil(old.color)
        track.color = nil
        XCTAssertNil(track.color)
    }

    func testMoveTrackClampsAndReorders() {
        var t = Timeline(name: "t", canvas: .landscape1080, tracks: [Track(kind: .video, name: "V1"), Track(kind: .audio, name: "A1"), Track(kind: .audio, name: "A2")])
        let a2 = t.tracks[2].id
        XCTAssertEqual(t.moveTrack(id: a2, by: -1), 1)
        XCTAssertEqual(t.tracks.map(\.name), ["V1", "A2", "A1"])
        XCTAssertEqual(t.moveTrack(id: a2, by: -5), 0, "clamped at the top")
        XCTAssertEqual(t.tracks.map(\.name), ["A2", "V1", "A1"])
        XCTAssertEqual(t.moveTrack(id: a2, by: 9), 2, "clamped at the bottom")
        XCTAssertEqual(t.tracks.map(\.name), ["V1", "A1", "A2"])
        XCTAssertNil(t.moveTrack(id: UUID(), by: 1))
    }

    // MARK: #287 beats live with the analysis

    func testAnalysisBeatsDecodeAsOptional() throws {
        var analysis = MediaAnalysis(assetID: UUID(), duration: 120)
        XCTAssertNil(analysis.beats)
        analysis.beats = [0.5, 1.0, 1.5]
        let back = try JSONDecoder().decode(MediaAnalysis.self, from: JSONEncoder().encode(analysis))
        XCTAssertEqual(back.beats, [0.5, 1.0, 1.5])
    }

    // MARK: #298 sound packs

    func testSoundPacksMapToLibrarySounds() {
        let names = Set(SoundLibrary.effects.map(\.name))
        for pack in SoundPack.allCases where pack != .pulse {
            for (job, name) in pack.preferences {
                XCTAssertTrue(["hit", "whoosh"].contains(job))
                XCTAssertTrue(names.contains(name), "\(pack) → \(name) must be a library sound")
            }
            XCTAssertEqual(SoundPack.matching(pack.preferences), pack)
        }
        XCTAssertEqual(SoundPack.matching([:]), .pulse)
        XCTAssertNil(SoundPack.matching(["hit": "Impact", "whoosh": "Glitch"]), "a hand-picked mix is no pack")
        XCTAssertTrue(SoundPack.pulse.preferences.isEmpty)
    }

    // MARK: #357 settings flag

    func testThumbnailAfterExportDefaultsOff() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertFalse(settings.thumbnailAfterExport)
    }
}
