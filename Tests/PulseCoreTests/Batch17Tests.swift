import XCTest
@testable import PulseCore

/// Roadmap batch 17: sentence-safe cuts (#97), drop markers (#288), progress bar (#92), hook sting (#77),
/// fuzzy command matching (#459), cloud folders (#356), caption spelling candidates (#242).
final class Batch17Tests: XCTestCase {
    func sentenceWords() -> [TranscriptWord] {
        // "So I open the door and the whole lobby is empty." then a pause, then "Anyway."
        let texts = ["So", "I", "open", "the", "door", "and", "the", "whole", "lobby", "is", "empty.", "Anyway."]
        var words: [TranscriptWord] = []
        var t: Seconds = 100
        for (i, text) in texts.enumerated() {
            if i == 11 { t += 1.0 }
            words.append(TranscriptWord(text: text, start: t, end: t + 0.3, speaker: 0))
            t += 0.4
        }
        return words
    }

    func testMidSentenceCutIsExtendedToTheSentenceEnd() throws {
        // source 100…130; cut at 103.1 — after "the whole" (word 7 ends 103.1); the sentence ends at 104.3.
        var timeline = Fixtures.simpleTimeline(clipDuration: 30)
        let words = sentenceWords()
        _ = try timeline.split(at: 3.1)
        timeline.tracks[0].clips.remove(at: 1)   // drop the rest of the story so the cut is a real cut
        if timeline.tracks.count > 3 { timeline.tracks[3].clips = timeline.tracks[3].clips.filter { $0.start < 3.1 } }
        let before = timeline.tracks[0].clips[0].sourceOut
        let mid = EditQualityCheck.midSentenceCuts(in: timeline, trackIndex: 0, words: words)
        XCTAssertEqual(mid.count, 1)
        XCTAssertEqual(mid.fixable.count, 1)
        XCTAssertEqual(mid.fixable[0].tail, 104.3 + 0.04 - before, accuracy: 1e-6)
        let report = EditQualityCheck.run(&timeline, words: words)
        XCTAssertTrue(report.issues.contains { $0.title == "Cuts moved to sentence ends" }, "\(report.issues.map(\.title))")
        XCTAssertEqual(timeline.tracks[0].clips[0].sourceOut, 104.34, accuracy: 1e-6)
        // At the sentence end there's nothing to fix.
        XCTAssertEqual(EditQualityCheck.midSentenceCuts(in: timeline, trackIndex: 0, words: words).count, 0)
        // A split that continues the same source isn't a cut.
        var whole = Fixtures.simpleTimeline(clipDuration: 30)
        _ = try whole.split(at: 3.1)
        XCTAssertEqual(EditQualityCheck.midSentenceCuts(in: whole, trackIndex: 0, words: words).count, 0)
        // A pause taken out of the middle of a sentence isn't one either.
        var tightened = whole
        tightened.tracks[0].clips[1].sourceIn += 0.8
        tightened.tracks[0].clips[1].sourceDuration -= 0.8
        XCTAssertEqual(EditQualityCheck.midSentenceCuts(in: tightened, trackIndex: 0, words: words).count, 0)
    }

    func testDropMarkersPullTheMusicOut() {
        var timeline = Fixtures.simpleTimeline(clipDuration: 60)
        let a = timeline.tracks.lastIndex { $0.kind == .audio }!
        var music = TimelineClip(name: "Bed", content: .media(assetID: Fixtures.assetID), start: 0, sourceDuration: 60, role: .music)
        music.audio.volume = AnimatedDouble(0.3)
        timeline.tracks[a].clips = [music]
        XCTAssertTrue(timeline.musicDropTimes.isEmpty)
        XCTAssertEqual(EditPolish.applyDropMarkers(&timeline), 0)
        timeline.markers = [Marker(time: 20, name: "Drop here", color: .purple), Marker(time: 40, name: "drop", color: .purple),
                            Marker(time: 10, name: "Chapter 1", color: .blue), Marker(time: 30, name: "Drop", color: .purple, aiGenerated: true)]
        XCTAssertEqual(timeline.musicDropTimes, [20, 40], "yours only, in order")
        XCTAssertEqual(EditPolish.applyDropMarkers(&timeline), 2)
        let volume = timeline.tracks[a].clips[0].audio.volume
        XCTAssertEqual(volume.value(at: 20.5), 0, accuracy: 1e-6)
        XCTAssertEqual(volume.value(at: 15), 0.3, accuracy: 1e-6)
        XCTAssertEqual(volume.value(at: 40.5), 0, accuracy: 1e-6)
    }

    func testProgressBarSlidesAcrossTheWholeVideo() {
        var timeline = Fixtures.simpleTimeline(clipDuration: 120)
        let tracks = timeline.tracks.count
        XCTAssertTrue(ProgressBar.add(&timeline))
        XCTAssertTrue(ProgressBar.isPresent(timeline))
        XCTAssertEqual(timeline.tracks.count, tracks + 1)
        let track = timeline.tracks.first { $0.name == ProgressBar.trackName }!
        XCTAssertEqual(track.kind, .video)
        let bar = track.clips[0]
        XCTAssertEqual(bar.duration, 120, accuracy: 1e-9)
        XCTAssertEqual(bar.transform.positionX.value(at: 0), -0.5, accuracy: 1e-9, "nothing showing")
        XCTAssertEqual(bar.transform.positionX.value(at: 60), 0, accuracy: 1e-6, "half way")
        XCTAssertEqual(bar.transform.positionX.value(at: 120), 0.5, accuracy: 1e-9, "full width")
        XCTAssertEqual(bar.transform.crop.height, 0.006, accuracy: 1e-9)
        XCTAssertGreaterThan(bar.transform.positionY.value, 0.99)
        XCTAssertEqual(bar.role, .graphic)
        XCTAssertFalse(ProgressBar.add(&timeline), "only once")
        XCTAssertTrue(ProgressBar.remove(&timeline))
        XCTAssertEqual(timeline.tracks.count, tracks)
        XCTAssertFalse(ProgressBar.remove(&timeline))
        var short = Fixtures.simpleTimeline(clipDuration: 8)
        XCTAssertFalse(ProgressBar.add(&short), "not on an 8-second clip")
        XCTAssertTrue(EditQualityCheck.blackGaps(in: timeline.tracks[0].clips).isEmpty)
    }

    func testHookStingSitsQuietlyAtTheTop() {
        var timeline = Fixtures.simpleTimeline(clipDuration: 30)
        var whoosh = Fixtures.mediaAsset(duration: 0.9)
        whoosh.name = "Whoosh"
        ShortBuilder.addHookSting(whoosh, to: &timeline)
        let sting = timeline.allClips.first { $0.name == "Hook Sting" }
        XCTAssertNotNil(sting)
        XCTAssertEqual(sting?.start ?? -1, 0.08, accuracy: 1e-9)
        XCTAssertEqual(sting?.role, .soundEffect)
        XCTAssertLessThan(sting?.audio.volume.value ?? 1, 0.5)
        XCTAssertEqual(sting?.duration ?? 0, 0.9, accuracy: 1e-9)
        var settings = AISettings()
        settings.hookSting = true
        XCTAssertTrue(ShortBuildOptions(settings: settings).hookSting)
        XCTAssertFalse(ShortBuildOptions().hookSting)
        let decoded = try? JSONDecoder().decode(AISettings.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded?.hookSting, false)
        XCTAssertEqual(decoded?.longFormProgressBar, false)
    }

    func testFuzzyMatchingRanksSensibly() {
        XCTAssertNotNil(FuzzyMatch.score("qexp", in: "Quick Export"))
        XCTAssertNil(FuzzyMatch.score("qxz", in: "Quick Export"))
        XCTAssertNil(FuzzyMatch.score("z", in: "Quick Export"), "a single letter needs a real substring")
        XCTAssertNotNil(FuzzyMatch.score("x", in: "Quick Export"), "…which x is")
        let exact = FuzzyMatch.score("export", in: "Export…")!
        let wordStart = FuzzyMatch.score("export", in: "Quick Export")!
        let inside = FuzzyMatch.score("port", in: "Quick Export")!
        let scattered = FuzzyMatch.score("qexp", in: "Quick Export")!
        XCTAssertGreaterThan(exact, wordStart)
        XCTAssertGreaterThan(wordStart, inside)
        XCTAssertGreaterThan(inside, scattered)
        let ranked = FuzzyMatch.rank("spl", items: ["Freeze Frame", "Split All Tracks at Playhead", "Split at Playhead", "Snapping"], text: { $0 })
        XCTAssertEqual(ranked.first, "Split All Tracks at Playhead", "\(ranked)")
        XCTAssertEqual(ranked.count, 2, "snapping has no l after its p: \(ranked)")
        XCTAssertEqual(FuzzyMatch.score("", in: "anything"), 0)
    }

    func testCloudFoldersAreDetected() {
        let home = "/Users/me"
        let present: Set<String> = [home + "/Library/Mobile Documents/com~apple~CloudDocs", home + "/Library/CloudStorage", home + "/Dropbox"]
        let folders = CloudFolders.detect(home: home, exists: { present.contains($0) },
                                          list: { $0 == home + "/Library/CloudStorage" ? ["GoogleDrive-me@gmail.com", "OneDrive-Personal", "Other"] : [] })
        XCTAssertEqual(folders.map(\.name), ["iCloud Drive", "Google Drive (me@gmail.com)", "OneDrive (Personal)", "Dropbox"])
        XCTAssertEqual(folders[1].path, home + "/Library/CloudStorage/GoogleDrive-me@gmail.com")
        XCTAssertEqual(folders[3].path, home + "/Dropbox")
        XCTAssertTrue(CloudFolders.detect(home: home, exists: { _ in false }, list: { _ in [] }).isEmpty)
    }

    func testSpellingCandidatesSkipWhatIsntAWord() {
        let words = ["Hello", "gg", "LOL", "2024", "Valorant", "teh", "don't", "🔥", "a", "HP", "Reyna", "wrld"].enumerated().map { i, t in
            CaptionWord(text: t, start: Double(i), end: Double(i) + 0.3)
        }
        var hidden = CaptionWord(text: "hiddenword", start: 20, end: 20.3)
        hidden.isHidden = true
        let checkable = CaptionSpelling.checkable(words + [hidden], known: ["Valorant", "reyna"])
        XCTAssertEqual(checkable.map(\.text), ["Hello", "teh", "don't", "wrld"])
        XCTAssertEqual(CaptionSpelling.normalize("“Hello,”"), "hello")
    }
}
