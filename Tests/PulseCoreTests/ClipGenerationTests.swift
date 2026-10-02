import XCTest
@testable import PulseCore

final class ClipGenerationTests: XCTestCase {
    func makeInput(duration: Seconds = 1200, spikes: [Seconds]) -> ClipGenerationInput {
        let special = spikes.flatMap { [($0, "NO"), ($0 + 0.4, "WAY!"), ($0 + 1.2, "hahaha")] }
        return ClipGenerationInput(assetID: Fixtures.assetID, duration: duration,
                                   audio: Fixtures.audio(duration: duration, spikes: spikes),
                                   transcript: Fixtures.transcript(duration: duration, special: special),
                                   visual: nil, profile: .gameplayWithFacecam)
    }

    func testFindsCandidatesAroundExcitingMoments() {
        let spikes: [Seconds] = [130, 455, 802, 1010]
        let generator = ClipGenerator(input: makeInput(spikes: spikes), settings: ClipGenerationSettings(targetDuration: 30, aggressiveness: 0.5, minimumPotential: 0))
        let candidates = generator.generate()
        XCTAssertGreaterThanOrEqual(candidates.count, 3)
        // Every spike should be covered by some candidate.
        for s in spikes {
            XCTAssertTrue(candidates.contains { $0.range.contains(s) }, "spike at \(s) not covered")
        }
        // The top candidates are the spikes.
        let top = candidates.prefix(4)
        XCTAssertTrue(top.allSatisfy { c in spikes.contains { c.range.contains($0) } })
        for c in candidates {
            XCTAssertGreaterThanOrEqual(c.duration, 30 * 0.6 - 0.01)
            XCTAssertLessThanOrEqual(c.duration, 30 * 1.25)
            XCTAssertGreaterThan(c.payoffTime, c.range.start)
            XCTAssertLessThan(c.payoffTime, c.range.end)
            XCTAssertFalse(c.title.isEmpty)
            XCTAssertFalse(c.copy.titles.isEmpty)
            XCTAssertTrue((1...99).contains(c.potential))
        }
        // Sorted by potential, no heavy overlaps.
        XCTAssertEqual(candidates.map(\.potential), candidates.map(\.potential).sorted(by: >))
        for (i, a) in candidates.enumerated() {
            for b in candidates.dropFirst(i + 1) {
                XCTAssertLessThanOrEqual(a.range.iou(b.range), 0.3 + 1e-9)
            }
        }
    }

    func testPayoffSitsAfterSetup() {
        let generator = ClipGenerator(input: makeInput(spikes: [600]), settings: ClipGenerationSettings(targetDuration: 30, minimumPotential: 0))
        let best = generator.generate().first { $0.range.contains(600) }!
        let setup = (best.payoffTime - best.range.start) / best.duration
        XCTAssertGreaterThan(setup, 0.25, "clip should include setup before the payoff")
        XCTAssertTrue(best.tags.contains(.funny) || best.tags.contains(.reaction))
    }

    func testReshapeKeepsIdentityAndChangesLength() {
        let generator = ClipGenerator(input: makeInput(spikes: [300]), settings: ClipGenerationSettings(targetDuration: 30, minimumPotential: 0))
        let c = generator.generate().first { $0.range.contains(300) }!
        let shorter = generator.reshape(c, targetDuration: 15)
        XCTAssertEqual(shorter.id, c.id)
        XCTAssertLessThan(shorter.duration, c.duration)
        XCTAssertTrue(shorter.range.contains(c.payoffTime))
    }

    func testShortRecordingBecomesSingleCandidate() {
        let input = ClipGenerationInput(assetID: Fixtures.assetID, duration: 28, audio: Fixtures.audio(duration: 28), transcript: nil, visual: nil)
        let result = ClipGenerator(input: input, settings: ClipGenerationSettings(targetDuration: 30, minimumPotential: 0)).generate()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].range.duration, 28, accuracy: 1e-9)
    }

    func testAudioOnlyStillWorks() {
        let input = ClipGenerationInput(assetID: Fixtures.assetID, duration: 900, audio: Fixtures.audio(duration: 900, spikes: [200, 700]), transcript: nil, visual: nil)
        let result = ClipGenerator(input: input, settings: ClipGenerationSettings(targetDuration: 15, minimumPotential: 0)).generate()
        XCTAssertTrue(result.contains { $0.range.contains(200) })
        XCTAssertTrue(result.contains { $0.range.contains(700) })
    }

    func testCandidateBudgetScalesWithLength() {
        let short = ClipGenerator(input: ClipGenerationInput(assetID: Fixtures.assetID, duration: 600, audio: nil, transcript: nil, visual: nil), settings: ClipGenerationSettings())
        let long = ClipGenerator(input: ClipGenerationInput(assetID: Fixtures.assetID, duration: 7200, audio: nil, transcript: nil, visual: nil), settings: ClipGenerationSettings())
        XCTAssertEqual(short.candidateBudget, 3)
        XCTAssertEqual(long.candidateBudget, 26)
    }

    func testTitleGeneratorQuotesThePunchline() {
        let words = [
            TranscriptWord(text: "okay", start: 0, end: 0.3),
            TranscriptWord(text: "watch", start: 0.4, end: 0.7),
            TranscriptWord(text: "this.", start: 0.8, end: 1.0),
            TranscriptWord(text: "No", start: 5, end: 5.2),
            TranscriptWord(text: "way", start: 5.3, end: 5.5),
            TranscriptWord(text: "he", start: 5.6, end: 5.7),
            TranscriptWord(text: "did", start: 5.8, end: 6.0),
            TranscriptWord(text: "that!", start: 6.1, end: 6.4),
        ]
        let copy = TitleGenerator.generate(words: words, payoff: 5.5, tags: [.reaction, .funny], seed: 7)
        XCTAssertTrue(copy.titles[0].contains("NO WAY HE DID THAT"), copy.titles[0])
        XCTAssertTrue(copy.hashtags.contains("#shorts"))
        XCTAssertTrue(copy.shortsTitle.count <= 100)
        let again = TitleGenerator.generate(words: words, payoff: 5.5, tags: [.reaction, .funny], seed: 7)
        XCTAssertEqual(copy, again, "deterministic for the same seed")
    }

    func testHookAdviceFlagsEarlyPayoff() {
        let input = makeInput(spikes: [500])
        let generator = ClipGenerator(input: input, settings: ClipGenerationSettings(targetDuration: 30, minimumPotential: 0))
        let advice = HookAnalyzer.analyze(range: TimeRange(start: 499, end: 529), payoff: 500.5, signals: generator.signals, transcript: input.transcript, hookScore: 0.2)
        if case .startEarlier = advice.recommendation {} else { XCTFail("expected startEarlier, got \(advice.recommendation)") }
    }

    func testCandidateSorts() {
        let a = ClipCandidate(assetID: Fixtures.assetID, range: TimeRange(start: 100, end: 130), payoffTime: 115, targetDuration: 30, potential: 50, scores: ClipScores(), tags: [.story], title: "A", copy: .empty, transcriptSnippet: "")
        let b = ClipCandidate(assetID: Fixtures.assetID, range: TimeRange(start: 10, end: 25), payoffTime: 20, targetDuration: 15, potential: 90, scores: ClipScores(), tags: [.funny], title: "B", copy: .empty, transcriptSnippet: "")
        XCTAssertEqual(CandidateSort.potential.sort([a, b]).map(\.title), ["B", "A"])
        XCTAssertEqual(CandidateSort.timestamp.sort([a, b]).map(\.title), ["B", "A"])
        XCTAssertEqual(CandidateSort.duration.sort([a, b]).map(\.title), ["B", "A"])
        XCTAssertEqual(CandidateSort.category.sort([a, b]).map(\.title), ["B", "A"])
    }
}

final class ClipEndingTests: XCTestCase {
    func testEndingRunsThroughTheLaughterAfterThePayoff() {
        // A spike at 150 s followed by 8 s of laughing.
        var special: [(Seconds, String)] = []
        for t in stride(from: 150.5, to: 158, by: 0.5) { special.append((t, "hahaha")) }
        let input = ClipGenerationInput(assetID: Fixtures.assetID, duration: 400,
                                        audio: Fixtures.audio(duration: 400, spikes: [150]),
                                        transcript: Fixtures.transcript(duration: 400, special: special), visual: nil)
        let generator = ClipGenerator(input: input, settings: ClipGenerationSettings(targetDuration: 15, minimumPotential: 0))
        let range = generator.window(forPayoff: 150.5)
        XCTAssertGreaterThanOrEqual(range.end, 157.9, "the clip keeps the laugh")
        XCTAssertLessThanOrEqual(range.duration, 15 * 1.25 + 0.3)
        // And it never ends halfway through a word.
        let words = input.transcript!.words
        XCTAssertFalse(words.contains { $0.start < range.end - 0.3 && $0.end > range.end })
    }
}
