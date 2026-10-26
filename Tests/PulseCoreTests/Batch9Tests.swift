import XCTest
@testable import PulseCore

/// Roadmap batch 9: own laughter (#28), speaker names (#40), taste summary (#51), cold open (#59), safe-area
/// captions (#68).
final class Batch9Tests: XCTestCase {
    func testTheStreamersOwnLaughCountsMore() {
        var words: [TranscriptWord] = []
        for i in 0..<60 { words.append(TranscriptWord(text: "so", start: Double(i), end: Double(i) + 0.3, speaker: 0)) }
        for i in 0..<10 { words.append(TranscriptWord(text: "yeah", start: 100 + Double(i), end: 100 + Double(i) + 0.3, speaker: 1)) }
        XCTAssertEqual(EngagementModel.dominantSpeaker(words), 0)
        XCTAssertEqual(EngagementModel.laughWeight(speaker: 0, dominant: 0), 1.3)
        XCTAssertEqual(EngagementModel.laughWeight(speaker: 1, dominant: 0), 0.8)
        XCTAssertEqual(EngagementModel.laughWeight(speaker: nil, dominant: 0), 1)
        XCTAssertNil(EngagementModel.dominantSpeaker([TranscriptWord(text: "x", start: 0, end: 1)]))
        var mine = words
        mine.append(TranscriptWord(text: "hahaha", start: 30, end: 30.5, speaker: 0))
        var theirs = words
        theirs.append(TranscriptWord(text: "hahaha", start: 30, end: 30.5, speaker: 1))
        let a = EngagementModel.compute(duration: 120, audio: nil, transcript: Transcript(language: "en", words: mine, source: .demo), visual: nil)
        let b = EngagementModel.compute(duration: 120, audio: nil, transcript: Transcript(language: "en", words: theirs, source: .demo), visual: nil)
        XCTAssertGreaterThan(a.laughter[a.index(at: 30)], b.laughter[b.index(at: 30)])
    }

    func testSpeakerNamesComeFromIntroductions() {
        var words: [TranscriptWord] = []
        func say(_ text: String, _ t: Seconds, _ speaker: Int) { words.append(TranscriptWord(text: text, start: t, end: t + 0.3, speaker: speaker)) }
        say("Hey", 0, 0); say("chat,", 0.4, 0); say("this", 0.8, 0); say("is", 1.1, 0); say("Mark", 1.4, 0); say("today.", 1.8, 0)
        say("Hi", 3, 1); say("everyone", 3.4, 1); say("thanks", 4, 1); say("for", 4.3, 1); say("having", 4.6, 1); say("me", 5, 1)
        say("and", 20, 0); say("joined", 20.4, 0); say("by", 20.7, 0); say("Sarah", 21, 0)
        say("Hello", 22, 2)
        say("this", 40, 0); say("is", 40.3, 0); say("the", 40.6, 0); say("stream", 41, 0)
        let names = SpeakerNameSuggester.suggest(words: words)
        XCTAssertEqual(names[1], "Mark")
        XCTAssertEqual(names[2], "Sarah")
        XCTAssertNil(names[0], "the introducer isn't named by their own introduction")
        XCTAssertTrue(SpeakerNameSuggester.suggest(words: words.map { TranscriptWord(text: $0.text, start: $0.start, end: $0.end) }).isEmpty, "needs speaker labels")
    }

    func testTasteSummaryReadsInPlainWords() {
        var taste = TasteProfile()
        XCTAssertTrue(taste.summaryLines.isEmpty)
        for _ in 0..<6 {
            taste.learn(scores: ClipScores(hook: 0.9, emotion: 0.9, story: 0.1, entertainment: 0.8, audio: 0.5, visual: 0.5, reaction: 0.9, context: 0.5, ending: 0.5), tags: [.funny], liked: true)
            taste.learn(scores: ClipScores(hook: 0.1, emotion: 0.2, story: 0.9, entertainment: 0.2, audio: 0.5, visual: 0.5, reaction: 0.1, context: 0.5, ending: 0.5), tags: [.story], liked: false)
        }
        let lines = taste.summaryLines
        XCTAssertTrue(lines[0].hasPrefix("6 👍 · 6 👎"), lines[0])
        XCTAssertTrue(lines.contains { $0.hasPrefix("Leans toward") && ($0.contains("emotion") || $0.contains("funny")) }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.hasPrefix("Cares less about") && ($0.contains("story")) }, "\(lines)")
    }

    func testColdOpenPutsAFlashOfThePayoffFirst() {
        var timeline = Fixtures.simpleTimeline(clipDuration: 40)   // source 100…140
        let assetID = timeline.tracks[0].clips[0].content.assetID!
        timeline.markers = [Marker(time: 25, name: "Payoff", color: .orange)]
        let before = timeline.duration
        XCTAssertTrue(EditPolish.coldOpen(&timeline, assetID: assetID, payoffAtSource: 125))
        XCTAssertEqual(timeline.duration, before + 1.6, accuracy: 1e-6)
        let teaser = timeline.tracks[0].clips[0]
        XCTAssertEqual(teaser.name, "Cold Open")
        XCTAssertEqual(teaser.role, .graphic)
        XCTAssertEqual(teaser.start, 0)
        XCTAssertEqual(teaser.sourceIn, 124.7, accuracy: 1e-9)
        XCTAssertEqual(teaser.sourceDuration, 1.6, accuracy: 1e-9)
        XCTAssertEqual(teaser.transitionOut?.kind, .fadeToBlack)
        XCTAssertEqual(timeline.tracks[0].clips[1].start, 1.6, accuracy: 1e-9, "the story moved right")
        XCTAssertEqual(timeline.tracks[3].clips.count, 2, "a sound piece for the teaser")
        XCTAssertEqual(timeline.tracks[3].clips[0].linkGroup, teaser.linkGroup)
        XCTAssertEqual(timeline.markers.first { $0.name == "Payoff" }?.time ?? -1, 26.6, accuracy: 1e-9)
        XCTAssertTrue(EditQualityCheck.blackGaps(in: timeline.tracks[0].clips).isEmpty)
        XCTAssertFalse(EditPolish.coldOpen(&timeline, assetID: assetID, payoffAtSource: 125), "only once")
        var early = Fixtures.simpleTimeline(clipDuration: 40)
        XCTAssertFalse(EditPolish.coldOpen(&early, assetID: assetID, payoffAtSource: 102), "the payoff is already at the start")
        var settings = AISettings()
        settings.coldOpenShorts = true
        XCTAssertTrue(ShortBuildOptions(settings: settings).coldOpen)
    }

    func testCaptionsUnderPlatformUIAreNoted() {
        var timeline = Fixtures.simpleTimeline(clipDuration: 30)
        let words = [TranscriptWord(text: "hi", start: 100, end: 100.3)]
        timeline.captions = CaptionTrack.make(from: Transcript(language: "en", words: words, source: .demo), range: TimeRange(start: 100, end: 130),
                                              assetID: Fixtures.assetID, style: .tiktok, emphasize: false)
        timeline.captions?.style.positionY = 0.92
        let low = EditQualityCheck.run(&timeline, autofix: false)
        XCTAssertTrue(low.issues.contains { $0.title == "Captions under platform UI" }, "\(low.issues)")
        timeline.captions?.style.positionY = 0.7
        XCTAssertFalse(EditQualityCheck.run(&timeline, autofix: false).issues.contains { $0.title == "Captions under platform UI" })
    }
}
