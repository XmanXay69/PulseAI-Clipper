import XCTest
@testable import PulseCore

/// #541: an ending that cuts cleanly back to the opening.
final class LoopBuilderTests: XCTestCase {
    private typealias Word = LoopBuilder.Word

    /// Words spoken one after another with the given gaps before each.
    private func speech(_ items: [(String, Seconds, Seconds)]) -> [Word] {
        items.map { Word($0.0, start: $0.1, end: $0.2) }
    }

    func testAnEndingLeftHangingForTheOpeningIsPreferredToOneThatTrailsOff() throws {
        // 20 s short. The opening is loud (−12 dB); the last second and a half trails off to −45 dB.
        let words = speech([("So", 0.2, 0.4), ("this", 0.45, 0.7), ("happened", 0.75, 1.3),
                            ("we", 14.0, 14.2), ("pushed", 14.25, 14.6), ("the", 14.65, 14.8), ("ridge", 14.85, 15.3),
                            ("and", 15.6, 15.8), ("that's", 15.85, 16.1), ("when", 16.15, 16.5),
                            ("yeah", 18.6, 18.9), ("anyway", 19.0, 19.5)])
        let level: (Seconds) -> Double = { $0 > 17 ? -45 : -12 }
        let loop = try XCTUnwrap(LoopBuilder.find(duration: 20, words: words, level: level))
        XCTAssertEqual(loop.end, 16.5 + 0.12, accuracy: 0.05, "ends just after “when”, in the breath before the trail-off")
        XCTAssertEqual(loop.trim, 20 - loop.end, accuracy: 0.001)
        XCTAssertTrue(loop.reason.contains("when"), loop.reason)
        XCTAssertGreaterThan(loop.quality, loop.currentQuality)
        XCTAssertTrue(loop.isWorthOffering)
    }

    func testAQuestionOrAReturnToTheOpeningWordsMakesASeam() throws {
        let question = speech([("Watch", 0.1, 0.4), ("this", 0.45, 0.8), ("clutch", 0.85, 1.4),
                               ("did", 15.0, 15.2), ("he", 15.25, 15.4), ("make", 15.45, 15.7), ("it?", 15.75, 16.1),
                               ("um", 18.0, 18.3), ("so", 18.4, 18.6), ("yeah", 18.7, 19.2)])
        let asked = try XCTUnwrap(LoopBuilder.find(duration: 20, words: question, level: { _ in -14 }))
        XCTAssertEqual(asked.end, 16.22, accuracy: 0.05)
        XCTAssertTrue(asked.reason.contains("question"), asked.reason)

        let circle = speech([("The", 0.1, 0.3), ("clutch", 0.35, 0.9), ("nobody", 0.95, 1.4), ("believed", 1.45, 2.0),
                             ("what", 15.0, 15.3), ("a", 15.35, 15.45), ("clutch.", 15.5, 16.0),
                             ("okay", 18.5, 18.9), ("moving", 19.0, 19.3), ("on", 19.35, 19.6)])
        let back = try XCTUnwrap(LoopBuilder.find(duration: 20, words: circle, level: { _ in -14 }))
        XCTAssertEqual(back.end, 16.12, accuracy: 0.05)
        XCTAssertTrue(back.reason.contains("opened with"), back.reason)
    }

    func testItNeverCutsThroughAWordBeforeThePayoffOrTooMuchOfTheShort() throws {
        // Continuous speech with no breaths: nowhere clean to cut, so the ending stays.
        var run: [Word] = []
        var t = 0.0
        while t < 19.8 { run.append(Word("word", start: t, end: t + 0.2)); t += 0.2 }
        let kept = try XCTUnwrap(LoopBuilder.find(duration: 20, words: run, level: { _ in -14 }))
        XCTAssertEqual(kept.trim, 0)
        XCTAssertFalse(kept.isWorthOffering)

        // A lovely hanging "and" at 9 s is before the 70 % mark: not taken.
        let early = speech([("Open", 0.1, 0.5), ("and", 8.7, 9.0), ("later", 19.0, 19.6)])
        let stay = try XCTUnwrap(LoopBuilder.find(duration: 20, words: early, level: { _ in -14 }))
        XCTAssertEqual(stay.trim, 0)

        // The payoff at 17 s must stay: an ending at 16.5 is off the table.
        let words = speech([("Go", 0.1, 0.4), ("and", 16.2, 16.5), ("boom.", 17.2, 17.6), ("so", 18.6, 18.8), ("yeah", 19.0, 19.4)])
        let guarded = try XCTUnwrap(LoopBuilder.find(duration: 20, words: words, level: { _ in -14 }, keepUntil: 17))
        XCTAssertGreaterThanOrEqual(guarded.end, 18)
        // Too short to loop at all.
        XCTAssertNil(LoopBuilder.find(duration: 3, words: [], level: { _ in -14 }))
    }

    func testTheCoachOffersTheLoopOnAShortAndTrimsToIt() throws {
        // The fixture short shows 100…130 s of its recording. Its words leave "and that's when" hanging 26.5 s
        // in, then trail off.
        let at: Seconds = 100
        var words: [TranscriptWord] = [TranscriptWord(text: "So", start: at + 0.2, end: at + 0.4), TranscriptWord(text: "this", start: at + 0.45, end: at + 0.7),
                                       TranscriptWord(text: "happened", start: at + 0.75, end: at + 1.3)]
        var t = 3.5
        while t < 25 { words.append(TranscriptWord(text: "talking", start: at + t, end: at + t + 0.3)); t += 0.35 }
        words += [TranscriptWord(text: "and", start: at + 25.6, end: at + 25.8), TranscriptWord(text: "that's", start: at + 25.85, end: at + 26.1),
                  TranscriptWord(text: "when", start: at + 26.15, end: at + 26.5),
                  TranscriptWord(text: "yeah", start: at + 28.6, end: at + 28.9), TranscriptWord(text: "anyway", start: at + 29.0, end: at + 29.5)]
        let analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: 140, audio: Fixtures.audio(duration: 140, spikes: [112]),
                                     transcript: Transcript(words: words, source: .demo), profile: .gameplay)
        let timeline = Fixtures.simpleTimeline(clipDuration: 30)
        XCTAssertEqual(EditFormat.of(timeline), .short)

        let loop = try XCTUnwrap(LoopBuilder.find(in: timeline, analysis: analysis))
        XCTAssertEqual(loop.end, 26.62, accuracy: 0.06)
        XCTAssertTrue(loop.reason.contains("when"), loop.reason)
        let review = EditCoach.review(timeline, analysis: analysis)
        if loop.isWorthOffering, !review.suggestions.contains(where: { $0.id == "ending" }) {
            let offered = try XCTUnwrap(review.suggestions.first { $0.id == "loop" })
            XCTAssertEqual(offered.fix, .trimEnd(loop.trim))
            XCTAssertTrue(offered.detail.contains("when"), offered.detail)
        }
        // A long video isn't looped, and neither is an edit with nothing known about its recording.
        XCTAssertNil(LoopBuilder.find(in: Fixtures.simpleTimeline(clipDuration: 400), analysis: analysis))
        XCTAssertNil(LoopBuilder.find(in: timeline, analysis: nil))
    }
}
