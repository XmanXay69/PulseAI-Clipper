import XCTest
@testable import PulseCore

/// Roadmap batch 5a: idle screens (#32/#33), custom vocabulary (#43), why this moment (#49/#50), make it
/// shorter (#64), shorts from the edit (#69), YouTube copy (#94), pause shortening (#96).
final class Batch5Tests: XCTestCase {
    /// 20 minutes of talk with a 60 s frozen screen at 600 s and a 10 s one at 900 s.
    func streamWithIdleScreens() -> (MediaAsset, MediaAnalysis) {
        let duration: Seconds = 1200
        let idle = [TimeRange(start: 600, end: 660), TimeRange(start: 900, end: 910)]
        var words: [TranscriptWord] = []
        var t = 0.5, i = 0
        while t < duration - 1 {
            if !idle.contains(where: { $0.expanded(by: 1).contains(t) }) {
                words.append(TranscriptWord(text: (i + 1) % 8 == 0 ? "okay." : "so", start: t, end: t + 0.32))
                i += 1
            }
            t += 0.4
        }
        for s in stride(from: 100.0, to: 1150, by: 150) { for k in 0..<4 { words.append(TranscriptWord(text: "hahaha", start: s + Double(k) * 0.5, end: s + Double(k) * 0.5 + 0.3)) } }
        let motion: [Float] = (0..<1200).map { s in idle.contains { $0.contains(Double(s)) } ? 0.001 : 0.03 }
        let visual = VisualFeatureSeries(hop: 1, motion: motion, brightness: [Float](repeating: 0.5, count: 1200), sceneCuts: [], faces: [])
        let analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: duration,
                                     audio: Fixtures.audio(duration: duration, spikes: Array(stride(from: 100.0, to: 1150, by: 150))),
                                     visual: visual,
                                     transcript: Transcript(language: "en", words: words.sorted { $0.start < $1.start }, source: .demo), profile: .gameplay)
        return (Fixtures.mediaAsset(duration: duration), analysis)
    }

    // MARK: #32 / #33

    func testIdleScreensAreStillAndSilent() {
        let (_, analysis) = streamWithIdleScreens()
        let words = analysis.transcript!.words
        let plain = IdleScreens.ranges(visual: analysis.visual, words: words, cues: [], duration: 1200)
        XCTAssertEqual(plain.count, 1, "\(plain)")
        XCTAssertEqual(plain[0].start, 600, accuracy: 1.5)
        XCTAssertEqual(plain[0].end, 660, accuracy: 1.5)

        let cued = IdleScreens.ranges(visual: analysis.visual, words: words, cues: [HUDEvent(time: 902, kind: .idleScreen, text: "BRB")], duration: 1200)
        XCTAssertEqual(cued.count, 2, "a cue lowers the bar for the short one: \(cued)")
        XCTAssertEqual(cued[1].start, 900, accuracy: 1.5)

        // Talking over a frozen screen (a story over a loading screen) isn't idle.
        var talking = words
        for t in stride(from: 600.0, to: 660, by: 0.4) { talking.append(TranscriptWord(text: "so", start: t, end: t + 0.32)) }
        XCTAssertTrue(IdleScreens.ranges(visual: analysis.visual, words: talking, cues: [], duration: 1200).isEmpty)

        // No frame analysis: strong cards still count for a few seconds.
        let noVisual = IdleScreens.ranges(visual: nil, words: [], cues: [HUDEvent(time: 100, kind: .idleScreen, text: "BE RIGHT BACK"),
                                                                        HUDEvent(time: 200, kind: .idleScreen, text: "LOADING")], duration: 1200)
        XCTAssertEqual(noVisual.count, 1)
        XCTAssertEqual(noVisual[0].start, 99.5, accuracy: 0.01)
        XCTAssertEqual(HUDCues.event(forText: "be right back", at: 1)?.kind, .idleScreen)
        XCTAssertEqual(HUDEvent.Kind.idleScreen.weight, 0)
        XCTAssertEqual(HUDCues.signal(events: [HUDEvent(time: 50, kind: .idleScreen, text: "LOADING")], duration: 100, step: 0.5).max(), 0)
    }

    func testEditMyVODCutsIdleScreensInsideKeptSections() {
        let (asset, analysis) = streamWithIdleScreens()
        let plan = LongFormEditor.planMoments(analysis: analysis, options: LongFormOptions())
        var moment = plan.moments[0]
        moment.range = TimeRange(start: 560, end: 700)
        moment.payoff = 580
        let result = LongFormEditor.build(asset: asset, analysis: analysis, options: LongFormOptions(coldOpen: false), segments: [moment])
        let idle = result.timeline.removedSections.filter { $0.reason == .idleScreen }
        XCTAssertFalse(idle.isEmpty, result.report)
        XCTAssertTrue(idle.contains { $0.sourceRange.start <= 602 && $0.sourceRange.end >= 658 }, "\(idle.map(\.sourceRange))")
        XCTAssertTrue(EditQualityCheck.blackGaps(in: result.timeline.tracks[0].clips).isEmpty)
    }

    // MARK: #43

    func testCustomVocabularyFixesNearMissesAndSpelledOutNames() {
        let words = ["I", "played", "valerant", "with", "x", "q", "c", "and", "sea", "of", "theives.", "The", "valorant", "lobby", "them"]
            .enumerated().map { TranscriptWord(text: $1, start: Double($0), end: Double($0) + 0.5) }
        let transcript = Transcript(language: "en", words: words, source: .demo)
        let fixed = TranscriptCorrector.correct(transcript, vocabulary: ["Valorant", "xQc", "Sea of Thieves", "them"])
        let texts = fixed.transcript.words.map(\.text)
        XCTAssertEqual(texts, ["I", "played", "Valorant", "with", "xQc", "and", "Sea of Thieves.", "The", "Valorant", "lobby", "them"], "\(texts)")
        XCTAssertEqual(fixed.changes, 4, "valerant, x q c, sea of theives, valorant (capitalised)")
        let xqc = fixed.transcript.words[4]
        XCTAssertEqual(xqc.start, 4)
        XCTAssertEqual(xqc.end, 6.5, "a merged word spans its pieces")
        XCTAssertEqual(fixed.transcript.words[6].start, 8)
        // No vocabulary, or nothing close: untouched.
        XCTAssertEqual(TranscriptCorrector.correct(transcript, vocabulary: []).changes, 0)
        XCTAssertEqual(TranscriptCorrector.correct(transcript, vocabulary: ["Minecraft"]).changes, 0)
        XCTAssertEqual(Levenshtein.distance("valerant", "valorant"), 1)
        XCTAssertEqual(Levenshtein.distance("", "abc"), 3)
    }

    // MARK: #49 / #50

    func testWhyThisMomentNamesTheSignals() {
        let (_, analysis) = streamWithIdleScreens()
        let candidate = ClipGenerator.candidate(for: TimeRange(start: 85, end: 125), analysis: analysis, settings: ClipGenerationSettings())
        let why = MomentExplanation.explain(candidate: candidate, analysis: analysis)
        XCTAssertTrue(why.signals.contains { $0.name == "Laughter" }, "\(why.signals)")
        XCTAssertTrue(why.signals.contains { $0.name == "Loudness" || $0.name == "Surprise" }, "\(why.signals)")
        XCTAssertTrue(why.summary.contains("laugh"), why.summary)
        XCTAssertTrue(zip(why.signals, why.signals.dropFirst()).allSatisfy { $0.value >= $1.value }, "strongest first")
        var banner = analysis
        banner.hudEvents = [HUDEvent(time: 101, kind: .win, text: "VICTORY")]
        let bannerWhy = MomentExplanation.explain(candidate: candidate, analysis: banner)
        XCTAssertTrue(bannerWhy.summary.contains("win banner"), "\(bannerWhy.summary) | \(bannerWhy.signals)")
        let dull = ClipGenerator.candidate(for: TimeRange(start: 300, end: 330), analysis: analysis, settings: ClipGenerationSettings())
        XCTAssertFalse(MomentExplanation.explain(candidate: dull, analysis: analysis).summary.isEmpty)
    }

    // MARK: #64

    func testMakeItShorterKeepsThePayoffAndLandsOnWords() {
        let (_, analysis) = streamWithIdleScreens()
        let original = ClipGenerator.candidate(for: TimeRange(start: 70, end: 125), analysis: analysis, settings: ClipGenerationSettings())
        let shorter = ClipGenerator.shorten(original, by: 0.2, analysis: analysis, settings: ClipGenerationSettings())
        XCTAssertEqual(shorter.id, original.id)
        XCTAssertEqual(shorter.title, original.title)
        XCTAssertTrue(shorter.userAdjusted)
        XCTAssertEqual(shorter.duration, original.duration * 0.8, accuracy: original.duration * 0.12, "\(original.range) → \(shorter.range)")
        XCTAssertTrue(shorter.range.contains(original.payoffTime))
        XCTAssertGreaterThanOrEqual(shorter.range.start, original.range.start)
        XCTAssertLessThanOrEqual(shorter.range.end, original.range.end)
        let words = analysis.transcript!.words
        XCTAssertTrue(words.contains { abs($0.start - 0.08 - shorter.range.start) < 0.05 || abs($0.start - 0.05 - shorter.range.start) < 0.05 }, "starts on a word")
        XCTAssertTrue(words.contains { abs($0.end + 0.25 - shorter.range.end) < 0.05 }, "ends after a word")
        // Too short to trim: unchanged range.
        var tiny = original
        tiny.range = TimeRange(start: 100, end: 108)
        XCTAssertEqual(ClipGenerator.shorten(tiny, by: 0.2, analysis: analysis, settings: ClipGenerationSettings()).range, tiny.range)
    }

    // MARK: #69 / #94

    func testShortsFromTheEditAndYouTubeCopy() {
        let (asset, analysis) = streamWithIdleScreens()
        let result = LongFormEditor.build(asset: asset, analysis: analysis)
        let shorts = LongFormEditor.shorts(from: result.timeline, analysis: analysis, settings: ClipGenerationSettings(), count: 3)
        XCTAssertEqual(shorts.count, 3, result.report)
        for s in shorts {
            XCTAssertGreaterThanOrEqual(s.duration, 15)
            XCTAssertLessThanOrEqual(s.duration, 60.01)
            XCTAssertTrue(s.range.contains(s.payoffTime))
            XCTAssertTrue(result.timeline.tracks[0].clips.contains { $0.role != .graphic && $0.sourceRange.contains(s.range) }, "inside one story piece")
        }
        XCTAssertFalse(shorts[0].range.overlaps(shorts[1].range))
        XCTAssertTrue(zip(shorts, shorts.dropFirst()).allSatisfy { $0.range.start < $1.range.start }, "stream order")

        let copy = try! XCTUnwrap(result.timeline.copy)
        XCTAssertEqual(copy.titles.count, 3, "\(copy.titles)")
        XCTAssertTrue(copy.titles.allSatisfy { $0.count <= 70 && !$0.isEmpty })
        XCTAssertTrue(copy.tiktokCaption.contains("Chapters") && copy.tiktokCaption.contains("#"), copy.tiktokCaption)
        XCTAssertTrue(copy.titles.contains { $0.contains("moments") || $0.contains("stream") }, "\(copy.titles)")
    }

    // MARK: #96

    func testPausesArePlayedFasterInsteadOfCut() throws {
        var timeline = Fixtures.simpleTimeline(clipDuration: 60)   // source 100…160 on V and A
        var words: [TranscriptWord] = []
        var t = 100.5
        while t < 160 {
            words.append(TranscriptWord(text: "so", start: t, end: t + 0.3))
            t += (t > 119.5 && t < 120.5) ? 2.4 : 0.4   // one 2.1 s pause around 120
        }
        let before = timeline.duration
        let count = EditPolish.shortenPauses(&timeline, words: words, after: 0)
        XCTAssertEqual(count, 1)
        let pause = try XCTUnwrap(timeline.tracks[0].clips.first { $0.name == "Pause" })
        XCTAssertEqual(pause.speed, 1.6, accuracy: 1e-9)
        XCTAssertEqual(pause.sourceDuration, 2.1 - 0.3, accuracy: 0.05)
        XCTAssertEqual(timeline.duration, before - pause.sourceDuration * (1 - 1 / 1.6), accuracy: 0.01)
        XCTAssertEqual(timeline.tracks[0].clips.count, 3)
        XCTAssertEqual(timeline.tracks[3].clips.count, 3, "the linked audio splits too")
        XCTAssertTrue(EditQualityCheck.blackGaps(in: timeline.tracks[0].clips).isEmpty)
        let audioPause = try XCTUnwrap(timeline.tracks[3].clips.first { $0.name == "Pause" })
        XCTAssertEqual(audioPause.start, pause.start, accuracy: 1e-6)
        XCTAssertEqual(audioPause.speed, 1.6, accuracy: 1e-9)
        // Already-shortened pauses are left alone on a second pass.
        XCTAssertEqual(EditPolish.shortenPauses(&timeline, words: words, after: 0), 0)
    }
}
