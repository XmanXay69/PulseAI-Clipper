import XCTest
@testable import PulseCore

final class Batch47Tests: XCTestCase {
    // MARK: #343 — two-pass encoding

    func testTwoPassSettingRoundTripsAndOnlyRunsForH264AndHEVC() throws {
        var settings = ExportSettings()
        XCTAssertFalse(settings.twoPass)
        XCTAssertFalse(settings.runsTwoPasses)
        settings.twoPass = true
        XCTAssertTrue(settings.runsTwoPasses)
        settings.codec = .proRes422
        XCTAssertFalse(settings.runsTwoPasses, "ProRes has no rate control to plan")
        settings.codec = .hevc
        XCTAssertTrue(settings.runsTwoPasses)
        settings.audioOnly = true
        XCTAssertFalse(settings.runsTwoPasses)
        settings.audioOnly = false
        let back = try JSONDecoder().decode(ExportSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertTrue(back.twoPass)
        let old = try JSONDecoder().decode(ExportSettings.self, from: Data(#"{"presetID":"tiktok"}"#.utf8))
        XCTAssertFalse(old.twoPass)
    }

    // MARK: #291 — tempo and license per track

    func testBPMFromABeatGrid() {
        let grid = (0..<40).map { Double($0) * 0.5 }   // 120 BPM
        XCTAssertEqual(MusicPicker.bpm(fromBeats: grid) ?? 0, 120, accuracy: 0.01)
        let swung = (0..<40).map { Double($0) * 0.6 + ($0 % 2 == 0 ? 0.03 : 0) }   // ≈100 BPM with a wobble
        XCTAssertEqual(MusicPicker.bpm(fromBeats: swung) ?? 0, 100, accuracy: 6)
        XCTAssertNil(MusicPicker.bpm(fromBeats: [0, 1, 2]), "too few beats")
        XCTAssertNil(MusicPicker.bpm(fromBeats: [0, 5, 10, 15, 20]), "12 BPM is not a tempo")
        XCTAssertNil(MusicPicker.bpm(fromBeats: [0, 0, 0, 0]))
    }

    func testPaceRangesAndPreferenceOrder() {
        XCTAssertTrue(MusicPicker.bpmRange(for: .fast).contains(140))
        XCTAssertFalse(MusicPicker.bpmRange(for: .fast).contains(80))
        XCTAssertTrue(MusicPicker.bpmRange(for: .slow).contains(70))
        XCTAssertTrue(MusicPicker.bpmRange(for: .medium).contains(100))
        func track(_ id: String, bpm: Double?) -> OnlineTrack { OnlineTrack(videoID: id, title: id, channel: "c", duration: 180, mood: "lofi", bpm: bpm) }
        let ordered = MusicPicker.preferring([track("slow", bpm: 70), track("unknown", bpm: nil), track("fast", bpm: 140), track("fast2", bpm: 150)], pace: .fast)
        XCTAssertEqual(ordered.map(\.videoID), ["fast", "fast2", "unknown", "slow"])
        // Medium pace keeps the given order among equals.
        let same = MusicPicker.preferring([track("a", bpm: 100), track("b", bpm: 110)], pace: .medium)
        XCTAssertEqual(same.map(\.videoID), ["a", "b"])
    }

    func testTrackLicenseLineAndOldLibraryEntries() throws {
        var track = OnlineTrack(videoID: "abc123", title: "Sunny Day", channel: "Beats", duration: 200, mood: "lofi")
        XCTAssertNil(track.bpm)
        XCTAssertEqual(track.licenseLine, "Creative Commons Attribution (CC BY) · https://www.youtube.com/watch?v=abc123")
        track.bpm = 92.4
        track.license = OnlineTrack.defaultLicense
        XCTAssertEqual(track.licenseLine, "Creative Commons Attribution (CC BY) · 92 BPM · https://www.youtube.com/watch?v=abc123")
        XCTAssertTrue(MusicPicker.creditBlock([track]).contains("92 BPM"))
        let old = try JSONDecoder().decode(OnlineTrack.self, from: Data(#"{"videoID":"x","title":"t","channel":"c","duration":100,"mood":"lofi","addedAt":0}"#.utf8))
        XCTAssertNil(old.bpm)
        XCTAssertNil(old.license)
        let back = try JSONDecoder().decode(OnlineTrack.self, from: JSONEncoder().encode(track))
        XCTAssertEqual(back.bpm, 92.4)
    }

    func testWiderSearchAddsAPhrasePerMood() {
        for pace in MusicPace.allCases {
            let (mood, queries) = MusicPicker.queries(for: [.gaming], pace: pace)
            XCTAssertTrue(queries.contains { $0.contains("free to use") && $0.contains(mood) })
            XCTAssertGreaterThanOrEqual(queries.count, 4)
        }
    }
}
