import XCTest
@testable import PulseCore

/// Roadmap batch 16: update channel (#454), keyboard caption editing (#256), intro bumper (#373), music tempo
/// by pacing (#102), monitoring note (#283), accent colour (#425), clip labels (#177), humanized effects
/// (#284), frame-locked stepping (#178).
final class Batch16Tests: XCTestCase {
    func release(_ tag: String, prerelease: Bool = false, body: String = "notes") -> String {
        """
        {"tag_name": "\(tag)", "name": "PULSE \(tag)", "body": "\(body)\\n\\n## Install\\nsteps", "html_url": "https://x/\(tag)", "draft": false, "prerelease": \(prerelease),
         "assets": [{"name": "PULSE.dmg", "browser_download_url": "https://x/\(tag)/PULSE.dmg", "size": 10}]}
        """
    }

    func testBetaChannelSeesPrereleasesAndMissedNotesStack() throws {
        let list = Data("[\(release("v1.7.0-beta.1", prerelease: true, body: "beta things")), \(release("v1.6.0", body: "six")), \(release("v1.5.0", body: "five"))]".utf8)
        let stable = ReleaseInfo.newest(in: list, channel: .stable)
        XCTAssertEqual(stable?.tag, "v1.6.0")
        XCTAssertFalse(stable?.prerelease ?? true)
        let beta = ReleaseInfo.newest(in: list, channel: .beta)
        XCTAssertEqual(beta?.tag, "v1.7.0-beta.1")
        XCTAssertTrue(beta?.prerelease ?? false)
        XCTAssertNil(ReleaseInfo.parse(Data(release("v1.7.0-beta.1", prerelease: true).utf8)), "the single-release parser still refuses betas")
        let all = ReleaseInfo.parseAll(list, includePrereleases: false)
        XCTAssertEqual(all.map(\.tag), ["v1.6.0", "v1.5.0"], "newest first")
        let missed = ReleaseInfo.missedNotes(all, since: AppVersion("1.4.0"))
        XCTAssertTrue(missed.hasPrefix("**PULSE v1.6.0**\nsix"), missed)
        XCTAssertTrue(missed.contains("**PULSE v1.5.0**\nfive"))
        XCTAssertFalse(missed.contains("Install"))
        XCTAssertEqual(ReleaseInfo.missedNotes(all, since: AppVersion("1.5.0")), "six", "one release: just its notes")
        XCTAssertEqual(ReleaseInfo.missedNotes(all, since: AppVersion("1.6.0")), "")
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded.updateChannel, .stable)
        XCTAssertEqual(decoded.accent, .pulse)
        XCTAssertNotEqual(AccentChoice.electric.hex, AccentChoice.pulse.hex)
    }

    func testKeyboardCaptionEditing() throws {
        var captions = CaptionTrack(sourceAssetID: Fixtures.assetID, words: [
            CaptionWord(text: "hello", start: 0, end: 0.3), CaptionWord(text: "there", start: 0.35, end: 0.6, isHidden: true),
            CaptionWord(text: "Mc", start: 0.65, end: 0.8), CaptionWord(text: "Donald", start: 0.82, end: 1.1, isEmphasized: true),
            CaptionWord(text: "okay", start: 1.2, end: 1.5),
        ], style: .tiktok)
        let ids = captions.words.map(\.id)
        // Tab skips hidden words.
        XCTAssertEqual(captions.neighborWord(of: ids[0], step: 1)?.id, ids[2])
        XCTAssertEqual(captions.neighborWord(of: ids[2], step: -1)?.id, ids[0])
        XCTAssertNil(captions.neighborWord(of: ids[0], step: -1))
        // ⌫ merges "Donald" into "Mc".
        XCTAssertEqual(captions.mergeIntoPrevious(id: ids[3]), ids[2])
        XCTAssertEqual(captions.words.count, 4)
        XCTAssertEqual(captions.words[2].text, "Mc Donald")
        XCTAssertEqual(captions.words[2].end, 1.1)
        XCTAssertTrue(captions.words[2].isEmphasized)
        XCTAssertNil(captions.mergeIntoPrevious(id: ids[0]), "nothing before the first word")
        // Return breaks the page after "hello".
        XCTAssertEqual(captions.toggleBreak(afterID: ids[0]), true)
        var timeline = Fixtures.simpleTimeline(clipDuration: 10)   // source 100…110
        captions.words = captions.words.map { w in var w = w; w.start += 100; w.end += 100; return w }
        timeline.captions = captions
        let words = CaptionLayoutEngine.timelineWords(captions, in: timeline)
        XCTAssertTrue(words.first?.breakAfter ?? false)
        var style = CaptionStyle.tiktok
        style.maxWordsPerPage = 10
        let pages = CaptionLayoutEngine.pages(words, style: style)
        XCTAssertEqual(pages.count, 2, "\(pages.map { $0.lines.flatMap { $0.map(\.text) } })")
        XCTAssertEqual(pages[0].lines.flatMap { $0 }.map(\.text), ["hello"])
        XCTAssertEqual(captions.toggleBreak(afterID: ids[0]), false)
        // Old projects decode without the new key.
        let old = try JSONDecoder().decode(CaptionWord.self, from: Data(#"{"id":"\#(UUID().uuidString)","text":"x","start":0,"end":1,"isEmphasized":false,"emphasisIsAI":false,"isHidden":false}"#.utf8))
        XCTAssertFalse(old.pageBreakAfter)
        let roundTrip = try JSONDecoder().decode(CaptionWord.self, from: JSONEncoder().encode(captions.words[0]))
        XCTAssertFalse(roundTrip.pageBreakAfter)
    }

    func testIntroBumperRipplesEverythingRight() {
        var timeline = Fixtures.simpleTimeline(clipDuration: 30)
        timeline.markers = [Marker(time: 5, name: "Payoff", color: .orange)]
        let before = timeline.duration
        XCTAssertTrue(IntroBumper.add(&timeline, name: "Xay", handle: "xay"))
        XCTAssertEqual(timeline.duration, before + 3, accuracy: 1e-9)
        let slate = timeline.tracks[0].clips[0]
        XCTAssertEqual(slate.name, IntroBumper.clipName)
        XCTAssertEqual(slate.role, .graphic)
        XCTAssertEqual(slate.start, 0)
        XCTAssertEqual(slate.duration, 3, accuracy: 1e-9)
        XCTAssertEqual(slate.transitionOut?.kind, .fadeToBlack)
        XCTAssertEqual(timeline.tracks[0].clips[1].start, 3, accuracy: 1e-9)
        XCTAssertEqual(timeline.markers.first { $0.name == "Payoff" }?.time ?? -1, 8, accuracy: 1e-9)
        let texts = timeline.tracks.first { $0.kind == .text }!.clips.filter { $0.name == IntroBumper.clipName }
        XCTAssertEqual(texts.count, 2, "name and handle")
        if case .text(let element) = texts[0].content { XCTAssertEqual(element.text, "Xay") }
        if case .text(let element) = texts[1].content { XCTAssertEqual(element.text, "@xay") }
        XCTAssertTrue(texts.allSatisfy { $0.end <= 3.001 })
        XCTAssertTrue(EditQualityCheck.blackGaps(in: timeline.tracks[0].clips).isEmpty)
        XCTAssertFalse(IntroBumper.add(&timeline, name: "Xay"), "only once")
        XCTAssertFalse(IntroBumper.add(&timeline, name: "   "))
        // The brand kit adds it when there's no intro clip, and takes it out again.
        var kit = BrandKit()
        kit.bumperName = "Xay"
        XCTAssertTrue(kit.hasAnything)
        var plain = Fixtures.simpleTimeline(clipDuration: 30)
        BrandKitApplier.apply(kit, assets: BrandKitAssets(), to: &plain, longForm: true, handle: "@xay")
        XCTAssertEqual(plain.tracks[0].clips[0].name, IntroBumper.clipName)
        BrandKitApplier.removeBrand(from: &plain)
        XCTAssertFalse(plain.allClips.contains { $0.name == IntroBumper.clipName })
        XCTAssertEqual(plain.duration, 30, accuracy: 1e-9)
        var short = Fixtures.simpleTimeline(clipDuration: 30)
        BrandKitApplier.apply(kit, assets: BrandKitAssets(), to: &short, longForm: false)
        XCTAssertFalse(short.allClips.contains { $0.name == IntroBumper.clipName }, "never on shorts")
        let decoded = try? JSONDecoder().decode(BrandKit.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded?.bumperName, "")
    }

    func testMusicPaceFollowsTheCutRate() throws {
        XCTAssertEqual(MusicPace(cutsPerMinute: 2), .slow)
        XCTAssertEqual(MusicPace(cutsPerMinute: 7), .medium)
        XCTAssertEqual(MusicPace(cutsPerMinute: 14), .fast)
        let medium = MusicPicker.queries(for: [.gaming])
        let fast = MusicPicker.queries(for: [.gaming], pace: .fast)
        let slow = MusicPicker.queries(for: [.story], pace: .slow)
        XCTAssertEqual(medium.mood, "chill gaming")
        XCTAssertEqual(fast.mood, "chill gaming upbeat")
        XCTAssertTrue(fast.queries.allSatisfy { $0.contains("upbeat") || $0.contains("energetic") }, "\(fast.queries)")
        XCTAssertGreaterThan(fast.queries.count, medium.queries.count)
        XCTAssertTrue(slow.queries.allSatisfy { $0.contains("slow") }, "\(slow.queries)")
        XCTAssertEqual(slow.mood, "ambient slow")
        var timeline = Fixtures.simpleTimeline(clipDuration: 60)
        XCTAssertEqual(timeline.cutsPerMinute, 0)
        for t in stride(from: 10.0, to: 60, by: 10) { _ = try timeline.split(at: t) }
        XCTAssertEqual(timeline.cutsPerMinute, 5, accuracy: 1e-9)
    }

    func testMonitoringNoteOnlyWhenItMatters() {
        XCTAssertTrue(MixingAdvice.line(outputName: "MacBook Pro Speakers", kind: .builtInSpeakers)?.contains("headphones") ?? false)
        XCTAssertTrue(MixingAdvice.line(outputName: "AirPods Pro", kind: .bluetooth)?.contains("behind the picture") ?? false)
        XCTAssertNil(MixingAdvice.line(outputName: "Scarlett 2i2", kind: .usb))
        XCTAssertNil(MixingAdvice.line(outputName: "External Headphones", kind: .headphoneJack))
        XCTAssertTrue(MixingAdvice.line(outputName: "", kind: .builtInSpeakers)?.contains("the built-in speakers") ?? false)
    }

    func testClipLabelsAndFilter() throws {
        var timeline = Fixtures.simpleTimeline(clipDuration: 30)
        _ = try timeline.split(at: 10)
        let ids = timeline.tracks[0].clips.map(\.id)
        XCTAssertTrue(timeline.labelsInUse.isEmpty)
        XCTAssertEqual(timeline.setLabel(.green, clipIDs: [ids[0]]), 1)
        XCTAssertEqual(timeline.setLabel(.green, clipIDs: [ids[0]]), 0, "already green")
        XCTAssertEqual(timeline.labelsInUse, [.green])
        XCTAssertEqual(timeline.clips(label: .green).map(\.id), [ids[0]])
        XCTAssertEqual(timeline.setLabel(nil, clipIDs: Set(ids)), 1)
        XCTAssertTrue(timeline.clips(label: .green).isEmpty)
        XCTAssertEqual(MarkerColor.cyan.displayName, "Cyan")
    }

    func testHumanizedEffectsAreSmallStableAndOnlyOnEffects() {
        var timeline = Fixtures.simpleTimeline(clipDuration: 30)
        let a = timeline.tracks.firstIndex { $0.kind == .audio }!
        for i in 0..<6 {
            var sfx = TimelineClip(name: "Whoosh", content: .media(assetID: Fixtures.assetID), start: Double(i) * 4, sourceDuration: 0.5, role: .soundEffect, aiGenerated: true)
            sfx.audio.volume = AnimatedDouble(0.8)
            timeline.tracks[a].clips.append(sfx)
        }
        timeline.tracks[a].sortClips()
        var twin = timeline
        XCTAssertEqual(EditPolish.humanizeEffects(&timeline, seed: 7), 6)
        XCTAssertEqual(EditPolish.humanizeEffects(&twin, seed: 7), 6)
        let levels = timeline.tracks[a].clips.filter { $0.role == .soundEffect }.map { $0.audio.volume.value }
        XCTAssertEqual(levels, twin.tracks[a].clips.filter { $0.role == .soundEffect }.map { $0.audio.volume.value }, "deterministic")
        XCTAssertTrue(levels.allSatisfy { $0 >= 0.8 * 0.95 - 1e-9 && $0 <= 0.8 * 1.05 + 1e-9 }, "\(levels)")
        XCTAssertGreaterThan(Set(levels.map { Int($0 * 10_000) }).count, 2, "not all the same: \(levels)")
        XCTAssertEqual(timeline.tracks[a].clips.first { $0.role != .soundEffect }?.audio.volume.value, 1, "dialogue untouched")
        var other = timeline
        XCTAssertEqual(EditPolish.humanizeEffects(&other, seed: 8), 6)
        XCTAssertNotEqual(other.tracks[a].clips.filter { $0.role == .soundEffect }.map { $0.audio.volume.value }, levels, "another seed, other levels")
    }

    func testFrameLockedStepping() {
        let fps = 30000.0 / 1001
        var t: Seconds = 0
        for _ in 0..<1000 { t = Timecode.stepped(t, frames: 1, fps: fps) }
        XCTAssertEqual(t * fps, 1000, accuracy: 1e-6, "a thousand steps land on frame 1000 exactly")
        XCTAssertEqual(Timecode.stepped(0.5, frames: -1, fps: 30), 14.0 / 30, accuracy: 1e-9, "from inside frame 15 back to frame 14")
        XCTAssertEqual(Timecode.stepped(0.0, frames: -1, fps: 30), 0)
        XCTAssertEqual(Timecode.frameAligned(0.999, fps: 30), 29.0 / 30, accuracy: 1e-9)
        XCTAssertEqual(Timecode.frameAligned(1.0, fps: 30), 1.0, accuracy: 1e-9, "exactly on a frame stays")
        XCTAssertEqual(Timecode.stepped(5, frames: 3, fps: 0), 5, "no frame rate, no change")
    }
}
