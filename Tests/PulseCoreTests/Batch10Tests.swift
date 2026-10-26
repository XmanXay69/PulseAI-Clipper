import XCTest
@testable import PulseCore

/// Roadmap batch 10: more titles (#60), merged moments (#65), running bits (#66), end cards (#71 #76), hashtags
/// (#72), pause preview (#82), extras presets and controls (#127 #128 #136–#139), timeline search (#174),
/// caption cleanup (#239 #241 #245), grade presets (#317), migration (#385), unused media (#469), statistics
/// (#478), never (#52), content fingerprints (#5).
final class Batch10Tests: XCTestCase {
    func sentence(_ text: String, at start: Seconds, speaker: Int? = nil) -> [TranscriptWord] {
        var out: [TranscriptWord] = []
        var t = start
        for w in text.split(separator: " ") {
            out.append(TranscriptWord(text: String(w), start: t, end: t + 0.3, speaker: speaker))
            t += 0.4
        }
        return out
    }

    func testMoreTitlesLikeThisOne() {
        let words = sentence("That was the craziest clutch ever!", at: 10) + sentence("No way he hit that shot.", at: 14)
            + sentence("Chat is going insane right now!", at: 18)
        let copy = TitleGenerator.generate(words: words, payoff: 12, tags: [.hype, .gaming], seed: 3)
        let title = copy.titles[0]
        XCTAssertTrue(title.hasPrefix("“"), title)
        let more = TitleGenerator.moreLike(title, words: words, payoff: 12, tags: [.hype, .gaming], seed: 3, avoiding: copy.titles)
        XCTAssertEqual(more.count, 3, "\(more)")
        XCTAssertEqual(Set(more).count, 3)
        XCTAssertFalse(more.contains(title))
        XCTAssertFalse(more.contains { copy.titles.contains($0) })
        XCTAssertTrue(more[0].hasPrefix("“"), "a quote gets the next quote first: \(more)")
        let template = TitleGenerator.moreLike("LET'S GOOO 🔥", words: words, payoff: 12, tags: [.hype], seed: 1)
        XCTAssertEqual(template.count, 3)
        XCTAssertFalse(template.contains("LET'S GOOO 🔥"))
    }

    func testHashtagsComeFromNamesSaidTwice() {
        let words = sentence("The game is Valorant and I love Valorant.", at: 0) + sentence("The chat said GG and GG again.", at: 5)
        let tags = Hashtags.suggest(words: words, tags: [.gaming])
        XCTAssertTrue(tags.contains("#valorant"), "\(tags)")
        XCTAssertTrue(tags.contains("#gg"), "\(tags)")
        XCTAssertFalse(tags.contains("#the"), "\(tags)")
        XCTAssertFalse(tags.contains("#i"), "\(tags)")
        XCTAssertEqual(tags.first, "#gaming")
        XCTAssertTrue(tags.contains("#shorts") && tags.contains("#clips"))
        XCTAssertEqual(Hashtags.parse("funny, #Gaming  #x! clips"), ["#funny", "#gaming", "#x", "#clips"])
        let copy = TitleGenerator.generate(words: words, payoff: 2, tags: [.gaming], seed: 0)
        XCTAssertTrue(copy.hashtags.contains("#valorant"))
    }

    func candidate(_ start: Seconds, tags: [ClipTag] = [.funny]) -> ClipCandidate {
        ClipCandidate(assetID: Fixtures.assetID, range: TimeRange(start: start, end: start + 30), payoffTime: start + 15, targetDuration: 30,
                      potential: 70, scores: ClipScores(), tags: tags, title: "T\(Int(start))", copy: .empty, transcriptSnippet: "")
    }

    func testRunningBitsAreLinkedIntoASeries() {
        let a = candidate(100), b = candidate(300), c = candidate(600)
        let words = sentence("So there was this goblin in the basement right", at: 110)
            + sentence("okay let's play the next round and see what happens", at: 310)
            + sentence("remember when the goblin came out of the basement again", at: 610)
        let groups = SeriesDetector.series(candidates: [c, a, b], words: words)
        XCTAssertEqual(groups, [[a.id, c.id]])
        let labels = SeriesDetector.partLabels(groups)
        XCTAssertEqual(labels[a.id], "Part 1/2")
        XCTAssertEqual(labels[c.id], "Part 2/2")
        XCTAssertNil(labels[b.id])
        let common = sentence("so yeah this is the thing that happened right", at: 110) + sentence("so yeah this is the thing that happened right", at: 610)
        XCTAssertTrue(SeriesDetector.series(candidates: [a, c], words: common).isEmpty, "common words don't make a series")
    }

    func testMergingTwoMomentsAppendsTimelines() {
        var first = Fixtures.simpleTimeline(clipDuration: 10)
        first.markers = [Marker(time: 2, name: "Payoff", color: .pink)]
        var second = Fixtures.simpleTimeline(clipDuration: 8)
        second.tracks[0].clips[0].sourceIn = 200
        second.tracks[3].clips[0].sourceIn = 200
        second.markers = [Marker(time: 3, name: "Payoff", color: .pink)]
        let oldIDs = Set(first.allClips.map(\.id) + second.allClips.map(\.id))
        first.append(second)
        XCTAssertEqual(first.duration, 18, accuracy: 1e-9)
        XCTAssertEqual(first.tracks.count, Fixtures.simpleTimeline().tracks.count, "tracks matched by kind")
        XCTAssertEqual(first.tracks[0].clips.count, 2)
        XCTAssertEqual(first.tracks[0].clips[1].start, 10, accuracy: 1e-9)
        XCTAssertEqual(first.tracks[0].clips[1].sourceIn, 200, accuracy: 1e-9)
        XCTAssertFalse(oldIDs.contains(first.tracks[0].clips[1].id), "fresh ids")
        XCTAssertEqual(first.tracks[0].clips[1].linkGroup, first.tracks[3].clips[1].linkGroup, "links kept")
        XCTAssertNotEqual(first.tracks[0].clips[0].linkGroup, first.tracks[0].clips[1].linkGroup)
        XCTAssertEqual(first.markers.map(\.time), [2, 13])
        XCTAssertTrue(EditQualityCheck.blackGaps(in: first.tracks[0].clips).isEmpty)
        let merged = ClipCandidate.merged(candidate(600, tags: [.funny]), candidate(100, tags: [.hype]))
        XCTAssertEqual(merged.range.start, 100, "time order")
        XCTAssertEqual(merged.extraRanges?.first?.start, 600)
        XCTAssertEqual(merged.totalDuration, 60)
        XCTAssertTrue(merged.isMerged)
        XCTAssertEqual(merged.tags, [.hype, .funny])
    }

    func testEndCardsAskForCommentsOrFollows() {
        XCTAssertEqual(EndCards.text(for: .comment, tags: [.question]), "WHAT'S YOUR ANSWER? 👇")
        XCTAssertEqual(EndCards.text(for: .follow, tags: [], handle: "xav"), "FOLLOW @xav FOR MORE")
        XCTAssertEqual(EndCards.text(for: .follow, tags: [], handle: "@xav"), "FOLLOW @xav FOR MORE")
        XCTAssertNil(EndCards.text(for: .none, tags: [.funny]))
        var timeline = Fixtures.simpleTimeline(clipDuration: 10)
        XCTAssertTrue(EndCards.add(&timeline, text: "TELL ME 👇"))
        let card = timeline.tracks.first { $0.kind == .text }?.clips.first { $0.name == "End Card" }
        XCTAssertEqual(card?.start ?? 0, 7.6, accuracy: 1e-9)
        XCTAssertEqual(card?.end ?? 0, 10, accuracy: 1e-9)
        XCTAssertFalse(EndCards.add(&timeline, text: "AGAIN"), "already has a card there")
        var short = Fixtures.simpleTimeline(clipDuration: 4)
        XCTAssertFalse(EndCards.add(&short, text: "X"), "too short")
        var settings = AISettings()
        settings.shortsEndCTA = .follow
        XCTAssertEqual(ShortBuildOptions(settings: settings).endCTA, .follow)
        let decoded = try? JSONDecoder().decode(AISettings.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded?.shortsEndCTA, EndCTA.none)
    }

    func testPauseRemovalEstimateLeavesTheTimelineAlone() {
        let timeline = Fixtures.simpleTimeline(clipDuration: 30)
        let words = sentence("one two three four five six seven eight nine ten", at: 100) + sentence("after the pause we keep going for a while here", at: 106.5)
        let estimate = EditPolish.pauseRemovalEstimate(timeline, words: words)
        XCTAssertEqual(estimate.pauses, 1)
        XCTAssertGreaterThan(estimate.saved, 0.5)
        XCTAssertEqual(timeline.duration, 30)
        XCTAssertEqual(EditPolish.pauseRemovalEstimate(timeline, words: []).pauses, 0)
    }

    func testExtrasPresetsAndFineControls() throws {
        XCTAssertTrue(EditExtras.Preset.gaming.extras.instantReplays)
        XCTAssertFalse(EditExtras.Preset.podcast.extras.instantReplays)
        XCTAssertTrue(EditExtras.Preset.podcast.extras.approveCut)
        var extras = EditExtras()
        extras.replaySpeed = 0.35
        extras.apply(.gaming)
        XCTAssertEqual(EditExtras.Preset.matching(extras), .gaming)
        XCTAssertEqual(extras.replaySpeed, 0.35, "fine controls survive a preset")
        XCTAssertNil(EditExtras.Preset.matching(EditExtras()))
        let decoded = try JSONDecoder().decode(EditExtras.self, from: Data(#"{"instantReplays":true,"replaySpeed":0.1,"punchInsPerVideo":99}"#.utf8))
        XCTAssertEqual(decoded.replaySpeed, 0.25)
        XCTAssertEqual(decoded.punchInsPerVideo, 20)
        XCTAssertEqual(decoded.replayTag, "REPLAY")
        XCTAssertTrue(decoded.replaySting)
        let a = LongFormSegment(range: TimeRange(start: 100, end: 160), payoff: 130, potential: 70, title: "A", tags: [.gaming])
        let b = LongFormSegment(range: TimeRange(start: 300, end: 360), payoff: 330, potential: 70, title: "B", tags: [.gaming])
        XCTAssertEqual(RetentionCards.text(for: b, after: a, index: 0, phrases: ["here we go", ""]), "HERE WE GO")
        XCTAssertEqual(RetentionCards.text(for: b, after: a, index: 1, phrases: ["here we go", "and then"]), "AND THEN")
        XCTAssertNotEqual(RetentionCards.text(for: b, after: a, index: 0), "HERE WE GO")
        XCTAssertEqual(InstantReplay.length(speed: 0.5), InstantReplay.length, accuracy: 1e-9)
    }

    func testInstantReplayHonoursSpeedTagAndLook() {
        var timeline = Fixtures.simpleTimeline(clipDuration: 60)
        let n = InstantReplay.apply(&timeline, at: [130], assetID: Fixtures.assetID, whoosh: nil, hookEnd: 0, speed: 0.35, tag: "again", sting: false, desaturate: false)
        XCTAssertEqual(n, 1)
        let replay = try? XCTUnwrap(timeline.tracks[0].clips.first { $0.name == "Replay" })
        XCTAssertEqual(replay?.speed ?? 0, 0.35, accuracy: 1e-9)
        XCTAssertEqual(replay?.duration ?? 0, InstantReplay.length(speed: 0.35), accuracy: 1e-6)
        XCTAssertEqual(replay?.color.saturation ?? -1, 0)
        if case .text(let element)? = timeline.tracks.first(where: { $0.kind == .text })?.clips.first(where: { $0.name == "Replay Tag" })?.content {
            XCTAssertEqual(element.text, "▶ AGAIN")
        } else {
            XCTFail("no tag")
        }
        XCTAssertTrue(EditQualityCheck.blackGaps(in: timeline.tracks[0].clips).isEmpty)
    }

    func testTimelineSearchFindsClipsMarkersAndWords() {
        var timeline = Fixtures.simpleTimeline(clipDuration: 30)
        timeline.markers = [Marker(time: 12, name: "Chapter 1", note: "the big fail", color: .blue)]
        let words = sentence("hello there chat welcome back to the stream", at: 105)
        timeline.captions = CaptionTrack.make(from: Transcript(language: "en", words: words, source: .demo), range: TimeRange(start: 100, end: 130),
                                              assetID: Fixtures.assetID, style: .tiktok, emphasize: false)
        let hits = timeline.find("welcome back")
        XCTAssertEqual(hits.count, 1, "\(hits)")
        XCTAssertEqual(hits.first?.kind, .words)
        XCTAssertEqual(hits.first?.time ?? 0, 6.2, accuracy: 1e-6, "“welcome” at source 106.2 → timeline 6.2")
        XCTAssertEqual(timeline.find("fail").first?.kind, .marker)
        XCTAssertEqual(timeline.find("V").count, 0, "too short to search")
        XCTAssertEqual(timeline.find("chapter").first?.time, 12)
        XCTAssertTrue(timeline.find("nothing here").isEmpty)
    }

    func testCaptionCleanupAndPlatformPosition() {
        let words = ["HELLO", "WORLD.", "i'm", "GG", "um", "fine", "NPC"].enumerated().map { CaptionWord(text: $1, start: Double($0), end: Double($0) + 0.5) }
        var track = CaptionTrack(sourceAssetID: Fixtures.assetID, words: words)
        XCTAssertEqual(track.applySentenceCase(), 3)
        XCTAssertEqual(track.words.map(\.text), ["Hello", "world.", "I'm", "GG", "um", "fine", "NPC"])
        XCTAssertEqual(track.stripFillers(), 1)
        XCTAssertEqual(track.words.count, 6)
        XCTAssertEqual(track.shiftTiming(by: 0.5, after: 3), 3)
        XCTAssertEqual(track.words[2].start, 2)
        XCTAssertEqual(track.words[3].start, 3.5)
        var style = CaptionStyle.tiktok
        style.position(for: .tiktok)
        XCTAssertEqual(style.positionY, 0.71, accuracy: 1e-9)
        var timeline = Fixtures.simpleTimeline(clipDuration: 30)
        timeline.captions = CaptionTrack(sourceAssetID: Fixtures.assetID, words: [CaptionWord(text: "hi", start: 100, end: 100.3)], style: style)
        XCTAssertFalse(EditQualityCheck.run(&timeline, autofix: false).issues.contains { $0.title == "Captions under platform UI" })
    }

    func testGradePresetsAndStatsRoundTrip() throws {
        var presets: [GradePreset] = []
        var grade = ColorAdjustments()
        grade.saturation = 0.3
        presets.save("Warm", adjustments: grade)
        grade.saturation = 0.5
        presets.save("warm", adjustments: grade)
        presets.save("   ", adjustments: grade)
        XCTAssertEqual(presets.count, 1)
        XCTAssertEqual(presets[0].adjustments.saturation, 0.5)
        var settings = AppSettings()
        settings.gradePresets = presets
        settings.stats.note { $0.shortsBuilt += 2; $0.deadAirRemoved += 90 }
        let data = try JSONEncoder().encode(settings)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(back.gradePresets, presets)
        XCTAssertEqual(back.stats.shortsBuilt, 2)
        XCTAssertNotNil(back.stats.since)
        XCTAssertGreaterThan(back.stats.hoursSaved, 0.4)
        XCTAssertFalse(back.stats.isEmpty)
        let empty = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(empty.gradePresets.isEmpty)
        XCTAssertTrue(empty.stats.isEmpty)
        XCTAssertEqual(empty.stats.lines.count, 7)
    }

    func testOldProjectsMigrate() throws {
        var doc = ProjectDocument(name: "Old")
        var timeline = Fixtures.simpleTimeline()
        timeline.tracks[0].clips = [timeline.tracks[0].clips[0]]
        var late = timeline.tracks[0].clips[0]
        late.id = UUID()
        late.start = 20
        late.linkGroup = nil
        timeline.tracks[0].clips.insert(late, at: 0)   // out of order on purpose
        doc.timelines = [timeline]
        doc.media = [Fixtures.mediaAsset()]
        doc.candidates = [candidate(100)]
        doc.candidates[0].timelineID = UUID()
        doc.activeTimelineID = UUID()
        doc.primaryAssetID = UUID()
        var json = try JSONSerialization.jsonObject(with: ProjectStore.makeEncoder().encode(doc)) as! [String: Any]
        json["schemaVersion"] = 1
        for key in ["snapshots", "lastImportFolder", "extrasAnswered"] { json.removeValue(forKey: key) }
        var loaded = try ProjectStore.makeDecoder().decode(ProjectDocument.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(loaded.schemaVersion, 1)
        let notes = ProjectMigration.migrate(&loaded)
        XCTAssertEqual(loaded.schemaVersion, ProjectDocument.schemaVersion)
        XCTAssertEqual(loaded.activeTimelineID, timeline.id)
        XCTAssertEqual(loaded.primaryAssetID, Fixtures.assetID)
        XCTAssertNil(loaded.candidates[0].timelineID)
        XCTAssertEqual(loaded.timelines[0].tracks[0].clips.map(\.start), [0, 20])
        XCTAssertTrue(notes.contains { $0.hasPrefix("Project format 1 → ") }, "\(notes)")
        XCTAssertTrue(notes.contains("Active timeline reset"))
        XCTAssertTrue(notes.contains("Main recording reset"))
        XCTAssertTrue(notes.contains { $0.hasPrefix("1 clip card unlinked") })
        XCTAssertTrue(ProjectMigration.migrate(&loaded).isEmpty, "idempotent")
        let minimal = try ProjectStore.makeDecoder().decode(ProjectDocument.self, from: Data(#"{"id":"11111111-2222-3333-4444-555555555555"}"#.utf8))
        XCTAssertEqual(minimal.name, "Untitled Project")
        XCTAssertEqual(minimal.extrasAnswered, false)
    }

    func testUnusedMediaIsTrimmedButCompanionsStay() {
        var doc = ProjectDocument(name: "P")
        let used = Fixtures.mediaAsset()
        var companion = MediaAsset(name: "Cam", path: "/tmp/cam.mov", kind: .video, role: .webcam)
        var unused = MediaAsset(name: "Old", path: "/tmp/old.mov", kind: .video)
        let group = UUID()
        companion.syncGroupID = group
        unused.syncGroupID = nil
        doc.media = [used, companion, unused]
        doc.media[0].syncGroupID = group
        doc.timelines = [Fixtures.simpleTimeline()]
        XCTAssertEqual(doc.unusedMedia.map(\.name), ["Old"])
        XCTAssertEqual(doc.removeUnusedMedia().map(\.name), ["Old"])
        XCTAssertEqual(doc.media.map(\.name), [used.name, "Cam"])
        XCTAssertTrue(doc.removeUnusedMedia().isEmpty)
        doc.media[1].contentHash = "abc"
        XCTAssertEqual(doc.asset(contentHash: "abc")?.name, "Cam")
        XCTAssertNil(doc.asset(contentHash: "zzz"))
    }

    func testNeverWeighsMoreThanADislike() {
        let scores = ClipScores(hook: 0.9, emotion: 0.2, story: 0.1, entertainment: 0.8, audio: 0.5, visual: 0.5, reaction: 0.9, context: 0.5, ending: 0.5)
        var once = TasteProfile(), never = TasteProfile()
        once.learn(scores: scores, tags: [.rage], liked: false)
        never.never(scores: scores, tags: [.rage])
        XCTAssertEqual(once.dislikes, 1)
        XCTAssertEqual(never.dislikes, 1)
        XCTAssertLessThan(never.tagWeights["rage"] ?? 0, once.tagWeights["rage"] ?? 0)
        XCTAssertLessThan(never.adjusted(70, scores: scores, tags: [.rage]), once.adjusted(70, scores: scores, tags: [.rage]))
    }

    func testContentFingerprintMatchesTheSameBytesUnderAnyName() throws {
        var bytes = Data(count: 3 << 20)
        for i in stride(from: 0, to: bytes.count, by: 4099) { bytes[i] = UInt8(truncatingIfNeeded: i) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-fp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.mov"), b = dir.appendingPathComponent("b.mov")
        try bytes.write(to: a)
        try bytes.write(to: b)
        let ha = try ContentFingerprint.compute(url: a)
        XCTAssertEqual(ha, try ContentFingerprint.compute(url: b))
        XCTAssertEqual(ha, ContentFingerprint.compute(data: bytes))
        XCTAssertEqual(ha.count, 16)
        bytes[bytes.count - 1] ^= 0xff
        XCTAssertNotEqual(ha, ContentFingerprint.compute(data: bytes))
        XCTAssertNotEqual(ContentFingerprint.compute(data: Data("x".utf8)), ContentFingerprint.compute(data: Data("xx".utf8)))
        let small = dir.appendingPathComponent("s.wav")
        try Data("hello".utf8).write(to: small)
        XCTAssertEqual(try ContentFingerprint.compute(url: small), ContentFingerprint.compute(data: Data("hello".utf8)))
    }
}
