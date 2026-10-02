import XCTest
@testable import PulseCore

final class LongFormEditorTests: XCTestCase {
    /// A 50-minute stream: steady talking with long quiet stretches, a dozen big moments with laughter.
    func stream() -> (MediaAsset, MediaAnalysis) {
        let duration: Seconds = 3000
        let spikes = stride(from: 150.0, to: 2900, by: 230).map { $0 }
        var special: [(Seconds, String)] = []
        for s in spikes { for k in 0..<4 { special.append((s + 1 + Double(k) * 0.5, "hahaha")) } }
        special.append((spikes[3] + 0.2, "insane!"))
        let silences = stride(from: 60.0, to: 2950, by: 97).map { TimeRange(start: $0, end: $0 + 4) }
        // Talking everywhere except the quiet stretches.
        var words: [TranscriptWord] = []
        var t = 0.5, i = 0
        while t < duration - 1 {
            if !silences.contains(where: { $0.contains(t) || $0.contains(t + 0.35) }) {
                words.append(TranscriptWord(text: (i + 1) % 8 == 0 ? "okay." : "so", start: t, end: t + 0.32))
                i += 1
            }
            t += 0.4
        }
        for (time, text) in special {
            words.removeAll { abs($0.start - time) < 0.3 }
            words.append(TranscriptWord(text: text, start: time, end: time + 0.3))
        }
        let transcript = Transcript(language: "en", words: words.sorted { $0.start < $1.start }, source: .demo)
        let analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: duration,
                                     audio: Fixtures.audio(duration: duration, spikes: spikes, silences: silences),
                                     transcript: transcript, profile: .gameplay)
        return (Fixtures.mediaAsset(duration: duration), analysis)
    }

    func sounds() -> LongFormSounds {
        func sfx(_ name: String) -> MediaAsset {
            var a = MediaAsset(name: name, path: "/tmp/\(name).m4a", kind: .audio, role: .soundEffect,
                               metadata: MediaMetadata(duration: 1, hasVideo: false, hasAudio: true, audioTrackCount: 1))
            a.tags = [name.lowercased()]
            return a
        }
        return LongFormSounds(effects: ["Whoosh", "Boom", "Rimshot", "Impact", "Sad Trombone"].map(sfx))
    }

    func testBuildsATenToTwentyMinuteEditWithAHookAndRestrainedEffects() throws {
        let (asset, analysis) = stream()
        let result = LongFormEditor.build(asset: asset, analysis: analysis, sounds: sounds())
        let t = result.timeline
        XCTAssertGreaterThanOrEqual(t.duration, 8 * 60, result.report)
        XCTAssertLessThanOrEqual(t.duration, 21 * 60, result.report)
        XCTAssertEqual(t.canvas.width, 1920, "landscape YouTube canvas")

        // Story segments are chronological and don't repeat (apart from the hook teaser).
        let hookEnd = t.markers.first { $0.name == "Hook" }.map { _ in t.tracks[0].clips[0].duration } ?? 0
        XCTAssertGreaterThan(hookEnd, 3, "opens with a cold-open hook")
        XCTAssertLessThan(hookEnd, 9)
        let story = t.tracks[0].clips.filter { $0.start >= hookEnd - 0.01 }
        XCTAssertTrue(zip(story, story.dropFirst()).allSatisfy { $0.sourceIn < $1.sourceIn })
        XCTAssertTrue(t.tracks[1].clips.contains { $0.name == "Hook Title" })

        // The biggest moments made the cut.
        let kept = story.map(\.sourceRange)
        let spikesKept = stride(from: 150.0, to: 2900, by: 230).filter { s in kept.contains { $0.contains(s + 0.5) } }.count
        XCTAssertGreaterThanOrEqual(spikesKept, 9, "most big moments are in")

        // Dead air was cut, captions are on, chapters are listed.
        XCTAssertTrue(t.removedSections.contains { $0.reason == .silence })
        XCTAssertEqual(t.captions?.style.presetName, "YouTube")
        XCTAssertTrue(t.notes.hasPrefix("Chapters\n0:00 Intro"))

        // Not over-edited.
        let minutes = t.duration / 60
        let zoomPunchIns = t.tracks[0].clips.reduce(0) { $0 + $1.transform.zoom.keyframes.filter(\.aiGenerated).count / 3 }
        XCTAssertGreaterThan(zoomPunchIns, 0)
        XCTAssertLessThanOrEqual(Double(zoomPunchIns), minutes * 60 / 22 + 2)
        let memes = t.tracks[1].clips.filter { $0.name.hasPrefix("Meme") }
        XCTAssertGreaterThan(memes.count, 0)
        XCTAssertLessThanOrEqual(Double(memes.count), minutes * 60 / 90 + 1)
        let sfx = t.allClips.filter { $0.role == .soundEffect }
        XCTAssertGreaterThan(sfx.count, 0)
        XCTAssertLessThanOrEqual(Double(sfx.count), minutes * 2 + 2)

        // Music chapters cover the story after the hook, ~3–5 min each.
        XCTAssertFalse(result.musicChapters.isEmpty)
        XCTAssertEqual(result.musicChapters.first?.start ?? -1, hookEnd, accuracy: 0.01)
        XCTAssertEqual(result.musicChapters.last?.end ?? 0, t.duration, accuracy: 0.01)
        XCTAssertTrue(result.musicChapters.allSatisfy { $0.duration <= 330 })
    }

    func testMusicBedsGoOnA2DuckedAndQuiet() {
        let (asset, analysis) = stream()
        var result = LongFormEditor.build(asset: asset, analysis: analysis, sounds: sounds())
        let beds = result.musicChapters.map { range in
            MediaAsset(name: "Bed", path: "/tmp/bed.m4a", kind: .audio, role: .music,
                       metadata: MediaMetadata(duration: range.duration, hasVideo: false, hasAudio: true, audioTrackCount: 1))
        }
        LongFormEditor.addMusic(beds, chapters: result.musicChapters, to: &result.timeline)
        let music = result.timeline.allClips.filter { $0.role == .music }
        XCTAssertEqual(music.count, beds.count)
        XCTAssertTrue(music.allSatisfy { $0.audio.duckUnderDialogue && $0.audio.volume.value(at: 0) < 0.3 })
    }

    func testShortRecordingsKeepMostOfIt() {
        let duration: Seconds = 400
        let analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: duration,
                                     audio: Fixtures.audio(duration: duration, spikes: [100, 250]),
                                     transcript: Fixtures.transcript(duration: duration))
        let result = LongFormEditor.build(asset: Fixtures.mediaAsset(duration: duration), analysis: analysis, options: LongFormOptions(coldOpen: false))
        XCTAssertGreaterThan(result.timeline.duration, 120)
        XCTAssertLessThan(result.timeline.duration, 400)
        XCTAssertFalse(result.timeline.markers.contains { $0.name == "Hook" })
    }

    func testTargetLengthFollowsTheRecording() {
        let o = LongFormOptions()
        XCTAssertEqual(o.targetLength(forSource: 3 * 3600), 1200, "long streams cap at 20 min")
        XCTAssertEqual(o.targetLength(forSource: 3600), 600, "an hour → 10 min")
        XCTAssertEqual(o.targetLength(forSource: 600), 360, accuracy: 1e-9, "short recordings keep 60 %")
    }

    func testStoryboardPlanOffersAlternativesAndBuildsTheHandPickedMoments() throws {
        let (asset, analysis) = stream()
        let plan = LongFormEditor.planMoments(analysis: analysis, options: LongFormOptions())
        XCTAssertGreaterThan(plan.moments.count, plan.selected.count, "there are alternatives to swap in")
        XCTAssertTrue(zip(plan.moments, plan.moments.dropFirst()).allSatisfy { $0.range.start <= $1.range.start }, "listed in stream order")
        XCTAssertNotNil(plan.hook)
        XCTAssertGreaterThan(plan.keptLength(), 0)

        // Keep just three moments and open with the second one.
        let picked = Array(plan.moments.filter { plan.selected.contains($0.id) }.prefix(3))
        let hook = picked[1]
        let result = LongFormEditor.build(asset: asset, analysis: analysis, segments: picked, hookPayoff: hook.payoff)
        let story = result.timeline.tracks[0].clips.dropFirst()
        XCTAssertTrue(story.allSatisfy { clip in picked.contains { $0.range.expanded(by: 8).contains(clip.sourceIn) } }, "only the picked moments")
        let opener = result.timeline.tracks[0].clips[0]
        XCTAssertTrue(TimeRange(start: opener.sourceIn, end: opener.sourceOut).contains(hook.payoff), "the chosen hook opens the video")
    }
}
