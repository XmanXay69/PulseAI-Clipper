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
    }

    /// Each genre says plainly what was watched for it. Only a genre whose videos taught it something claims so.
    func testEachGenreSaysWhatWasWatchedAndNoMoreThanThat() {
        for genre in VideoGenre.allCases {
            XCTAssertTrue(genre.studyNote.contains("14 November 2026"), genre.rawValue)
            XCTAssertTrue(genre.studyNote.contains("starting points"), genre.rawValue)
            XCTAssertFalse(genre.watchedSources.isEmpty, "\(genre.rawValue) lists the videos it was checked against")
            for source in genre.watchedSources {
                XCTAssertTrue(source.url.hasPrefix("https://www.youtube.com/watch?v="), source.url)
            }
            XCTAssertEqual(Set(genre.sources.map(\.url)).count, genre.sources.count, "\(genre.rawValue) lists each source once")
        }
        // The stream videos did not show how a long highlights video looks, so that genre must not say it was learned from them.
        let stream = VideoGenre.streamHighlights.studyNote
        XCTAssertTrue(stream.contains("not learned by watching"))
        XCTAssertFalse(stream.contains("checked against"))
        for genre in VideoGenre.allCases where genre != .streamHighlights {
            XCTAssertTrue(genre.studyNote.contains("checked against"), genre.rawValue)
            XCTAssertFalse(genre.studyNote.contains("not learned by watching"), genre.rawValue)
        }
    }

    /// The numbers that two or more of the videos watched disagreed with, as they were moved on 14 November 2026.
    func testTheStudyMovedTheNumbersTheVideosDisagreedWith() {
        // Snappy zooms and pop-ins: about a tenth of a second, not slower (Finzar, MortarMarv, ItsProger, Isaac).
        XCTAssertEqual(EditorPlaybook.retention.rules.zoomRamp, 0.12, accuracy: 0.001)
        XCTAssertFalse(EditorPlaybook.retention.rules.zoomsGlide)
        XCTAssertEqual(EditorPlaybook.retention.rules.maxCaptionWords, 3)
        // The spoken promise lands about twenty seconds in and a new section about every two minutes.
        for playbook in [EditorPlaybook.story, .vlog] {
            XCTAssertEqual(playbook.rules.hookDeadline, 20, playbook.id)
            XCTAssertEqual(playbook.rules.rehookInterval, 120, playbook.id)
        }
        // A vlog-style edit runs about six hard cuts a minute, not ten.
        XCTAssertEqual(EditorPlaybook.vlog.style.cutsPerMinute, 6)
        XCTAssertEqual(EditorPlaybook.vlog.style.averageShotLength, 9)
        // A cinematic opening may be a fast run of shots.
        XCTAssertTrue(EditorPlaybook.smooth.style.opensFast)
        // What the videos agreed on is in the principles, not only in the numbers.
        XCTAssertTrue(EditorPlaybook.retention.principles.contains { $0.detail.contains("twelve frames") })
        XCTAssertTrue(EditorPlaybook.smooth.principles.contains { $0.detail.contains("every second or fourth beat") })
        XCTAssertTrue(EditorPlaybook.onTheBeat.principles.contains { $0.detail.contains("every second to fourth beat") })
        // Left alone on purpose: the videos split on them, or did not cover them.
        XCTAssertEqual(EditorPlaybook.commentary.style.cutsPerMinute, 3)
        XCTAssertEqual(EditorPlaybook.streamHighlights.style.cutsPerMinute, 6)
        XCTAssertEqual(EditorPlaybook.retention.style.cutsPerMinute, 12)
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
        // A vlog: music-led, no caption wall. Six cuts a minute, as the vlog and story videos watched run, leaves the
        // zooms to the reactions instead of punching in on every sentence (from eight cuts a minute up they do).
        let vlog = options(.vlog)
        XCTAssertTrue(vlog.music && vlog.zooms && vlog.coldOpen)
        XCTAssertFalse(vlog.captions || vlog.memes)
        XCTAssertEqual(vlog.style?.rhythmZooms, false, "six cuts a minute is a steady pace, not a jump-cut one")
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
