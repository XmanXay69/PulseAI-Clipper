import XCTest
@testable import PulseCore

final class EditCoachTests: XCTestCase {
    /// Talking from `from` to `to` at 2.5 words/s, sentence breaks every 8 words.
    func words(from: Seconds, to: Seconds, skipping gaps: [TimeRange] = []) -> Transcript {
        var list: [TranscriptWord] = []
        var t = from, i = 0
        while t < to {
            if gaps.contains(where: { $0.contains(t) }) { t += 0.4; continue }
            list.append(TranscriptWord(text: (i + 1) % 8 == 0 ? "okay." : "so", start: t, end: t + 0.32))
            t += 0.4
            i += 1
        }
        return Transcript(language: "en", words: list, source: .demo)
    }

    func analysis(silences: [TimeRange], spikes: [Seconds] = [115]) -> MediaAnalysis {
        MediaAnalysis(assetID: Fixtures.assetID, duration: 200,
                      audio: Fixtures.audio(duration: 200, spikes: spikes, silences: silences),
                      transcript: words(from: 0.5, to: 199, skipping: silences))
    }

    func testSlowStartGetsATrimSuggestionAndTrimmingRaisesTheHook() throws {
        let a = analysis(silences: [TimeRange(start: 100, end: 103)])
        var timeline = Fixtures.simpleTimeline(clipDuration: 30) // source 100…130
        let review = EditCoach.review(timeline, analysis: a)
        XCTAssertEqual(review.prediction.format, .short)
        let trim = try XCTUnwrap(review.suggestions.first { $0.id == "hook-trim" })
        guard case .trimStart(let seconds) = trim.fix else { return XCTFail("expected a trim fix") }
        XCTAssertEqual(seconds, 2.9, accuracy: 0.6)
        XCTAssertTrue(review.suggestions.contains { $0.fix == .addCaptions }, "no captions yet")

        timeline.rippleDelete(range: TimeRange(start: 0, end: seconds))
        let after = EditCoach.review(timeline, analysis: a)
        let hookBefore = review.prediction.factors.first { $0.name == "Hook" }!.value
        let hookAfter = after.prediction.factors.first { $0.name == "Hook" }!.value
        XCTAssertGreaterThan(hookAfter, hookBefore)
        XCTAssertFalse(after.suggestions.contains { $0.id == "hook-trim" })
        XCTAssertGreaterThan(after.prediction.score, review.prediction.score)
    }

    func testDeadAirIsFlaggedAndGoesAwayOnceCut() {
        let gaps = [TimeRange(start: 108, end: 110.5), TimeRange(start: 118, end: 121)]
        let a = analysis(silences: gaps)
        var timeline = Fixtures.simpleTimeline(clipDuration: 30)
        let before = EditCoach.review(timeline, analysis: a)
        XCTAssertTrue(before.suggestions.contains { $0.fix == .removeDeadAir })
        timeline.removeSourceRanges(gaps, assetID: Fixtures.assetID, reason: .silence)
        let after = EditCoach.review(timeline, analysis: a)
        XCTAssertFalse(after.suggestions.contains { $0.fix == .removeDeadAir })
        let pacing = { (r: EditReview) in r.prediction.factors.first { $0.name == "Pacing" }!.value }
        XCTAssertGreaterThan(pacing(after), pacing(before))
    }

    func testPolishCountsAndOverZoomingIsCalledOut() {
        let a = analysis(silences: [])
        var timeline = Fixtures.simpleTimeline(clipDuration: 30)
        let bare = EditCoach.review(timeline, analysis: a)
        timeline.captions = CaptionTrack.make(from: a.transcript!, range: TimeRange(start: 100, end: 130), assetID: Fixtures.assetID, style: .tiktok, emphasize: true)
        PunchInGenerator.apply(moments: [.reaction(15)], to: &timeline, trackID: timeline.tracks[0].id)
        let polished = EditCoach.review(timeline, analysis: a)
        XCTAssertGreaterThan(polished.prediction.score, bare.prediction.score)
        XCTAssertFalse(polished.suggestions.contains { $0.id == "captions" || $0.id == "zooms" })
        // Twenty zooms in 30 s is too many.
        var busy = PunchInSettings()
        busy.minimumSpacing = 1
        PunchInGenerator.apply(moments: stride(from: 1.0, to: 29, by: 1.4).map { .reaction($0) }, to: &timeline, trackID: timeline.tracks[0].id, settings: busy)
        XCTAssertTrue(EditCoach.review(timeline, analysis: a).suggestions.contains { $0.id == "over-zoom" })
    }

    func testColdOpenCopiesTheMomentToTheFrontAndShiftsTheRest() throws {
        var timeline = Fixtures.simpleTimeline(clipDuration: 30)
        var music = TimelineClip(name: "Bed", content: .media(assetID: UUID()), start: 0, sourceDuration: 30, role: .music)
        music.audio.volume = AnimatedDouble(0.3)
        timeline.tracks[4].clips = [music]
        timeline.markers = [Marker(time: 15, name: "Payoff")]
        try timeline.insertColdOpen(from: TimeRange(start: 14, end: 18))
        XCTAssertEqual(timeline.duration, 34, accuracy: 1e-6)
        let video = timeline.tracks[0].clips
        XCTAssertEqual(video.count, 2)
        XCTAssertEqual(video[0].start, 0, accuracy: 1e-9)
        XCTAssertEqual(video[0].sourceIn, 114, accuracy: 1e-9, "the teaser shows source 114…118")
        XCTAssertEqual(video[0].duration, 4, accuracy: 1e-9)
        XCTAssertEqual(video[1].start, 4, accuracy: 1e-9)
        XCTAssertEqual(video[1].sourceIn, 100, accuracy: 1e-9)
        // Linked audio comes along; music doesn't get duplicated.
        XCTAssertEqual(timeline.tracks[3].clips.count, 2)
        XCTAssertEqual(timeline.tracks[3].clips[0].linkGroup, video[0].linkGroup)
        XCTAssertNotEqual(video[0].linkGroup, video[1].linkGroup)
        XCTAssertEqual(timeline.tracks[4].clips.count, 1)
        XCTAssertEqual(timeline.markers.first { $0.name == "Payoff" }?.time ?? 0, 19, accuracy: 1e-9)
        XCTAssertTrue(timeline.markers.contains { $0.name == "Cold Open" && $0.time == 0 })
    }
}
