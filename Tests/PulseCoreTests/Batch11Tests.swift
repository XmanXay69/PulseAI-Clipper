import XCTest
@testable import PulseCore
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Roadmap batch 11: shouts (#29), game-only audio (#30), platform lengths (#58), cover frame (#70), chapter
/// outline (#86), match previous (#226), phrase line breaks (#255), rebuilt captions (#258), reference explain
/// (#368), undo memory cap (#397), anonymized structure (#455), deadlines (#475), notes checklists (#476),
/// editing time (#477), FCPXML (#480).
final class Batch11Tests: XCTestCase {
    func sentence(_ text: String, at start: Seconds, speaker: Int? = nil) -> [TranscriptWord] {
        var out: [TranscriptWord] = []
        var t = start
        for w in text.split(separator: " ") {
            out.append(TranscriptWord(text: String(w), start: t, end: t + 0.3, speaker: speaker))
            t += 0.4
        }
        return out
    }

    /// A steady −24 dB bed with one 2 s burst at −6 dB and a flat spectrum (a voice, not an explosion).
    func burstAudio(duration: Seconds, at time: Seconds) -> AudioFeatureSeries {
        let hop = 0.1
        let n = Int(duration / hop)
        var rms = [Float](repeating: -24, count: n)
        for i in 0..<n { rms[i] += Float(sin(Double(i) * 0.37)) * 1.5 }
        for k in Int(time / hop)..<min(n, Int((time + 2) / hop)) { rms[k] = -6 }
        return AudioFeatureSeries(hop: hop, rmsDB: rms, peakDB: rms.map { $0 + 6 }, zeroCrossingRate: [Float](repeating: 0.1, count: n),
                                  spectralFlux: [Float](repeating: 0.1, count: n))
    }

    func testShoutsNeedAVoiceBehindThem() {
        let audio = burstAudio(duration: 120, at: 60)
        let voiced = Transcript(language: "en", words: sentence("oh my god no way no way no way", at: 60), source: .demo)
        let a = EngagementModel.compute(duration: 120, audio: audio, transcript: voiced, visual: nil)
        let b = EngagementModel.compute(duration: 120, audio: audio, transcript: Transcript(language: "en", words: sentence("so yeah", at: 10), source: .demo), visual: nil)
        let i = a.index(at: 60.5)
        XCTAssertGreaterThan(a.shouts[i], 0, "a scream while talking")
        XCTAssertEqual(b.shouts[i], 0, "a loud game with nobody talking isn't a scream")
        XCTAssertEqual(a.shouts.count, a.count)
        XCTAssertGreaterThan(a.excitement[i], b.excitement[i])
    }

    func testGameOnlyRangesNeedLoudAudioAndNoWords() {
        var s = EngagementModel.compute(duration: 60, audio: nil, transcript: nil, visual: nil, step: 0.5)
        XCTAssertTrue(EngagementModel.gameOnlyRanges(s).isEmpty)
        for i in 20..<60 { s.loudness[i] = 1.0; s.speech[i] = 0 }      // 10 s → 30 s loud, silent voice
        for i in 60..<70 { s.loudness[i] = 1.0; s.speech[i] = 1 }      // talking over it
        for i in 80..<90 { s.loudness[i] = 1.0; s.speech[i] = 0 }      // 5 s: too short
        let ranges = EngagementModel.gameOnlyRanges(s)
        XCTAssertEqual(ranges.count, 1, "\(ranges)")
        XCTAssertEqual(ranges.first?.start ?? -1, 10, accuracy: 1e-9)
        XCTAssertEqual(ranges.first?.end ?? -1, 30, accuracy: 1e-9)
        XCTAssertEqual(RemovedSection.Reason.noTalking.displayName, "No one talking")
        XCTAssertFalse(LongFormOptions().cutGameOnly)
    }

    func testPlatformLengthPresets() {
        XCTAssertEqual(ClipLengthPreset.reels90.seconds, 90)
        XCTAssertEqual(ClipLengthPreset.tiktok180.seconds, 180)
        XCTAssertEqual(ClipGenerationSettings(targetDuration: 180).targetDuration, 180)
        XCTAssertEqual(ClipGenerationSettings(targetDuration: 500).targetDuration, 180)
        XCTAssertTrue(ClipLengthPreset.long60.displayName.contains("Shorts"))
    }

    func moment(_ start: Seconds, tags: [ClipTag], potential: Int = 60) -> LongFormSegment {
        LongFormSegment(range: TimeRange(start: start, end: start + 40), payoff: start + 20, potential: potential, title: "M\(Int(start))", tags: tags)
    }

    func testChapterOutlineSplitsAtTheBigJumps() {
        let moments = [moment(100, tags: [.hype]), moment(160, tags: [.gaming]), moment(220, tags: [.hype]),
                       moment(900, tags: [.story]), moment(960, tags: [.story]),
                       moment(1800, tags: [.fail]), moment(1860, tags: [.rage]), moment(1920, tags: [.funny])]
        let plan = LongFormPlan(moments: moments.shuffled(), selected: Set(moments.map(\.id)), target: 600, hook: moments[0].id, hookCandidates: [])
        let chapters = ChapterOutline.propose(plan: plan)
        XCTAssertTrue((3...5).contains(chapters.count), "\(chapters.map(\.name))")
        XCTAssertEqual(chapters.flatMap(\.momentIDs).count, 8, "every moment in exactly one chapter")
        XCTAssertEqual(Set(chapters.flatMap(\.momentIDs)).count, 8)
        XCTAssertEqual(chapters.flatMap(\.momentIDs), moments.map(\.id), "time order")
        let early = chapters.first { $0.momentIDs.contains(moments[0].id) }!
        XCTAssertFalse(early.momentIDs.contains(moments[3].id), "the 11-minute jump splits chapters")
        XCTAssertFalse(chapters.first { $0.momentIDs.contains(moments[4].id) }!.momentIDs.contains(moments[5].id))
        XCTAssertEqual(Set(chapters.map(\.name)).count, chapters.count, "unique names")
        XCTAssertTrue(chapters.allSatisfy { !$0.name.isEmpty })
        XCTAssertEqual(chapters.first { $0.momentIDs.contains(moments[3].id) }?.name, "Story Time")
        let words = sentence("that was the craziest clutch ever!", at: 115)
        XCTAssertEqual(ChapterOutline.propose(plan: plan, words: words).first?.name, "Craziest Clutch Ever")
        var none = plan
        none.selected = []
        XCTAssertTrue(ChapterOutline.propose(plan: none).isEmpty)
        var two = plan
        two.selected = Set(moments.prefix(2).map(\.id))
        XCTAssertEqual(ChapterOutline.propose(plan: two).count, 2)
    }

    func testMatchPreviousCopiesTheLook() {
        var timeline = Fixtures.simpleTimeline(clipDuration: 10)
        timeline.tracks[0].clips[0].color.saturation = 0.4
        timeline.tracks[0].clips[0].transform.scale = AnimatedDouble(1.2)
        var second = timeline.tracks[0].clips[0]
        second.id = UUID()
        second.start = 10
        second.linkGroup = nil
        second.color = .neutral
        second.transform = VisualTransform()
        timeline.tracks[0].clips.append(second)
        XCTAssertTrue(timeline.matchPrevious(clipID: second.id))
        XCTAssertEqual(timeline.tracks[0].clips[1].color.saturation, 0.4)
        XCTAssertEqual(timeline.tracks[0].clips[1].transform.scale.value, 1.2)
        XCTAssertFalse(timeline.matchPrevious(clipID: timeline.tracks[0].clips[0].id), "nothing before the first clip")
        XCTAssertFalse(timeline.matchPrevious(clipID: UUID()))
    }

    func testLinesBreakAtThePhrase() {
        let texts = ["I", "went", "to", "the", "store,", "and", "then", "I", "came", "back"]
        var t = 0.0
        let words = texts.map { text -> TimedCaptionWord in
            defer { t += 0.3 }
            return TimedCaptionWord(id: UUID(), text: text, start: t, end: t + 0.25, isEmphasized: false, speaker: nil)
        }
        var style = CaptionStyle.tiktok
        style.displayMode = .phrase
        style.maxWordsPerPage = 20
        style.maxCharsPerLine = 24
        style.maxLines = 2
        let pages = CaptionLayoutEngine.pages(words, style: style)
        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages[0].lines.count, 2)
        XCTAssertEqual(pages[0].lines[0].last?.text, "store,", pages[0].text)
        XCTAssertEqual(pages[0].lines[1].map(\.text).joined(separator: " "), "and then I came back")
        // Tighter lines split into more pages; balancing never widens a line past the greedy result.
        style.maxCharsPerLine = 12
        let tight = CaptionLayoutEngine.pages(words, style: style)
        XCTAssertGreaterThanOrEqual(tight.count, 2)
        XCTAssertTrue(tight.allSatisfy { $0.lines.count <= 2 })
        XCTAssertEqual(tight.flatMap { $0.words }.map(\.text), texts, "every word still shown once, in order")
    }

    func testRebuiltCaptionsKeepYourFixes() {
        let old = Transcript(language: "en", words: sentence("hello there friend of mine", at: 100), source: .demo)
        var track = CaptionTrack.make(from: old, range: TimeRange(start: 100, end: 110), assetID: Fixtures.assetID, style: .tiktok, emphasize: false)
        track.words[1].text = "Dare"
        track.words[2].isHidden = true
        track.words[0].isEmphasized = true
        track.words[0].emphasisIsAI = false
        track.speakerNames[0] = "Mark"
        let fresh = Transcript(language: "en", words: sentence("hello there friends of mine", at: 100), source: .demo)
        let rebuilt = CaptionTrack.rebuilt(from: fresh, range: TimeRange(start: 100, end: 110), assetID: Fixtures.assetID, keeping: track, previous: old, emphasize: true)
        XCTAssertEqual(rebuilt.words.map(\.text), ["hello", "Dare", "friends", "of", "mine"])
        XCTAssertTrue(rebuilt.words[2].isHidden)
        XCTAssertTrue(rebuilt.words[0].isEmphasized && !rebuilt.words[0].emphasisIsAI)
        XCTAssertEqual(rebuilt.speakerNames[0], "Mark")
        XCTAssertFalse(rebuilt.aiGenerated, "it carries your edits")
    }

    func testReferenceExplainsItself() {
        let style = ReferenceStyle(name: "Ref", duration: 700, aspect: 1.78, cutsPerMinute: 12, averageShotLength: 5, zoomsPerMinute: 2.5, zoomScale: 1.2,
                                   captions: ReferenceStyle.CaptionLook(coverage: 0.8, positionY: 0.8, lineHeight: 0.06, wordsOnScreen: 3, uppercase: true),
                                   popupsPerMinute: 0.5, wordsPerMinute: 160, pauseRatio: 0.05, musicBed: 0.7, effectsPerMinute: 1, fadesPerMinute: 0.3, opensFast: true)
        let lines = style.explain(ReferenceAnswers())
        XCTAssertGreaterThanOrEqual(lines.count, 8, "\(lines)")
        XCTAssertTrue(lines.contains { $0.hasPrefix("Zooms: every") && $0.contains("2.5 times a minute") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.hasPrefix("Captions: on, big ALL-CAPS") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.hasPrefix("Music: on") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("Transitions: fades") })
        let fewer = style.explain(ReferenceAnswers(copyZooms: false, copyMusic: false))
        XCTAssertFalse(fewer.contains { $0.hasPrefix("Zooms") })
        XCTAssertFalse(fewer.contains { $0.hasPrefix("Music") })
    }

    func testUndoDropsOldStepsPastTheMemoryCap() {
        var history = History<Int>(limit: 100, maxCost: 10, cost: { $0 })
        for i in 1...6 { history.record(i, label: "s\(i)") }
        XCTAssertEqual(history.labels, ["s6"], "\(history.labels)")
        XCTAssertEqual(history.totalCost, 6)
        var small = History<Int>(limit: 100, maxCost: 100, cost: { $0 })
        for i in 1...6 { small.record(i, label: "s\(i)") }
        XCTAssertEqual(small.labels.count, 6)
        var uncapped = History<Int>()
        for i in 1...6 { uncapped.record(i, label: "s\(i)") }
        XCTAssertEqual(uncapped.labels.count, 6)
        XCTAssertEqual(uncapped.totalCost, 0)
    }

    func testAnonymizedStructureHasNothingPersonal() {
        var doc = ProjectDocument(name: "Xav's Secret Stream")
        var asset = Fixtures.mediaAsset()
        asset.name = "SecretStream.mp4"
        asset.path = "/Users/xav/Movies/SecretStream.mp4"
        doc.media = [asset]
        doc.timelines = [Fixtures.simpleTimeline()]
        doc.timelines[0].name = "My Private Edit"
        doc.candidates = [ClipCandidate(assetID: asset.id, range: TimeRange(start: 100, end: 130), payoffTime: 115, targetDuration: 30, potential: 72,
                                        scores: ClipScores(), tags: [.funny], title: "THE SECRET WORD", copy: .empty, transcriptSnippet: "we said the secret")]
        let text = doc.anonymizedStructure()
        XCTAssertTrue(text.contains("media 0: video/main 1920x1080"), text)
        XCTAssertTrue(text.contains("timeline 0:"))
        XCTAssertTrue(text.contains("clip cards: 1 good"))
        for secret in ["Secret", "SECRET", "xav", "Xav", "/Users", "Private", "we said"] { XCTAssertFalse(text.contains(secret), "leaked \(secret)") }
    }

    func testDeadlinesEditingTimeAndCoverFrameRoundTrip() throws {
        var doc = ProjectDocument(name: "P")
        doc.deadline = Date(timeIntervalSince1970: 1_800_000_000)
        doc.editingSeconds = 125
        doc.timelines = [Fixtures.simpleTimeline()]
        doc.timelines[0].coverTime = 4.5
        let back = try ProjectStore.makeDecoder().decode(ProjectDocument.self, from: ProjectStore.makeEncoder().encode(doc))
        XCTAssertEqual(back.deadline, doc.deadline)
        XCTAssertEqual(back.editingSeconds, 125)
        XCTAssertEqual(back.timelines[0].coverTime, 4.5)
        XCTAssertEqual(back.summary.deadline, doc.deadline)
        XCTAssertEqual(back.summary.editingSeconds, 125)
        XCTAssertNil(ProjectDocument(name: "Q").summary.editingSeconds)
        let minimal = try ProjectStore.makeDecoder().decode(ProjectDocument.self, from: Data(#"{"id":"11111111-2222-3333-4444-555555555555"}"#.utf8))
        XCTAssertNil(minimal.deadline)
        XCTAssertEqual(minimal.editingSeconds, 0)
    }

    func testNotesChecklist() {
        var notes = "Plan\n- [ ] grade the intro\n- [x] export\nSome text\n  - [ ] indented"
        var items = NotesChecklist.items(in: notes)
        XCTAssertEqual(items.map(\.text), ["grade the intro", "export", "indented"])
        XCTAssertEqual(items.map(\.done), [false, true, false])
        XCTAssertEqual(items.map(\.line), [1, 2, 4])
        notes = NotesChecklist.toggle(notes, line: 1)
        notes = NotesChecklist.toggle(notes, line: 2)
        notes = NotesChecklist.toggle(notes, line: 4)
        items = NotesChecklist.items(in: notes)
        XCTAssertEqual(items.map(\.done), [true, false, true])
        XCTAssertTrue(notes.contains("  - [x] indented"), "indent kept")
        XCTAssertEqual(NotesChecklist.toggle(notes, line: 0), notes, "not a checkbox line")
        XCTAssertEqual(NotesChecklist.toggle(notes, line: 99), notes)
        notes = NotesChecklist.add("  thumbnail ", to: notes)
        XCTAssertTrue(notes.hasSuffix("\n- [ ] thumbnail"))
        XCTAssertEqual(NotesChecklist.add("", to: notes), notes)
        XCTAssertEqual(NotesChecklist.add("x", to: ""), "- [ ] x")
        let progress = NotesChecklist.progress(in: notes)
        XCTAssertEqual(progress.done, 2)
        XCTAssertEqual(progress.total, 4)
    }

    func testFCPXMLCarriesTheCut() throws {
        var timeline = Fixtures.simpleTimeline(clipDuration: 10)
        var second = timeline.tracks[0].clips[0]
        second.id = UUID()
        second.start = 12
        second.sourceIn = 300
        second.linkGroup = nil
        second.name = "Second <take> & more"
        timeline.tracks[0].clips.append(second)
        let style = TextStyle(fontName: "Inter", fontSize: 60, weight: .bold)
        if let t1 = timeline.tracks.firstIndex(where: { $0.kind == .text }) {
            timeline.tracks[t1].clips.append(TimelineClip(name: "Title", content: .text(TextElement(text: "Hello \"world\"", style: style)), start: 3, sourceDuration: 2))
        }
        var music = Fixtures.mediaAsset(duration: 120)
        music.id = UUID()
        music.name = "Bed"
        music.kind = .audio
        music.metadata.hasVideo = false
        timeline.tracks[4].clips.append(TimelineClip(name: "Music", content: .media(assetID: music.id), start: 0, sourceIn: 5, sourceDuration: 20, role: .music))
        timeline.markers = [Marker(time: 4, name: "Payoff", note: "big one", color: .pink)]
        let xml = FCPXMLExporter.xml(timeline: timeline, assets: [Fixtures.mediaAsset(duration: 600), music], projectName: "Test & Co")
        XCTAssertTrue(xml.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE fcpxml>\n<fcpxml version=\"1.9\">"), String(xml.prefix(120)))
        XCTAssertEqual(xml.components(separatedBy: "<asset-clip ").count - 1, 3, xml)
        XCTAssertTrue(xml.contains("frameDuration=\"1/30s\""), xml)
        XCTAssertTrue(xml.contains("<gap name=\"Gap\" offset=\"300/30s\" start=\"0s\" duration=\"60/30s\""), xml)
        XCTAssertTrue(xml.contains("start=\"9000/30s\" duration=\"300/30s\""), "second clip's source start")
        XCTAssertTrue(xml.contains("<title ref=") && xml.contains("Hello &quot;world&quot;"), xml)
        XCTAssertTrue(xml.contains("lane=\"-2\""), "music on A2 is a connected audio clip below the spine")
        XCTAssertTrue(xml.contains("<marker start=\"120/30s\"") && xml.contains("note=\"big one\""))
        XCTAssertTrue(xml.contains("name=\"Second &lt;take&gt; &amp; more\""))
        XCTAssertTrue(xml.contains("<project name=\"Test &amp; Co\">"))
        XCTAssertTrue(XMLParser(data: Data(xml.utf8)).parse(), "well-formed")
        XCTAssertEqual(FCPXMLExporter.frameDuration(fps: 29.97).1, 30000)
        XCTAssertEqual(FCPXMLExporter.frameDuration(fps: 25).1, 25)
        XCTAssertEqual(FCPXMLExporter.frameDuration(fps: 24.5).1, 2450)
    }
}
