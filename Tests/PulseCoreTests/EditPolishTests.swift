import XCTest
@testable import PulseCore

final class EditPolishTests: XCTestCase {
    let asset = UUID()

    /// V1 + A1 pieces cut from one source, back to back on the timeline.
    func cutTimeline(_ pieces: [(sourceIn: Seconds, length: Seconds)]) -> Timeline {
        var v = Track(kind: .video, name: "V1"), a = Track(kind: .audio, name: "A1"), t = Track(kind: .text, name: "T1")
        var at: Seconds = 0
        for p in pieces {
            let g = UUID()
            v.clips.append(TimelineClip(name: "p", content: .media(assetID: asset), start: at, sourceIn: p.sourceIn, sourceDuration: p.length, linkGroup: g, role: .main))
            a.clips.append(TimelineClip(name: "p", content: .media(assetID: asset), start: at, sourceIn: p.sourceIn, sourceDuration: p.length, linkGroup: g, role: .microphone))
            at += p.length
        }
        t.clips = []
        return Timeline(name: "t", canvas: .landscape1080, tracks: [v, t, a])
    }

    func testSliversWithoutAWordGo() {
        var t = cutTimeline([(0, 5), (6, 0.2), (7, 0.25), (8, 5)])
        let removed = EditPolish.removeMicroFragments(&t, words: [TranscriptWord(text: "no", start: 7.02, end: 7.2)])
        XCTAssertEqual(removed, 1, "the 0.25 s piece holds a whole word and stays")
        XCTAssertEqual(t.tracks[0].clips.count, 3)
        XCTAssertEqual(t.duration, 10.25, accuracy: 0.001, "rippled closed")
        XCTAssertTrue(EditQualityCheck.blackGaps(in: t.tracks[0].clips).isEmpty)
    }

    func testEveryDialogueCutGetsAFade() {
        var t = cutTimeline([(0, 3), (5, 3)])
        XCTAssertEqual(EditPolish.addCutFades(&t), 2)
        XCTAssertTrue(t.tracks[2].clips.allSatisfy { $0.audio.fadeIn >= EditPolish.cutFade && $0.audio.fadeOut >= EditPolish.cutFade })
        XCTAssertEqual(EditPolish.addCutFades(&t), 0, "idempotent")
    }

    func testJumpCutsAlternateFramingAndResetPerSegment() {
        // Jumps between 1→2, 2→3 (same segment); piece 4 starts a new segment.
        var t = cutTimeline([(0, 3), (5, 3), (10, 3), (100, 3), (105, 3)])
        let zoomed = EditPolish.jumpCutZooms(&t, from: 0, segmentStarts: [0, 9], scale: 1.06)
        let z = t.tracks[0].clips.sorted { $0.start < $1.start }.map(\.transform.zoom.value)
        XCTAssertEqual(z[0], 1, accuracy: 1e-9)
        XCTAssertEqual(z[1], 1.06, accuracy: 1e-9)
        XCTAssertEqual(z[2], 1, accuracy: 1e-9)
        XCTAssertEqual(z[3], 1, accuracy: 1e-9, "new segment starts wide")
        XCTAssertEqual(z[4], 1.06, accuracy: 1e-9)
        XCTAssertEqual(zoomed, 2)
        XCTAssertTrue(t.tracks[2].clips.allSatisfy { $0.transform.zoom.value == 1 }, "audio untouched")
    }

    func testDeadSpansSkipQuietStretchesButKeepAction() {
        let step: Seconds = 0.5
        var excitement = [Float](repeating: 0.3, count: 200)
        // 40–50 s: no talking, nothing happening. 60–70 s: no talking but a big moment on screen.
        for i in 120..<140 { excitement[i] = 0.9 }
        var words: [TranscriptWord] = []
        for i in 0..<250 {
            let t = Double(i) * 0.4   // (adding 0.4 repeatedly drifts past the 40 s / 50 s edges)
            if !(40..<50).contains(t) && !(60..<70).contains(t) { words.append(TranscriptWord(text: "so", start: t, end: t + 0.3)) }
        }
        let spans = EditPolish.deadSpans(in: TimeRange(start: 0, end: 100), words: words, excitement: excitement, step: step)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].start, 40.6, accuracy: 0.2)
        XCTAssertEqual(spans[0].end, 49.4, accuracy: 0.2)
    }

    func testMusicDropsOutOnThePunchline() {
        var t = Timeline(name: "t", canvas: .landscape1080, tracks: [Track(kind: .video, name: "V1"), Track(kind: .audio, name: "A2 Music")])
        var bed = TimelineClip(name: "bed", content: .media(assetID: asset), start: 0, sourceDuration: 120, role: .music)
        bed.audio.volume = AnimatedDouble(0.08)
        t.tracks[1].clips = [bed]
        XCTAssertEqual(EditPolish.musicDrops(&t, at: [30, 80]), 2)
        let v = t.tracks[1].clips[0].audio.volume
        XCTAssertEqual(v.value(at: 20), 0.08, accuracy: 1e-6)
        XCTAssertEqual(v.value(at: 30.5), 0, accuracy: 1e-6)
        XCTAssertEqual(v.value(at: 40), 0.08, accuracy: 1e-6)
        XCTAssertEqual(v.value(at: 80.5), 0, accuracy: 1e-6, "the second drop is there too")
        XCTAssertEqual(v.value(at: 90), 0.08, accuracy: 1e-6)
    }

    func testCheckFindsAndFixesMechanicalProblems() {
        var t = cutTimeline([(0, 5), (6, 0.1), (8, 5)])
        // A gap on the main track and loud, unducked music.
        t.tracks[0].clips[2].start += 2
        t.tracks[2].clips[2].start += 2
        var music = TimelineClip(name: "m", content: .media(assetID: UUID()), start: 0, sourceDuration: 10, role: .music)
        music.audio.volume = AnimatedDouble(0.6)
        t.tracks.append(Track(kind: .audio, name: "A2", clips: [music]))

        let dry = t
        var copy = dry
        let report = EditQualityCheck.run(&copy, autofix: false)
        XCTAssertEqual(report.open.count, report.issues.count)
        XCTAssertGreaterThanOrEqual(report.issues.count, 4, report.text)

        let fixedReport = EditQualityCheck.run(&t)
        XCTAssertFalse(fixedReport.fixed.isEmpty)
        let again = EditQualityCheck.run(&t)
        XCTAssertTrue(again.issues.filter { $0.severity == .fixed }.isEmpty, "nothing left to fix: \(again.text)")
        XCTAssertTrue(EditQualityCheck.blackGaps(in: t.tracks[0].clips).isEmpty)
        XCTAssertFalse(t.tracks[0].clips.contains { $0.duration < EditPolish.minimumPiece })
    }

    func testEditMyVODComesOutClean() {
        let duration: Seconds = 1800
        let spikes = stride(from: 150.0, to: 1700, by: 160).map { $0 }
        var special: [(Seconds, String)] = []
        for s in spikes { for k in 0..<4 { special.append((s + 1 + Double(k) * 0.5, "hahaha")) } }
        let analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: duration,
                                     audio: Fixtures.audio(duration: duration, spikes: spikes),
                                     transcript: Fixtures.transcript(duration: duration, special: special), profile: .gameplay)
        let result = LongFormEditor.build(asset: Fixtures.mediaAsset(duration: duration), analysis: analysis,
                                          options: LongFormOptions(minimumLength: 240, maximumLength: 480))
        var t = result.timeline
        // Nothing mechanical left for a second check to fix.
        let report = EditQualityCheck.run(&t, words: analysis.transcript?.words ?? [], autofix: false)
        XCTAssertFalse(report.issues.contains { $0.severity == .warning }, report.text)
        // Finishing touches are there.
        XCTAssertTrue(t.allClips.contains { $0.name == "End Screen" }, "end screen for YouTube's cards")
        XCTAssertTrue(t.tracks[0].clips.filter { $0.content.assetID != nil }.allSatisfy { !$0.color.isIdentity }, "graded")
        XCTAssertTrue(result.report.contains("check"), result.report)
        XCTAssertLessThanOrEqual(result.musicDrops.count, 3, "music drops only on the biggest punchlines")
    }
}
