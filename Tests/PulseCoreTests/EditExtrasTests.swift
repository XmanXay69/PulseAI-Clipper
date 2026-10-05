import XCTest
@testable import PulseCore

final class EditExtrasTests: XCTestCase {
    let asset = UUID()

    func words(_ items: [(String, Seconds, Seconds)], speaker: Int? = nil) -> [TranscriptWord] {
        items.map { TranscriptWord(text: $0.0, start: $0.1, end: $0.2, speaker: speaker) }
    }

    // MARK: Asking

    func testEverythingIsOffUntilYouSayYes() throws {
        let fresh = EditExtras()
        XCTAssertFalse(fresh.anyEditTime || fresh.approveCut || fresh.loudnessCheck)
        XCTAssertEqual(LongFormOptions().extras, EditExtras())
        // Old settings files have no answers yet: they decode as "no".
        let decoded = try JSONDecoder().decode(EditExtras.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, EditExtras())
        let settings = try JSONDecoder().decode(AISettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.editExtras, EditExtras())
        // And the answers survive a round trip.
        let answers = EditExtras(brollClips: true, titleCards: true, loudnessCheck: true)
        XCTAssertEqual(try JSONDecoder().decode(EditExtras.self, from: JSONEncoder().encode(answers)), answers)
    }

    // MARK: Speaker-aware

    func testSectionsSnapToWholeSentences() {
        let w = words([("So", 8.0, 8.2), ("I", 8.3, 8.4), ("went", 8.5, 8.8), ("in.", 8.9, 9.2),
                       ("Then", 10.0, 10.3), ("he", 10.4, 10.5), ("just", 10.6, 10.9), ("left.", 11.0, 11.4)])
        // Starts mid-sentence ("went") and ends mid-sentence ("just").
        let segment = LongFormSegment(range: TimeRange(start: 8.5, end: 10.7), payoff: 10, potential: 60, title: "", tags: [])
        let snapped = SpeakerAware.snapToSentences([segment], words: w, duration: 60)[0]
        XCTAssertEqual(snapped.range.start, 7.9, accuracy: 0.01, "back to the start of “So I went in.”")
        XCTAssertEqual(snapped.range.end, 11.65, accuracy: 0.01, "through to the end of “…just left.”")
    }

    func testSnappingNeverReachesTooFar() {
        // A sentence that started 10 s earlier: leave the start alone.
        let w = words(stride(from: 0.0, to: 20, by: 0.5).map { ("word", $0, $0 + 0.4) })
        let segment = LongFormSegment(range: TimeRange(start: 10.1, end: 12), payoff: 11, potential: 60, title: "", tags: [])
        let snapped = SpeakerAware.snapToSentences([segment], words: w, duration: 60)[0]
        XCTAssertEqual(snapped.range.start, 10.1, accuracy: 0.001)
    }

    func testCrosstalkNeedsTwoSpeakersAndSparesThePayoff() {
        let a = words(stride(from: 10.0, to: 14, by: 0.4).map { ("a", $0, $0 + 0.38) }, speaker: 0)
        let b = words(stride(from: 10.1, to: 14, by: 0.4).map { ("b", $0, $0 + 0.38) }, speaker: 1)
        let range = TimeRange(start: 0, end: 60)
        let found = SpeakerAware.crosstalk(in: range, words: a + b, protect: 40)
        XCTAssertEqual(found.count, 1)
        XCTAssertGreaterThan(found[0].duration, 3)
        XCTAssertTrue(SpeakerAware.crosstalk(in: range, words: a + b, protect: 12).isEmpty, "never cut the payoff")
        XCTAssertTrue(SpeakerAware.crosstalk(in: range, words: a, protect: 40).isEmpty, "one speaker isn't crosstalk")
        XCTAssertTrue(SpeakerAware.crosstalk(in: range, words: words([("x", 10, 14)]), protect: 40).isEmpty, "no labels, no trimming")
    }

    // MARK: Retention cards

    func testCardsOnlyAfterRealJumps() {
        let segments = [
            LongFormSegment(range: TimeRange(start: 0, end: 60), payoff: 30, potential: 60, title: "", tags: []),
            LongFormSegment(range: TimeRange(start: 90, end: 150), payoff: 120, potential: 60, title: "", tags: [.funny]),  // 30 s jump
            LongFormSegment(range: TimeRange(start: 900, end: 960), payoff: 930, potential: 60, title: "", tags: [.fail]), // 12½ min jump
            LongFormSegment(range: TimeRange(start: 1100, end: 1160), payoff: 1130, potential: 60, title: "", tags: [.story]),
        ]
        var t = Timeline(name: "t", canvas: .landscape1080, tracks: [Track(kind: .video, name: "V1"), Track(kind: .text, name: "T1")])
        t.tracks[0].clips = [TimelineClip(name: "v", content: .media(assetID: asset), start: 0, sourceDuration: 300)]
        // The third section comes only 60 s after the second card: too soon for another.
        XCTAssertEqual(RetentionCards.add(&t, segments: segments, starts: [5, 65, 125, 185], hookEnd: 5), 1)
        t.tracks[1].clips = []
        XCTAssertEqual(RetentionCards.add(&t, segments: segments, starts: [5, 65, 125, 230], hookEnd: 5), 2)
        let cards = t.tracks[1].clips
        XCTAssertEqual(cards[0].start, 125.1, accuracy: 0.001)
        XCTAssertEqual(cards[1].start, 230.1, accuracy: 0.001)
        if case .text(let first) = cards[0].content { XCTAssertEqual(first.text, "13 MINUTES LATER…") } else { XCTFail() }
        if case .text(let second) = cards[1].content { XCTAssertEqual(second.text, "WAIT FOR IT…") } else { XCTFail() }
    }

    func testCardsStayOffOtherText() {
        let segments = [LongFormSegment(range: TimeRange(start: 0, end: 60), payoff: 30, potential: 60, title: "", tags: []),
                        LongFormSegment(range: TimeRange(start: 600, end: 660), payoff: 630, potential: 60, title: "", tags: [])]
        var t = Timeline(name: "t", canvas: .landscape1080, tracks: [Track(kind: .text, name: "T1")])
        t.tracks[0].clips = [TimelineClip(name: "Meme", content: .text(TextElement(text: "BRUH")), start: 66, sourceDuration: 1.3)]
        XCTAssertEqual(RetentionCards.add(&t, segments: segments, starts: [5, 65], hookEnd: 5), 0)
    }

    // MARK: Facecam

    func testFacecamPunchInFramesTheFacecam() {
        var t = Timeline(name: "t", canvas: .landscape1080, tracks: [Track(kind: .video, name: "V1")])
        t.tracks[0].clips = [TimelineClip(name: "v", content: .media(assetID: asset), start: 10, sourceDuration: 30)]
        let cam = NormRect(x: 0.72, y: 0.62, width: 0.24, height: 0.3)
        XCTAssertEqual(FacecamPunchIn.apply(&t, at: [20, 39.5], region: cam), 1, "too close to the clip's end for the second")
        let clip = t.tracks[0].clips[0]
        let crop = clip.transform.effectiveCrop(at: 10.9)   // clip-local: 0.9 s into the hold
        XCTAssertTrue(crop.contains(cam.center), "the facecam is in the frame")
        XCTAssertLessThan(crop.width, 0.5, "and fills most of it")
        XCTAssertEqual(clip.transform.effectiveCrop(at: 5), .full, "normal framing before")
        XCTAssertEqual(clip.transform.effectiveCrop(at: 15), .full, "and after")
    }

    // MARK: Beats

    func testBeatGridFromAClickTrack() {
        let hop = 0.01
        var onsets = [Float](repeating: 0.05, count: 3000)
        for i in stride(from: 37, to: 3000, by: 50) { onsets[i] = 1 }   // 120 BPM, first beat at 0.37 s
        let beats = BeatSync.beats(onsets: onsets, hop: hop, duration: 30)
        XCTAssertGreaterThan(beats.count, 55)
        XCTAssertEqual(beats[0], 0.37, accuracy: 0.011)
        let gaps = zip(beats.dropFirst(), beats).map { $0 - $1 }
        XCTAssertEqual(gaps.reduce(0, +) / Double(gaps.count), 0.5, accuracy: 0.01)
        XCTAssertEqual(beats.last!.truncatingRemainder(dividingBy: 0.5), 0.37, accuracy: 0.011, "no drift across the track")
    }

    func testBeatGridFollowsATempoThatIsNotAWholeNumberOfHops() {
        let hop = 0.0116
        let period = 0.4321
        var onsets = [Float](repeating: 0, count: 15_000)
        var t = 0.2
        var truth: [Double] = []
        while Int((t / hop).rounded()) < onsets.count { onsets[Int((t / hop).rounded())] = 1; truth.append(t); t += period }
        let beats = BeatSync.beats(onsets: onsets, hop: hop, duration: Double(onsets.count) * hop)
        XCTAssertGreaterThan(beats.count, truth.count - 3)
        for b in beats.suffix(20) {
            let nearest = truth.min { abs($0 - b) < abs($1 - b) }!
            XCTAssertEqual(b, nearest, accuracy: hop * 1.5, "still on the beat at the end of a 3-minute track")
        }
    }

    func testMusicStartsOnTheBeatAndZoomsLandOnBeats() {
        let music = UUID()
        var t = Timeline(name: "t", canvas: .landscape1080, tracks: [Track(kind: .video, name: "V1"), Track(kind: .audio, name: "A2 Music")])
        var v = TimelineClip(name: "v", content: .media(assetID: asset), start: 0, sourceDuration: 60)
        // A punch-in hitting at 10.12 s; a pan rides along.
        for (time, value) in [(9.87, 1.0), (10.12, 1.16), (11.92, 1.16), (12.17, 1.0)] {
            v.transform.zoom.setKeyframe(at: time, value: value, aiGenerated: true)
            v.transform.panX.setKeyframe(at: time, value: value - 1, aiGenerated: true)
        }
        t.tracks[0].clips = [v]
        t.tracks[1].clips = [TimelineClip(name: "m", content: .media(assetID: music), start: 0, sourceDuration: 60, role: .music),
                             TimelineClip(name: "m", content: .media(assetID: music), start: 60, sourceDuration: 120, role: .music)]
        let grid = stride(from: 0.3, to: 120, by: 0.5).map { $0 }
        XCTAssertEqual(BeatSync.alignMusic(&t, beats: [music: grid], durations: [music: 120]), 2)
        XCTAssertEqual(t.tracks[1].clips[0].sourceIn, 0.3, accuracy: 0.001)
        XCTAssertEqual(t.tracks[1].clips[1].sourceDuration, 119.7, accuracy: 0.001, "a full-length piece gets shorter instead")
        let beats = BeatSync.timelineBeats(t, beats: [music: grid])
        XCTAssertEqual(beats.first, 0)
        XCTAssertEqual(BeatSync.snapZooms(&t, beats: beats), 1)
        let zoom = t.tracks[0].clips[0].transform.zoom.keyframes.map(\.time)
        XCTAssertEqual(zoom[1], 10.0, accuracy: 0.001, "the hit is on the beat")
        XCTAssertEqual(zoom[0], 9.75, accuracy: 0.001, "the whole zoom moved together")
        XCTAssertEqual(t.tracks[0].clips[0].transform.panX.keyframes.map(\.time), zoom, "the pan stays with it")
    }

    // MARK: B-roll

    func testBrollPicksStrongFunnyMomentsSpacedOut() {
        var segments: [LongFormSegment] = []
        for i in 0..<10 {
            let start = Double(i) * 100
            let potential = i == 3 ? 40 : 60 + i
            let tags: [ClipTag] = i % 2 == 0 ? [.funny] : [.conversation]
            segments.append(LongFormSegment(range: TimeRange(start: start, end: start + 60), payoff: start + 30, potential: potential, title: "", tags: tags))
        }
        let moments = BrollPlacer.moments(segments: segments, timelineTime: { $0 / 2 }, hookEnd: 5, duration: 600)
        XCTAssertFalse(moments.isEmpty)
        XCTAssertLessThanOrEqual(moments.count, 5)
        XCTAssertTrue(zip(moments.dropFirst(), moments).allSatisfy { $0.time - $1.time >= 60 })
        XCTAssertTrue(moments.allSatisfy { $0.query == "funny laughing reaction meme" })
        XCTAssertNil(BrollPlacer.score(VideoSearchResult(videoID: "a", title: "Green screen meme", channel: "", duration: 8)))
        XCTAssertNil(BrollPlacer.score(VideoSearchResult(videoID: "b", title: "meme compilation", channel: "", duration: 600)))
        XCTAssertNotNil(BrollPlacer.score(VideoSearchResult(videoID: "c", title: "bruh reaction meme no copyright", channel: "", duration: 6)))
    }

    func testBrollGoesOnItsOwnTrackWithItsSound() {
        var t = Timeline(name: "t", canvas: .landscape1080, tracks: [
            Track(kind: .video, name: "V1 Stream"), Track(kind: .text, name: "T1"), Track(kind: .audio, name: "A1"), Track(kind: .audio, name: "A3 SFX"),
        ])
        t.tracks[0].clips = [TimelineClip(name: "v", content: .media(assetID: asset), start: 0, sourceDuration: 120)]
        let clip = MediaAsset(name: "bruh", path: "/tmp/bruh.mp4", kind: .video,
                              metadata: MediaMetadata(duration: 6, width: 1280, height: 720, hasVideo: true, hasAudio: true))
        XCTAssertEqual(BrollPlacer.place(&t, clips: [(clip, 30), (clip, 31), (clip, 119)]), 1, "no overlaps, nothing past the end")
        XCTAssertEqual(t.tracks[1].name, "V2 B-roll", "right above the stream")
        let placed = t.tracks[1].clips[0]
        XCTAssertEqual(placed.duration, 2.4, accuracy: 0.001)
        XCTAssertEqual(placed.transform.fit, .fill)
        let sound = t.tracks.first { $0.name == "A3 SFX" }!.clips
        XCTAssertEqual(sound.count, 1)
        XCTAssertEqual(sound[0].linkGroup, placed.linkGroup)
        XCTAssertTrue(BrollPlacer.creditBlock([OnlineTrack(videoID: "x", title: "Bruh", channel: "Memes", duration: 6, mood: "b")]).contains("youtube.com/watch?v=x"))
    }

    // MARK: Loudness

    func testStreamingLoudnessMatchesTheMeter() {
        let rate = 48_000.0
        let n = Int(rate * 6)
        var left = [Float](repeating: 0, count: n), right = left
        for i in 0..<n {
            let t = Double(i) / rate
            let envelope: Float = t < 2 ? 0.05 : 0.3   // quiet start, loud rest (exercises the gates)
            left[i] = envelope * Float(sin(2 * .pi * 1000 * t))
            right[i] = envelope * Float(sin(2 * .pi * 440 * t))
        }
        let reference = LoudnessMeter.integratedLUFS([left, right], sampleRate: rate)
        var streaming = StreamingLoudness(sampleRate: rate)
        var at = 0
        while at < n {   // odd chunk sizes, like decoded buffers
            let count = min(4_321, n - at)
            streaming.add([Array(left[at..<(at + count)]), Array(right[at..<(at + count)])])
            at += count
        }
        XCTAssertEqual(streaming.integratedLUFS, reference, accuracy: 0.3)
        XCTAssertEqual(streaming.peakDB, 20 * log10(0.3), accuracy: 0.05)
    }

    func testLoudnessVerdicts() {
        XCTAssertEqual(LoudnessVerdict(lufs: -14.3, peakDB: -2, unleveledDialogue: true).action, .fine)
        if case .lower(let db) = LoudnessVerdict(lufs: -9, peakDB: -1, unleveledDialogue: false).action {
            XCTAssertEqual(db, 5, accuracy: 0.001)
        } else { XCTFail("too loud should offer to turn it down") }
        if case .lower(let db) = LoudnessVerdict(lufs: -14, peakDB: 0.4, unleveledDialogue: false).action {
            XCTAssertEqual(db, 1.4, accuracy: 0.001, "clipping peaks come down too")
        } else { XCTFail() }
        XCTAssertEqual(LoudnessVerdict(lufs: -22, peakDB: -8, unleveledDialogue: true).action, .levelDialogue)
        XCTAssertEqual(LoudnessVerdict(lufs: -22, peakDB: -8, unleveledDialogue: false).action, .quietButLeveled)
        XCTAssertTrue(LoudnessVerdict(lufs: -9, peakDB: -1, unleveledDialogue: false).summary.contains("Lower it by 5.0 dB?"))
    }

    func testLoudnessFixOnlyTouchesWhatItSays() {
        var t = Timeline(name: "t", canvas: .landscape1080, tracks: [Track(kind: .audio, name: "A1"), Track(kind: .audio, name: "A2")])
        var voice = TimelineClip(name: "voice", content: .media(assetID: asset), start: 0, sourceDuration: 10, role: .microphone)
        voice.audio.normalize = false
        t.tracks[0].clips = [voice]
        t.tracks[1].clips = [TimelineClip(name: "music", content: .media(assetID: UUID()), start: 0, sourceDuration: 10, role: .music)]
        XCTAssertTrue(LoudnessVerdict.hasUnleveledDialogue(t))

        var leveled = t
        XCTAssertEqual(LoudnessVerdict(lufs: -22, peakDB: -8, unleveledDialogue: true).apply(to: &leveled), 1)
        XCTAssertTrue(leveled.tracks[0].clips[0].audio.normalize)
        XCTAssertFalse(leveled.tracks[1].clips[0].audio.normalize, "music is left alone")

        var lowered = t
        XCTAssertEqual(LoudnessVerdict(lufs: -10, peakDB: -1, unleveledDialogue: true).apply(to: &lowered), 2)
        XCTAssertEqual(lowered.tracks[0].clips[0].audio.gainDB, -4, accuracy: 0.001)
        XCTAssertEqual(lowered.tracks[1].clips[0].audio.gainDB, -4, accuracy: 0.001)

        var untouched = t
        XCTAssertEqual(LoudnessVerdict(lufs: -14, peakDB: -3, unleveledDialogue: true).apply(to: &untouched), 0)
        XCTAssertEqual(untouched, t)
    }
}
