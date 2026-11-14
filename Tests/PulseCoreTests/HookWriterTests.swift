import XCTest
@testable import PulseCore

/// #542: five on-screen opening lines for the first two seconds of a short.
final class HookWriterTests: XCTestCase {
    private func word(_ text: String, _ start: Seconds, _ end: Seconds) -> TranscriptWord { TranscriptWord(text: text, start: start, end: end) }

    func testFiveDifferentLinesOneOfEachKindShortEnoughToRead() {
        let words = [word("okay", 100.2, 100.5), word("one", 101, 101.2), word("more", 101.25, 101.5), word("fight.", 101.55, 102),
                     word("LET'S", 111.6, 111.9), word("GO!", 111.95, 112.4)]
        let lines = HookWriter.lines(words: words, range: TimeRange(start: 100, end: 120), payoff: 112, tags: [.hype, .gaming], seed: 7)
        XCTAssertEqual(lines.map(\.kind), HookWriter.Kind.allCases)
        XCTAssertEqual(Set(lines.map(\.text)).count, 5, "no two alike: \(lines.map(\.text))")
        for line in lines {
            XCTAssertFalse(line.text.isEmpty)
            XCTAssertLessThanOrEqual(line.text.count, HookWriter.maximumLength, line.text)
            XCTAssertEqual(line.text, line.text.uppercased())
            XCTAssertFalse(line.text.hasSuffix("."))
        }
        // The same clip gives the same lines; another seed may pick other templates but the same kinds.
        XCTAssertEqual(lines, HookWriter.lines(words: words, range: TimeRange(start: 100, end: 120), payoff: 112, tags: [.hype, .gaming], seed: 7))
        XCTAssertEqual(HookWriter.lines(words: words, range: TimeRange(start: 100, end: 120), payoff: 112, tags: [.hype], seed: 8).count, 5)
    }

    func testEveryLineIsTrueToTheClip() throws {
        let words = [word("wait", 50.2, 50.5), word("is", 51, 51.1), word("that", 51.15, 51.3), word("a", 51.35, 51.4), word("squad?", 51.45, 51.9),
                     word("no", 58.5, 58.7), word("way", 58.75, 59.0), word("we", 59.1, 59.2), word("won!", 59.25, 59.7)]
        let lines = HookWriter.lines(words: words, range: TimeRange(start: 50, end: 65), payoff: 59, tags: [.reaction], banner: "Victory Royale", seed: 1)
        let byKind = Dictionary(uniqueKeysWithValues: lines.map { ($0.kind, $0.text) })
        // The question is the one that was asked, as it was said.
        XCTAssertEqual(byKind[.question], "WAIT IS THAT A SQUAD?")
        // The tease counts down to the payoff that is really there: 9 s in.
        XCTAssertEqual(byKind[.tease], "WAIT 9 SECONDS")
        // The stakes name what the game put on screen.
        XCTAssertEqual(byKind[.stakes], "WATCH FOR THE VICTORY ROYALE")
        // The quote is made of words that were said.
        let quote = try XCTUnwrap(byKind[.quote])
        let said = Set(words.map { TranscriptWord.normalize($0.text) })
        XCTAssertTrue(quote.split(separator: " ").allSatisfy { said.contains(TranscriptWord.normalize(String($0))) }, quote)

        // A quote that only repeats the question gives way, and quotation marks never reach the screen.
        let echo = [word("did", 10.2, 10.4), word("you", 10.45, 10.6), word("see", 10.65, 10.9), word("that?", 10.95, 11.4)]
        let echoed = HookWriter.lines(words: echo, range: TimeRange(start: 10, end: 25), payoff: 11, tags: [.reaction])
        let asked = echoed.first { $0.kind == .question }?.text ?? ""
        let quoted = echoed.first { $0.kind == .quote }?.text ?? ""
        XCTAssertEqual(asked, "DID YOU SEE THAT?")
        XCTAssertLessThan(AnalyticsImporter.similarity(asked, quoted), 0.6, "\(asked) / \(quoted)")
        XCTAssertEqual(HookWriter.fit("“no way.”"), "NO WAY")
        XCTAssertTrue(echoed.allSatisfy { !$0.text.contains("“") && !$0.text.contains("\"") })
        // A payoff right at the start or far away gets a tease that doesn't lie about the wait.
        XCTAssertEqual(HookWriter.lines(words: words, range: TimeRange(start: 50, end: 65), payoff: 51, tags: [.reaction]).first { $0.kind == .tease }?.text, "DON'T BLINK")
        XCTAssertEqual(HookWriter.lines(words: [], range: TimeRange(start: 0, end: 90), payoff: 80, tags: []).first { $0.kind == .tease }?.text, "WAIT FOR THE END")
        // No words, no tags, an over-long banner: still five usable lines.
        let bare = HookWriter.lines(words: [], range: TimeRange(start: 0, end: 20), payoff: 10, tags: [], banner: "An extraordinarily long banner that would never fit")
        XCTAssertEqual(bare.count, 5)
        XCTAssertTrue(bare.allSatisfy { !$0.text.isEmpty && $0.text.count <= HookWriter.maximumLength })
        XCTAssertEqual(Set(bare.map(\.text)).count, 5)
    }

    func testAChosenLineGoesOverTheOpeningAndASecondChoiceReplacesIt() throws {
        var short = Fixtures.simpleTimeline(clipDuration: 20)
        XCTAssertNil(HookWriter.current(in: short))
        HookWriter.apply(HookWriter.Line(kind: .question, text: "CAN HE CLUTCH THIS?"), to: &short)
        XCTAssertEqual(HookWriter.current(in: short), "CAN HE CLUTCH THIS?")
        let clip = try XCTUnwrap(short.allClips.first { $0.name == HookWriter.clipName })
        XCTAssertLessThan(clip.start, 0.1)
        XCTAssertEqual(clip.duration, 2, accuracy: 0.01)
        XCTAssertTrue(clip.aiGenerated)
        XCTAssertLessThan(clip.transform.positionY.value, 0.4, "high in the frame, clear of the captions")
        XCTAssertEqual(short.duration, 20, accuracy: 0.001, "the short is no longer for it")

        HookWriter.apply(HookWriter.Line(kind: .tease, text: "WAIT 9 SECONDS"), to: &short)
        XCTAssertEqual(short.allClips.filter { $0.name == HookWriter.clipName }.count, 1)
        XCTAssertEqual(HookWriter.current(in: short), "WAIT 9 SECONDS")
        HookWriter.remove(from: &short)
        XCTAssertNil(HookWriter.current(in: short))

        // A text clip of your own with the same name isn't touched, and a pop-up already there isn't overwritten.
        var busy = Fixtures.simpleTimeline(clipDuration: 20)
        busy.tracks[2].clips = [TimelineClip(name: "Meme", content: .text(TextElement(text: "BRUH")), start: 0.5, sourceIn: 0, sourceDuration: 1)]
        HookWriter.apply(HookWriter.Line(kind: .claim, text: "NOBODY SAW THIS COMING"), to: &busy)
        XCTAssertTrue(busy.allClips.contains { $0.name == "Meme" })
        XCTAssertEqual(HookWriter.current(in: busy), "NOBODY SAW THIS COMING")
    }
}
