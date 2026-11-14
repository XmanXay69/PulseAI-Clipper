import XCTest
@testable import PulseCore

/// #936 (a video's real retention imported and kept on its edit) and #937 (what the audience left during).
final class RetentionGraphTests: XCTestCase {
    func testYouTubeStudiosExportReads() throws {
        var csv = "Video position (%),Absolute audience retention (%),Relative retention performance (%)\n"
        for i in 0...100 { csv += "\(i),\(String(format: "%.2f", 100 - Double(i) * 0.6)),0.5\n" }
        let graph = try XCTUnwrap(RetentionImporter.parse(csv, duration: 600, source: "Table data.csv"))
        XCTAssertEqual(graph.points.count, 101)
        XCTAssertEqual(graph.watching(atPosition: 0), 1, accuracy: 0.001)
        XCTAssertEqual(graph.watching(atPosition: 0.5), 0.7, accuracy: 0.001)
        XCTAssertEqual(graph.watching(atPosition: 0.505), 0.697, accuracy: 0.001, "between two rows")
        XCTAssertEqual(graph.watching(at: 600, duration: 600), 0.4, accuracy: 0.001)
        XCTAssertEqual(graph.averageViewed, 0.7, accuracy: 0.005)
        XCTAssertEqual(graph.source, "Table data.csv")
        XCTAssertFalse(graph.isStale(for: 600))
        XCTAssertFalse(graph.isStale(for: 605), "a few seconds of difference still lines up")
        XCTAssertTrue(graph.isStale(for: 540))
    }

    func testOtherShapesOfTheSameTableReadAndJunkDoesNot() throws {
        // Fractions instead of percentages, a byte-order mark, quoted headers, the columns the other way round.
        let fractions = "\u{FEFF}\"Audience retention\",\"Position\"\n1.0,0\n0.8,0.25\n0.6,0.5\n0.5,0.75\n0.45,1\n"
        let a = try XCTUnwrap(RetentionImporter.parse(fractions))
        XCTAssertEqual(a.watching(atPosition: 0.5), 0.6, accuracy: 0.001)
        // Timecodes need the video's length; without it the last timecode stands in.
        let timed = "Time,Viewers watching (%)\n0:00,100\n0:30,80\n1:00,70\n2:00,50\n"
        let b = try XCTUnwrap(RetentionImporter.parse(timed, duration: 240))
        XCTAssertEqual(b.watching(at: 60, duration: 240), 0.7, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(RetentionImporter.parse(timed)).watching(atPosition: 1), 0.5, accuracy: 0.001)
        // A rewatch spike above 100 % is kept, not clipped.
        let spike = "Video position (%),Absolute audience retention (%)\n0,100\n10,130\n20,90\n30,80\n"
        XCTAssertEqual(try XCTUnwrap(RetentionImporter.parse(spike)).watching(atPosition: 0.1), 1.3, accuracy: 0.001)
        // Not a retention table: a views export, an empty file, two rows.
        XCTAssertNil(RetentionImporter.parse("Video title,Views\nA,100\nB,200\nC,300\nD,400\n"))
        XCTAssertNil(RetentionImporter.parse(""))
        XCTAssertNil(RetentionImporter.parse("Video position (%),Absolute audience retention (%)\n0,100\n50,60\n"))
    }

    /// A four-minute edit of one held shot with a punch-in every 20 s after the first minute.
    private func edit() -> Timeline {
        var timeline = Fixtures.simpleTimeline(clipDuration: 240)
        PunchInGenerator.apply(moments: stride(from: 70.0, to: 230, by: 20).map { .reaction($0) }, to: &timeline, trackID: timeline.tracks[0].id)
        return timeline
    }

    /// Retention that falls gently, except for a cliff of `drop` over ten seconds starting at `at`.
    private func graph(cliffAt at: Seconds, drop: Double, duration: Seconds = 240) -> RetentionGraph {
        var points: [RetentionGraph.Point] = []
        var watching = 1.0
        for second in 0...Int(duration) {
            points.append(RetentionGraph.Point(position: Double(second) / duration, watching: watching))
            let t = Double(second)
            watching -= t < 30 ? 0.006 : (t >= at && t < at + 10 ? drop / 10 : 0.0008)
        }
        return RetentionGraph(points: points, videoDuration: duration)
    }

    func testTheSteepestFallIsFoundAndBlamedOnWhatWasOnScreen() throws {
        let timeline = edit()
        // The first minute has no cut, zoom or pop-up: the shot is held from 12 s on. The cliff is at 40 s.
        let leaks = RetentionLearning.leaks(timeline: timeline, graph: graph(cliffAt: 40, drop: 0.12), signals: nil)
        let worst = try XCTUnwrap(leaks.first)
        XCTAssertEqual(worst.time, 40, accuracy: 5)
        XCTAssertEqual(worst.lost, 0.12, accuracy: 0.03)
        XCTAssertEqual(worst.cause, .heldShot)
        // A fall of the same size in the busy part isn't blamed on a held shot.
        let busy = try XCTUnwrap(RetentionLearning.leaks(timeline: timeline, graph: graph(cliffAt: 150, drop: 0.12), signals: nil).first)
        XCTAssertEqual(busy.time, 150, accuracy: 5)
        XCTAssertNotEqual(busy.cause, .heldShot)
        // A graph with no cliff has no leaks; the opening's own steep fall never counts.
        XCTAssertTrue(RetentionLearning.leaks(timeline: timeline, graph: graph(cliffAt: 500, drop: 0), signals: nil).isEmpty)
        // A graph from another cut of the video is not read against this one.
        XCTAssertTrue(RetentionLearning.leaks(timeline: timeline, graph: graph(cliffAt: 40, drop: 0.12, duration: 300), signals: nil).isEmpty)
        XCTAssertNil(RetentionLearning.observe(timeline: timeline, graph: graph(cliffAt: 40, drop: 0.12, duration: 300), signals: nil))
    }

    func testTheCoachSaysWhereViewersLeftAndTheGraphSurvivesASave() throws {
        var timeline = edit()
        timeline.retention = graph(cliffAt: 40, drop: 0.12)
        let review = EditCoach.review(timeline, analysis: nil)
        let told = try XCTUnwrap(review.suggestions.first { $0.id == "leak-1" })
        XCTAssertTrue(told.title.contains("0:4") || told.title.contains("0:3"), told.title)
        XCTAssertEqual(told.fix, .addZooms)
        XCTAssertEqual(told.severity, .recommended)
        let saved = try JSONDecoder().decode(Timeline.self, from: JSONEncoder().encode(timeline))
        XCTAssertEqual(saved.retention, timeline.retention)
        // Cut the edit shorter and the graph is called out as belonging to another cut instead.
        var shorter = timeline
        shorter.rippleDelete(range: TimeRange(start: 100, end: 160))
        let stale = EditCoach.review(shorter, analysis: nil)
        XCTAssertTrue(stale.suggestions.contains { $0.id == "retention-stale" })
        XCTAssertFalse(stale.suggestions.contains { $0.id.hasPrefix("leak-") })
        XCTAssertFalse(EditCoach.review(edit(), analysis: nil).suggestions.contains { $0.id.hasPrefix("leak-") || $0.id == "retention-stale" })
    }

    func testAChannelsProfileLearnsAcrossVideosAndTightensTheRulesItSupports() throws {
        let timeline = edit()
        var profile = RetentionProfile()
        XCTAssertTrue(profile.insights.isEmpty)
        XCTAssertNil(profile.lift(.heldShot))
        // Three videos whose viewers all left during the held first minute.
        for _ in 0..<3 {
            let seen = try XCTUnwrap(RetentionLearning.observe(timeline: timeline, graph: graph(cliffAt: 40, drop: 0.12), signals: nil))
            XCTAssertGreaterThan(seen.features[RetentionFeature.heldShot.rawValue]?.seconds ?? 0, 10)
            profile = profile.adding(seen)
        }
        XCTAssertEqual(profile.videos, 3)
        let lift = try XCTUnwrap(profile.lift(.heldShot))
        XCTAssertGreaterThan(lift, 1.25, "they left faster during held shots: enough to be called out")
        XCTAssertTrue(profile.insights.contains { $0.contains("held shots") && $0.contains("3 videos") }, "\(profile.insights)")
        // The rules follow: held shots get less room, by no more than a third.
        let standard = PacingRules.standard(for: .longForm)
        let learned = profile.adjusted(standard)
        XCTAssertLessThan(learned.maxStaticStretch, standard.maxStaticStretch)
        XCTAssertGreaterThanOrEqual(learned.maxStaticStretch, (standard.maxStaticStretch * 0.67).rounded() - 0.01)
        XCTAssertEqual(learned.maxEffectsPerMinute, standard.maxEffectsPerMinute, "nothing else moves")
        // One video is not a pattern, and an empty profile changes nothing.
        let one = RetentionProfile().adding(try XCTUnwrap(RetentionLearning.observe(timeline: timeline, graph: graph(cliffAt: 40, drop: 0.12), signals: nil)))
        XCTAssertNil(one.lift(.heldShot))
        XCTAssertEqual(RetentionProfile().adjusted(standard), standard)
        // The same video imported twice is one video.
        let seen = try XCTUnwrap(RetentionLearning.observe(timeline: timeline, graph: graph(cliffAt: 40, drop: 0.12), signals: nil))
        let once = RetentionProfile().adding(seen, video: "A").adding(seen, video: "A").adding(seen, video: "B")
        XCTAssertEqual(once.videos, 2)
        XCTAssertEqual(once.counted, ["A", "B"])
        // It survives a save inside the settings, and settings from before read as empty.
        var settings = AISettings()
        settings.retentionProfile = profile
        XCTAssertEqual(try JSONDecoder().decode(AISettings.self, from: JSONEncoder().encode(settings)).retentionProfile, profile)
    }
}
