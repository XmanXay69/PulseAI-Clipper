import XCTest
@testable import PulseCore

/// The genre button: what kind of video this is decides which editing style the auto-editor cuts in.
final class VideoGenreTests: XCTestCase {
    func testEveryGenreHasItsOwnLongFormStyleAndSaysWhereItsRulesCameFrom() {
        let genres = VideoGenre.allCases
        XCTAssertEqual(genres.count, 7)
        XCTAssertEqual(Set(genres.map(\.playbook.id)).count, genres.count, "no two genres cut the same way")
        for genre in genres {
            XCTAssertFalse(genre.playbook.style.isShortForm, "\(genre.rawValue) is a long video's style")
            XCTAssertEqual(VideoGenre.genre(forPlaybook: genre.playbook.id), genre)
            XCTAssertFalse(genre.displayName.isEmpty)
            XCTAssertFalse(genre.blurb.isEmpty)
            XCTAssertGreaterThanOrEqual(genre.sources.count, 2, genre.rawValue)
            for source in genre.sources {
                XCTAssertTrue(source.url.hasPrefix("https://"), source.url)
                XCTAssertFalse(source.gave.isEmpty)
            }
        }
        // Every long-form style is reachable from a genre; the phone short is a format, not a genre.
        let reachable = Set(genres.map(\.playbook.id))
        XCTAssertEqual(Set(EditorPlaybook.all.filter { !$0.style.isShortForm }.map(\.id)), reachable)
        XCTAssertNil(VideoGenre.genre(forPlaybook: EditorPlaybook.punchyShort.id))
        XCTAssertNil(VideoGenre.genre(forPlaybook: ""))
        XCTAssertTrue(VideoGenre.studyNote.contains("not learned by watching"))
    }

    func testTheSuggestedGenreFollowsTheKindOfRecording() {
        XCTAssertEqual(VideoGenre.suggested(for: .gameplayWithFacecam), .streamHighlights)
        XCTAssertEqual(VideoGenre.suggested(for: .gameplay), .gamingVideo)
        XCTAssertEqual(VideoGenre.suggested(for: .talkingHead), .commentary)
        XCTAssertEqual(VideoGenre.suggested(for: .podcast), .commentary)
        XCTAssertEqual(VideoGenre.suggested(for: .unknown), .challenge)
    }

    func testStreamHighlightsAndVlogCutTheWayTheyDescribe() {
        func options(_ playbook: EditorPlaybook) -> LongFormOptions { playbook.style.longFormOptions(.recommended(for: playbook.style)) }
        // A highlights video: clean cuts and a push-in on the reaction; no burned-in captions, memes or added music.
        let stream = options(.streamHighlights)
        XCTAssertTrue(stream.zooms && stream.coldOpen && stream.cutDeadAir)
        XCTAssertFalse(stream.captions || stream.memes || stream.music)
        XCTAssertEqual(stream.style?.rhythmZooms, false)
        XCTAssertEqual(stream.style?.silence, .balanced)
        XCTAssertEqual(stream.style?.fades, true, "a soft join between moments")
        XCTAssertGreaterThan(stream.zoomSpacing, options(.retention).zoomSpacing * 2, "far fewer zooms than an edited gaming video")
        // A vlog: music-led, quicker cuts, no caption wall.
        let vlog = options(.vlog)
        XCTAssertTrue(vlog.music && vlog.zooms && vlog.coldOpen)
        XCTAssertFalse(vlog.captions || vlog.memes)
        XCTAssertEqual(vlog.style?.rhythmZooms, true, "ten cuts a minute keeps the frame moving")
        XCTAssertTrue(EditorPlaybook.vlog.plantsTease)
        XCTAssertFalse(EditorPlaybook.streamHighlights.plantsTease)
        // The coach holds each to its own rules.
        XCTAssertLessThan(EditorPlaybook.streamHighlights.rules.maxEffectsPerMinute, EditorPlaybook.retention.rules.maxEffectsPerMinute)
    }

    func testAProjectRemembersItsGenreAndOldProjectsHaveNone() throws {
        var project = ProjectDocument(name: "Stream")
        XCTAssertNil(project.genre)
        XCTAssertNil(project.genrePlaybook)
        project.genre = .montage
        let saved = try JSONEncoder().encode(project)
        let again = try JSONDecoder().decode(ProjectDocument.self, from: saved)
        XCTAssertEqual(again.genre, .montage)
        XCTAssertEqual(again.genrePlaybook?.id, EditorPlaybook.onTheBeat.id)
        // A project from before genres, or one saved by a newer version with a genre this one doesn't know.
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: saved) as? [String: Any])
        json["genre"] = nil
        XCTAssertNil(try JSONDecoder().decode(ProjectDocument.self, from: try JSONSerialization.data(withJSONObject: json)).genre)
        json["genre"] = "hologram"
        XCTAssertNil(try JSONDecoder().decode(ProjectDocument.self, from: try JSONSerialization.data(withJSONObject: json)).genre)
    }
}
