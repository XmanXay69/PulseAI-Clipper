import XCTest
@testable import PulseCore

/// 1.6.0 roadmap batch: stream edges, word-safe cuts, close gaps, looks.
final class RoadmapBatchTests: XCTestCase {
    let asset = UUID()

    func words(_ text: String, from start: Seconds, step: Seconds = 0.4) -> [TranscriptWord] {
        text.split(separator: " ").enumerated().map { i, w in
            TranscriptWord(text: String(w), start: start + Double(i) * step, end: start + Double(i) * step + 0.3)
        }
    }

    func testIntroAndOutroAreFoundFromWhatIsSaid() {
        var w = words("okay mic check mic check. can you guys hear me? alright we're live let's go. so today we are playing", from: 2)
        w += words("and that was a crazy game honestly. anyway thanks for watching everyone, I'm gonna raid someone now. peace", from: 3500)
        let intro = StreamEdges.intro(words: w)
        XCTAssertNotNil(intro)
        XCTAssertEqual(intro!.start, 0)
        // Ends after "…hear me?" (the last cue's sentence), before "alright we're live".
        XCTAssertEqual(intro!.end, 2 + 9 * 0.4 + 0.3 + 0.4, accuracy: 0.05)
        let outro = StreamEdges.outro(words: w, duration: 3520)
        XCTAssertNotNil(outro)
        XCTAssertEqual(outro!.end, 3520)
        XCTAssertEqual(outro!.start, 3500 + 7 * 0.4 - 0.4, accuracy: 0.05, "from the start of “anyway thanks for watching…”")
        XCTAssertNil(StreamEdges.intro(words: words("so today we are playing ranked and it's going great", from: 2)))
        XCTAssertNil(StreamEdges.outro(words: words("and that is the win. let's go again", from: 3500), duration: 3520))
    }

    func testIntroTalkIsDemotedWhenPickingMoments() {
        let duration: Seconds = 1200
        var w: [TranscriptWord] = []
        var t = 0.5
        while t < duration { w.append(TranscriptWord(text: "so", start: t, end: t + 0.3)); t += 0.4 }
        // A "big moment" (laughter) while still setting up ("can you hear me?" comes after it) and an identical one later.
        for (at, text) in [(12.0, "can"), (12.4, "you"), (12.8, "hear"), (13.2, "me?")] { w.removeAll { abs($0.start - at) < 0.2 }; w.append(TranscriptWord(text: text, start: at, end: at + 0.3)) }
        for base in [6.0, 600.0] { for k in 0..<4 { let at = base + Double(k) * 0.5; w.removeAll { abs($0.start - at) < 0.25 }; w.append(TranscriptWord(text: "hahaha", start: at, end: at + 0.3)) } }
        let transcript = Transcript(language: "en", words: w.sorted { $0.start < $1.start }, source: .demo)
        let analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: duration, audio: Fixtures.audio(duration: duration, spikes: [6, 600]),
                                     transcript: transcript, profile: .gameplay)
        let plan = LongFormEditor.planMoments(analysis: analysis, options: LongFormOptions())
        let early = plan.moments.filter { $0.range.contains(6) }.map(\.potential).max() ?? 0
        let later = plan.moments.filter { $0.range.contains(600) }.map(\.potential).max() ?? 0
        XCTAssertGreaterThan(later, early + 20, "the same laugh during the mic check scores much lower (\(early) vs \(later))")
    }

    func testCutsInsideWordsAreExtendedToTheWordAndRippled() {
        var t = Timeline(name: "t", canvas: .landscape1080, tracks: [Track(kind: .video, name: "V1"), Track(kind: .text, name: "T1"), Track(kind: .audio, name: "A1")])
        let g1 = UUID(), g2 = UUID()
        // Piece 1 ends at source 10.20, in the middle of a word 10.0–10.5; piece 2 starts at 30.
        t.tracks[0].clips = [TimelineClip(name: "a", content: .media(assetID: asset), start: 0, sourceIn: 0, sourceDuration: 10.2, linkGroup: g1),
                             TimelineClip(name: "b", content: .media(assetID: asset), start: 10.2, sourceIn: 30, sourceDuration: 5, linkGroup: g2)]
        t.tracks[2].clips = [TimelineClip(name: "a", content: .media(assetID: asset), start: 0, sourceIn: 0, sourceDuration: 10.2, linkGroup: g1, role: .microphone),
                             TimelineClip(name: "b", content: .media(assetID: asset), start: 10.2, sourceIn: 30, sourceDuration: 5, linkGroup: g2, role: .microphone)]
        t.tracks[1].clips = [TimelineClip(name: "Meme", content: .text(TextElement(text: "LOL")), start: 11, sourceDuration: 1)]
        let w = [TranscriptWord(text: "absolutely", start: 10.0, end: 10.5), TranscriptWord(text: "fine", start: 30.5, end: 30.8)]
        let report = EditQualityCheck.run(&t, words: w)
        XCTAssertTrue(report.issues.contains { $0.title == "Cuts moved off words" }, report.text)
        XCTAssertEqual(t.tracks[0].clips[0].sourceOut, 10.54, accuracy: 0.001, "through the end of “absolutely”")
        XCTAssertEqual(t.tracks[2].clips[0].sourceOut, 10.54, accuracy: 0.001, "the linked dialogue too")
        XCTAssertEqual(t.tracks[0].clips[1].start, 10.54, accuracy: 0.001, "what follows moved along")
        XCTAssertEqual(t.tracks[2].clips[1].start, 10.54, accuracy: 0.001)
        XCTAssertEqual(t.tracks[1].clips[0].start, 11.34, accuracy: 0.001, "on every track")
        XCTAssertTrue(EditQualityCheck.blackGaps(in: t.tracks[0].clips).isEmpty)
        // A second run finds nothing left to do.
        let again = EditQualityCheck.run(&t, words: w)
        XCTAssertFalse(again.issues.contains { $0.title.hasPrefix("Cuts") }, again.text)
    }

    func testCrosstalkTrimsAndBigOffsetsAreNotAutoFixed() {
        var t = Timeline(name: "t", canvas: .landscape1080, tracks: [Track(kind: .video, name: "V1")])
        t.tracks[0].clips = [TimelineClip(name: "a", content: .media(assetID: asset), start: 0, sourceIn: 0, sourceDuration: 10.2),
                             TimelineClip(name: "b", content: .media(assetID: asset), start: 10.2, sourceIn: 30, sourceDuration: 5)]
        // The word runs on for 2 s: too far to extend silently.
        let long = [TranscriptWord(text: "aaaaaaaa", start: 10.0, end: 12.2)]
        let report = EditQualityCheck.run(&t, words: long)
        XCTAssertTrue(report.issues.contains { $0.title == "Cuts inside words" }, report.text)
        XCTAssertEqual(t.tracks[0].clips[0].sourceOut, 10.2, accuracy: 0.001)
        // A crosstalk trim that ends exactly there is intentional.
        t.removedSections.append(RemovedSection(assetID: asset, sourceRange: TimeRange(start: 10.2, end: 30), reason: .crosstalk, aiGenerated: true))
        let quiet = EditQualityCheck.run(&t, words: [TranscriptWord(text: "absolutely", start: 10.0, end: 10.5)])
        XCTAssertFalse(quiet.issues.contains { $0.title.hasPrefix("Cuts") }, quiet.text)
    }

    func testCloseGapsRipplesEverythingBack() {
        var t = Timeline(name: "t", canvas: .landscape1080, tracks: [Track(kind: .video, name: "V1"), Track(kind: .audio, name: "A1")])
        t.tracks[0].clips = [TimelineClip(name: "a", content: .media(assetID: asset), start: 0, sourceDuration: 5),
                             TimelineClip(name: "b", content: .media(assetID: asset), start: 7, sourceIn: 10, sourceDuration: 5),
                             TimelineClip(name: "c", content: .media(assetID: asset), start: 13, sourceIn: 20, sourceDuration: 5)]
        t.tracks[1].clips = [TimelineClip(name: "a", content: .media(assetID: asset), start: 0, sourceDuration: 5, role: .microphone),
                             TimelineClip(name: "b", content: .media(assetID: asset), start: 7, sourceIn: 10, sourceDuration: 5, role: .microphone),
                             TimelineClip(name: "c", content: .media(assetID: asset), start: 13, sourceIn: 20, sourceDuration: 5, role: .microphone)]
        XCTAssertEqual(EditQualityCheck.closeGaps(&t), 2)
        XCTAssertEqual(t.tracks[0].clips.map(\.start), [0, 5, 10])
        XCTAssertEqual(t.tracks[1].clips.map(\.start), [0, 5, 10])
        XCTAssertEqual(EditQualityCheck.closeGaps(&t), 0)
    }

    func testLooksAreGentleAndScale() {
        for look in ColorAdjustments.Look.allCases {
            let c = ColorAdjustments.look(look)
            XCTAssertFalse(c.isIdentity, look.rawValue)
            XCTAssertLessThanOrEqual(abs(c.contrast), 0.2)
            XCTAssertLessThanOrEqual(abs(c.saturation), 0.25)
            XCTAssertLessThanOrEqual(abs(c.temperature), 0.25)
            XCTAssertTrue(ColorAdjustments.look(look, intensity: 0).isIdentity)
            XCTAssertEqual(ColorAdjustments.look(look, intensity: 0.5).contrast, c.contrast / 2, accuracy: 1e-9)
        }
    }

    func testSidecarCarriesTitlesChaptersAndCredits() {
        var t = Timeline(name: "YouTube Edit", canvas: .landscape1080, tracks: [])
        XCTAssertEqual(ExportSidecar.text(for: t, projectName: "Stream"), "")
        t.copy = ClipCopy(titles: ["I CAN'T BELIEVE IT", ""], shortsTitle: "", tiktokCaption: "", instagramCaption: "", hashtags: ["gaming", "#clips"])
        t.notes = "Chapters\n0:00 Hook\n\nMusic\n♪ Sunday — Someone (Creative Commons)"
        let text = ExportSidecar.text(for: t, projectName: "Stream")
        XCTAssertTrue(text.hasPrefix("Stream — YouTube Edit"))
        XCTAssertTrue(text.contains("• I CAN'T BELIEVE IT"))
        XCTAssertTrue(text.contains("0:00 Hook") && text.contains("Creative Commons"))
        XCTAssertTrue(text.contains("#gaming #clips"))
    }

    func testChapterListEndsWithTheOutroAndFlagsUnbalancedChapters() {
        let markers = [Marker(time: 6, name: "The comeback", color: .blue), Marker(time: 400, name: "Story time", color: .blue)]
        let list = LongFormEditor.chapterList(markers, hasHook: true, outroAt: 610)
        XCTAssertEqual(list.components(separatedBy: "\n").last, "10:10 Outro")
        XCTAssertTrue(list.contains("0:00 Intro") && list.contains("0:06 The comeback"))

        var t = Timeline(name: "t", canvas: .landscape1080, tracks: [Track(kind: .video, name: "V1")])
        t.tracks[0].clips = [TimelineClip(name: "v", content: .media(assetID: asset), start: 0, sourceDuration: 900)]
        t.markers = [0, 30, 60, 90].map { Marker(time: $0, name: "c", color: .blue) }   // last chapter: 810 s vs 30 s
        let report = EditQualityCheck.run(&t)
        XCTAssertTrue(report.issues.contains { $0.title == "Unbalanced chapters" }, report.text)
        t.markers = [0, 300, 600].map { Marker(time: $0, name: "c", color: .blue) }
        let even = EditQualityCheck.run(&t)
        XCTAssertFalse(even.issues.contains { $0.title == "Unbalanced chapters" }, even.text)
    }

    func testFreezeFrameHoldsThePictureAndPausesTheSound() throws {
        var t = Timeline(name: "t", canvas: .landscape1080, tracks: [Track(kind: .video, name: "V1"), Track(kind: .audio, name: "A1"), Track(kind: .text, name: "T1")])
        let g = UUID()
        t.tracks[0].clips = [TimelineClip(name: "v", content: .media(assetID: asset), start: 0, sourceIn: 100, sourceDuration: 20, linkGroup: g)]
        t.tracks[1].clips = [TimelineClip(name: "a", content: .media(assetID: asset), start: 0, sourceIn: 100, sourceDuration: 20, linkGroup: g, role: .microphone)]
        t.tracks[2].clips = [TimelineClip(name: "Meme", content: .text(TextElement(text: "LOL")), start: 12, sourceDuration: 1)]
        let id = try t.freezeFrame(at: 8, hold: 2)
        let v = t.tracks[0].clips
        XCTAssertEqual(v.count, 3)
        XCTAssertEqual(v[0].end, 8, accuracy: 0.001)
        let still = v[1]
        XCTAssertEqual(still.id, id)
        XCTAssertEqual(still.start, 8, accuracy: 0.001)
        XCTAssertEqual(still.duration, 2, accuracy: 0.001, "one frame stretched to the hold")
        XCTAssertEqual(still.sourceIn, 108, accuracy: 0.001)
        XCTAssertEqual(v[2].start, 10, accuracy: 0.001)
        XCTAssertEqual(v[2].sourceIn, 108, accuracy: 0.001, "the story resumes on the same frame")
        XCTAssertEqual(t.tracks[1].clips.map(\.start), [0, 10], "the sound pauses with the picture")
        XCTAssertEqual(t.tracks[2].clips[0].start, 14, accuracy: 0.001)
        XCTAssertTrue(EditQualityCheck.blackGaps(in: t.tracks[0].clips).isEmpty)
    }

    func testOverlappingShortsAreFlagged() {
        func candidate(_ title: String, _ start: Seconds, _ end: Seconds) -> ClipCandidate {
            ClipCandidate(assetID: asset, range: TimeRange(start: start, end: end), payoffTime: start + 10, targetDuration: 30, potential: 70,
                          scores: ClipScores(), tags: [], title: title,
                          copy: ClipCopy(titles: [], shortsTitle: "", tiktokCaption: "", instagramCaption: "", hashtags: []), transcriptSnippet: "")
        }
        let a = candidate("A", 100, 130), b = candidate("B", 110, 140), c = candidate("C", 500, 530)
        let pairs = [a, b, c].overlappingPairs()
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].share, 20.0 / 30, accuracy: 0.001)
        XCTAssertTrue([a, c].overlappingPairs().isEmpty)
    }

    func testFastCaptionsGetANote() {
        var t = Timeline(name: "t", canvas: .landscape1080, tracks: [Track(kind: .video, name: "V1")])
        t.tracks[0].clips = [TimelineClip(name: "v", content: .media(assetID: asset), start: 0, sourceDuration: 60)]
        // 6 words a second for 12 s, then normal.
        var words: [CaptionWord] = []
        var at = 0.0
        while at < 12 { words.append(CaptionWord(text: "w", start: at, end: at + 0.12)); at += 1.0 / 6 }
        while at < 60 { words.append(CaptionWord(text: "w", start: at, end: at + 0.3)); at += 0.5 }
        t.captions = CaptionTrack(sourceAssetID: asset, words: words, style: .youtube)
        let report = EditQualityCheck.run(&t)
        XCTAssertTrue(report.issues.contains { $0.title == "Fast captions" }, report.text)
    }

    func testCaptionsHideUnderTitleCards() {
        var t = Timeline(name: "t", canvas: .landscape1080, tracks: [Track(kind: .video, name: "V1"), Track(kind: .text, name: "T1")])
        t.tracks[0].clips = [TimelineClip(name: "v", content: .media(assetID: asset), start: 0, sourceDuration: 60)]
        t.tracks[1].clips = [TimelineClip(name: "Title Card", content: .text(TextElement(text: "THEN THIS HAPPENED…")), start: 10, sourceDuration: 1.7, aiGenerated: true),
                             TimelineClip(name: "Hook Title", content: .text(TextElement(text: "x")), start: 30, sourceDuration: 2, aiGenerated: true)]
        t.captions = CaptionTrack(sourceAssetID: asset, words: [CaptionWord(text: "a", start: 9, end: 9.5), CaptionWord(text: "b", start: 10.5, end: 11),
                                                                CaptionWord(text: "c", start: 30.5, end: 31)], style: .youtube)
        XCTAssertEqual(RetentionCards.hideCaptionsUnderCards(&t), 1, "only the word under the card (not under the hook title)")
        XCTAssertEqual(t.captions!.words.filter(\.isHidden).map(\.text), ["b"])
    }

    func testTitleCardsUseTheStreamersOwnWordsWhenShort() {
        let w = [("that", 100.0), ("was", 100.4), ("the", 100.8), ("craziest", 101.2), ("clutch", 101.6), ("ever!", 102.0)].map {
            TranscriptWord(text: $0.0, start: $0.1, end: $0.1 + 0.3)
        }
        let prev = LongFormSegment(range: TimeRange(start: 0, end: 60), payoff: 30, potential: 60, title: "", tags: [])
        let seg = LongFormSegment(range: TimeRange(start: 90, end: 150), payoff: 102, potential: 80, title: "", tags: [.gaming, .hype])
        let text = RetentionCards.text(for: seg, after: prev, index: 0, words: w)
        XCTAssertEqual(text, "CRAZIEST CLUTCH EVER!")
        XCTAssertEqual(RetentionCards.text(for: seg, after: prev, index: 0), "THEN THIS HAPPENED…", "no transcript → the stock line")
    }

    func testDeadAirSettingAndChapterMoods() {
        var options = LongFormOptions()
        XCTAssertEqual(options.silencePreset, .balanced)
        options.deadAir = .aggressive
        XCTAssertEqual(options.silencePreset, .aggressive)
        options.style = StyleTuning(name: "ref")
        options.style?.silence = .conservative
        XCTAssertEqual(options.silencePreset, .conservative, "a reference style wins")
    }

    func testYourOwnMemesAndCensorWords() {
        XCTAssertEqual(LongFormEditor.memeFor(tags: [.fail]).text, "BRUH")
        XCTAssertEqual(LongFormEditor.memeFor(tags: [.fail], custom: [.fail: "OOF"]).text, "OOF")
        XCTAssertEqual(LongFormEditor.memeFor(tags: [.fail], custom: [.fail: "  "]).text, "BRUH", "blank means default")
        XCTAssertEqual(LongFormEditor.memeFor(tags: [.conversation], custom: [.story: "👂"]).text, "👂", "story-like moods share one pop-up")
        var ai = AISettings()
        ai.memeTexts = ["hype": "SHEESH", "nonsense": "x"]
        XCTAssertEqual(ai.memeTextsByTag, [.hype: "SHEESH"])
        ai.extraProfanity = ["Heck!", "dang", ""]
        XCTAssertEqual(ai.normalizedExtraProfanity, ["heck", "dang"])
        EngagementLexicon.customProfanity = ai.normalizedExtraProfanity
        XCTAssertTrue(EngagementLexicon.isProfane("dang"))
        XCTAssertTrue(EngagementLexicon.isProfane("shit"))
        EngagementLexicon.customProfanity = []
        XCTAssertFalse(EngagementLexicon.isProfane("dang"))
    }

    func testSearchActionKindHasAnIcon() {
        XCTAssertEqual(SearchResultKind.action.symbolName, "command")
        XCTAssertEqual(SearchResultKind.action.displayName, "Action")
    }
}
