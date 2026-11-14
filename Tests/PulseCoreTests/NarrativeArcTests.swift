import XCTest
@testable import PulseCore

/// #581: the moments read as a story, ordered to tell it, with what is missing named.
final class NarrativeArcTests: XCTestCase {
    private func moment(_ start: Seconds, potential: Int = 60, tags: [ClipTag] = []) -> LongFormSegment {
        LongFormSegment(range: TimeRange(start: start, end: start + 30), payoff: start + 20, potential: potential, title: "", tags: tags)
    }

    private func transcript(_ lines: [(Seconds, String)]) -> Transcript {
        var words: [TranscriptWord] = []
        for (start, line) in lines {
            for (i, text) in line.split(separator: " ").enumerated() {
                words.append(TranscriptWord(text: String(text), start: start + Double(i) * 0.4, end: start + Double(i) * 0.4 + 0.3))
            }
        }
        return Transcript(words: words, source: .demo)
    }

    func testAChallengeStreamReadsAsGoalSetbacksTriesAndAnEnding() throws {
        let goal = moment(60), setback = moment(600, tags: [.fail]), retry = moment(1500), another = moment(2400, tags: [.rage]),
            ending = moment(3300, potential: 95, tags: [.hype])
        let said = transcript([(62, "today we are going to beat the whole game with no deaths"),
                               (603, "oh no no no I died to the first boss"),
                               (1502, "okay okay one more try this time we dodge"),
                               (2405, "are you kidding me how did that hit"),
                               (3305, "we did it finally let's go")])
        let arc = NarrativeArcBuilder.build(moments: [ending, retry, goal, another, setback], transcript: said, duration: 3600)
        XCTAssertEqual(arc.beat(of: goal.id), .goal)
        XCTAssertEqual(arc.beat(of: setback.id), .obstacle)
        XCTAssertEqual(arc.beat(of: retry.id), .attempt)
        XCTAssertEqual(arc.beat(of: another.id), .obstacle)
        XCTAssertEqual(arc.beat(of: ending.id), .result)
        XCTAssertTrue(arc.missing.isEmpty)
        // Told in order: the goal, what happened on the way as it happened, the ending last.
        XCTAssertEqual(arc.order, [goal.id, setback.id, retry.id, another.id, ending.id])
        XCTAssertEqual(arc.summary, "A goal, 2 obstacles, an attempt and a result.")
        // The reading says why.
        let why = try XCTUnwrap(arc.placements.first { $0.momentID == goal.id })
        XCTAssertTrue(why.evidence.contains("going to"), why.evidence)
        XCTAssertGreaterThan(why.confidence, 0.25)
    }

    func testAGoalSaidLateComesFirstAndTheStrongestEndingGoesLast() {
        // The streamer explains the challenge twenty minutes in, after a first failed run; two wins near the end.
        let fail = moment(300, tags: [.fail]), explained = moment(1200), win = moment(3000, potential: 70, tags: [.hype]),
            bigWin = moment(2700, potential: 96, tags: [.hype])
        let said = transcript([(302, "I died again why"),
                               (1203, "so the challenge is we have to win without healing that is the goal"),
                               (2702, "no way we won we did it"),
                               (3002, "gg that's it finally")])
        let arc = NarrativeArcBuilder.build(moments: [fail, explained, win, bigWin], transcript: said, duration: 3600)
        XCTAssertEqual(arc.beat(of: explained.id), .goal)
        XCTAssertEqual(arc.order.first, explained.id, "the goal is told first even though it was said later")
        XCTAssertEqual(arc.order.last, bigWin.id, "the bigger of two endings closes the video")
        XCTAssertEqual(Set(arc.order), Set([fail.id, explained.id, win.id, bigWin.id]), "no moment is dropped")
    }

    func testWhatIsMissingIsNamedWithSomethingToDoAboutIt() {
        // Three mid-stream fails and nothing else: no goal stated, no ending.
        let fails = [moment(1000, tags: [.fail]), moment(1500, tags: [.rage]), moment(2000, tags: [.fail])]
        let said = transcript([(1002, "oh no I died"), (1502, "why is this so hard"), (2002, "dead again unlucky")])
        let arc = NarrativeArcBuilder.build(moments: fails, transcript: said, duration: 3600)
        XCTAssertTrue(arc.missing.contains(.goal))
        XCTAssertTrue(arc.missing.contains(.result))
        XCTAssertFalse(arc.missing.contains(.obstacle))
        XCTAssertEqual(arc.count(.obstacle), 3)
        XCTAssertTrue(arc.summary.hasPrefix("3 obstacles."), arc.summary)
        XCTAssertTrue(arc.summary.contains("Missing: a goal"), arc.summary)
        for beat in StoryBeat.allCases { XCTAssertGreaterThan(beat.adviceWhenMissing.count, 40) }

        // No transcript at all: tags and position still give a reading, and nothing crashes on no moments.
        let silent = NarrativeArcBuilder.build(moments: [moment(30), moment(1800, tags: [.fail]), moment(3400, potential: 99, tags: [.hype])],
                                               transcript: nil, duration: 3600)
        XCTAssertEqual(silent.placements.map(\.beat), [.goal, .obstacle, .result])
        let none = NarrativeArcBuilder.build(moments: [], transcript: nil, duration: 3600)
        XCTAssertEqual(none.missing, StoryBeat.allCases)
        XCTAssertEqual(none.summary, "No story beats found. Missing: a goal, an obstacle, an attempt and a result.")
    }
}
