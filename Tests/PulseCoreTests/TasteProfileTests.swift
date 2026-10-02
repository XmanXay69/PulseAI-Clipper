import XCTest
@testable import PulseCore

final class TasteProfileTests: XCTestCase {
    func candidate(_ tags: [ClipTag], story: Double, reaction: Double, potential: Int = 60) -> ClipCandidate {
        ClipCandidate(assetID: UUID(), range: TimeRange(start: 0, end: 30), payoffTime: 15, targetDuration: 30, potential: potential,
                      scores: ClipScores(hook: 0.6, emotion: 0.6, story: story, entertainment: 0.6, audio: 0.5, visual: 0.4, reaction: reaction, context: 0.7, ending: 0.6),
                      tags: tags, title: "", copy: .empty, transcriptSnippet: "")
    }

    func testLearnsToPreferFunnyReactionsOverSlowStories() {
        var taste = TasteProfile()
        let funny = candidate([.funny, .reaction], story: 0.3, reaction: 0.9)
        let story = candidate([.story, .conversation], story: 0.9, reaction: 0.2)
        XCTAssertEqual(taste.adjusted(funny), 60, "no ratings → no change")
        for _ in 0..<6 {
            taste.learn(scores: funny.scores, tags: funny.tags, liked: true)
            taste.learn(scores: story.scores, tags: story.tags, liked: false)
        }
        XCTAssertEqual(taste.ratings, 12)
        XCTAssertGreaterThan(taste.adjusted(funny), 70)
        XCTAssertLessThan(taste.adjusted(story), 50)
        // A new clip that looks like the liked ones ranks above one like the disliked ones.
        let newFunny = candidate([.funny], story: 0.4, reaction: 0.8, potential: 50)
        let newStory = candidate([.story], story: 0.8, reaction: 0.3, potential: 55)
        XCTAssertGreaterThan(taste.adjusted(newFunny), taste.adjusted(newStory))
        XCTAssertTrue(taste.summary.contains("Funny"), taste.summary)
    }

    func testOneRatingBarelyMovesThingsAndShiftIsBounded() {
        var taste = TasteProfile()
        let c = candidate([.hype], story: 0.5, reaction: 0.9)
        taste.learn(scores: c.scores, tags: c.tags, liked: true)
        XCTAssertLessThanOrEqual(abs(taste.adjusted(c) - 60), 4)
        for _ in 0..<200 { taste.learn(scores: c.scores, tags: c.tags, liked: true) }
        XCTAssertLessThanOrEqual(taste.adjusted(c), 85, "never more than +25")
    }

    func testApplyingTasteKeepsTheBaseScore() {
        var taste = TasteProfile()
        let c = candidate([.funny], story: 0.3, reaction: 0.9)
        for _ in 0..<12 { taste.learn(scores: c.scores, tags: c.tags, liked: true) }
        let once = [c].applyingTaste(taste)
        let twice = once.applyingTaste(taste)
        XCTAssertEqual(once[0].basePotential, 60)
        XCTAssertEqual(twice[0].potential, once[0].potential, "re-applying doesn't compound")
        XCTAssertEqual([c].applyingTaste(TasteProfile())[0].potential, 60)
    }
}
