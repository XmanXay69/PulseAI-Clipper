import XCTest
@testable import PulseCore

final class Batch35Tests: XCTestCase {
    // MARK: #194 / #281 — meters from waveform peaks

    func testPeakMeterReadsTheLoudestPeakAroundTheTime() {
        var peaks = [Float](repeating: 0.1, count: 500)   // 10 s at 50/s
        peaks[250] = 0.8                                  // 5.0 s
        XCTAssertEqual(PeakMeter.level(peaks: peaks, at: 5.0, perSecond: 50), 0.8)
        XCTAssertEqual(PeakMeter.level(peaks: peaks, at: 5.02, perSecond: 50), 0.8, "within the window")
        XCTAssertEqual(PeakMeter.level(peaks: peaks, at: 7, perSecond: 50), 0.1)
        XCTAssertEqual(PeakMeter.level(peaks: peaks, at: 40, perSecond: 50), 0, "past the end")
        XCTAssertEqual(PeakMeter.level(peaks: [], at: 1, perSecond: 50), 0)
        XCTAssertEqual(PeakMeter.dB(1), 0)
        XCTAssertEqual(PeakMeter.dB(0.5), -6.02, accuracy: 0.01)
        XCTAssertEqual(PeakMeter.dB(0), -60)
        XCTAssertEqual(PeakMeter.fraction(1), 1)
        XCTAssertEqual(PeakMeter.fraction(0), 0)
    }

    func testBallisticsHoldThenDecayAndStickOnClipping() {
        var b = PeakMeter.Ballistics()
        b.update(level: 0.8, at: 0)
        XCTAssertEqual(b.level, 0.8)
        XCTAssertEqual(b.hold, 0.8)
        b.update(level: 0.2, at: 0.5)
        XCTAssertEqual(b.level, 0.8 - 0.6, accuracy: 1e-6, "falls at 1.2 per second")
        XCTAssertEqual(b.hold, 0.8, "the hold tick stays for 1.5 s")
        b.update(level: 0.2, at: 2.0)
        XCTAssertEqual(b.hold, 0.2, "and then lets go")
        XCTAssertFalse(b.clipped)
        b.update(level: 1.0, at: 2.1)
        XCTAssertTrue(b.clipped)
        b.update(level: 0.1, at: 3.0)
        XCTAssertTrue(b.clipped, "sticky until reset")
        b.reset()
        XCTAssertFalse(b.clipped)
        XCTAssertEqual(b.level, 0)
    }

    func testMixMeterHonoursGainsMutesAndSolo() {
        let a = UUID(), m = UUID()
        var voice = Track(kind: .audio, name: "Voice")
        var clip = TimelineClip(name: "Talk", content: .media(assetID: a), start: 0, sourceIn: 10, sourceDuration: 20)
        clip.audio.gainDB = -6
        voice.clips = [clip]
        var music = Track(kind: .audio, name: "Music", volume: 0.5)
        music.clips = [TimelineClip(name: "Song", content: .media(assetID: m), start: 0, sourceDuration: 20)]
        var timeline = Timeline(name: "T", canvas: .vertical1080, tracks: [voice, music])
        func peaks(_ id: UUID) -> [Float]? { id == a ? [Float](repeating: 1, count: 2000) : [Float](repeating: 0.4, count: 2000) }
        let levels = MixMeter.levels(timeline, at: 5, perSecond: 50, peaks: peaks)
        XCTAssertEqual(levels.tracks[voice.id]!, 0.501, accuracy: 0.001, "−6 dB of a full-scale peak")
        XCTAssertEqual(levels.tracks[music.id]!, 0.2, accuracy: 1e-6, "0.4 × track volume 0.5")
        XCTAssertEqual(levels.master, 0.701, accuracy: 0.001, "the bus sees the sum")
        timeline.tracks[1].isSolo = true
        let soloed = MixMeter.levels(timeline, at: 5, perSecond: 50, peaks: peaks)
        XCTAssertEqual(soloed.tracks[voice.id], 0)
        XCTAssertEqual(soloed.master, 0.2, accuracy: 1e-6)
        timeline.tracks[1].isSolo = false
        timeline.tracks[0].isMuted = true
        XCTAssertEqual(MixMeter.levels(timeline, at: 5, perSecond: 50, peaks: peaks).tracks[voice.id], 0)
        XCTAssertEqual(MixMeter.trackLevel(timeline.tracks[1], at: 25, perSecond: 50, peaks: peaks), 0, "nothing under the playhead")
    }

    // MARK: #267 — voice / game balance

    func testMixBalanceSetsTrackVolumesAndReadsThemBack() {
        let mic = UUID(), game = UUID()
        var voice = Track(kind: .audio, name: "Mic")
        voice.clips = [TimelineClip(name: "Mic", content: .media(assetID: mic), start: 0, sourceDuration: 10, role: .microphone)]
        var gameTrack = Track(kind: .audio, name: "Game")
        gameTrack.clips = [TimelineClip(name: "Game", content: .media(assetID: game), start: 0, sourceDuration: 10, role: .gameplay)]
        var timeline = Timeline(name: "T", canvas: .landscape1080, tracks: [voice, gameTrack])
        let role: (TimelineClip) -> MediaRole? = { $0.role }
        XCTAssertTrue(MixBalance.isAvailable(in: timeline, role: role))
        XCTAssertEqual(MixBalance.current(in: timeline, role: role), 0)
        MixBalance.apply(-1, to: &timeline, role: role)
        XCTAssertEqual(timeline.tracks[1].volume, pow(10, -12 / 20), accuracy: 1e-9, "game 12 dB down")
        XCTAssertEqual(timeline.tracks[0].volume, 1)
        XCTAssertEqual(MixBalance.current(in: timeline, role: role)!, -1, accuracy: 1e-9)
        MixBalance.apply(0.5, to: &timeline, role: role)
        XCTAssertEqual(timeline.tracks[1].volume, 1)
        XCTAssertEqual(timeline.tracks[0].volume, pow(10, -6 / 20), accuracy: 1e-9, "voice 6 dB down")
        XCTAssertEqual(MixBalance.current(in: timeline, role: role)!, 0.5, accuracy: 1e-9)
        let onlyVoice = Timeline(name: "V", canvas: .landscape1080, tracks: [voice])
        XCTAssertFalse(MixBalance.isAvailable(in: onlyVoice, role: role))
        XCTAssertNil(MixBalance.current(in: onlyVoice, role: role))
    }

    // MARK: #273 — room tone

    func testRoomToneFillsShortGapsFromTheQuietestStretch() {
        let asset = UUID()
        var track = Track(kind: .audio, name: "A1")
        // Two clips of one recording with a 0.5 s gap between them.
        track.clips = [TimelineClip(name: "A", content: .media(assetID: asset), start: 0, sourceIn: 0, sourceDuration: 10),
                       TimelineClip(name: "B", content: .media(assetID: asset), start: 10.5, sourceIn: 20, sourceDuration: 10)]
        var timeline = Timeline(name: "T", canvas: .vertical1080, tracks: [track])
        // Loud everywhere except 6–7.5 s, which is quiet.
        var rms = [Float](repeating: -20, count: 400)   // 40 s at 0.1 s hops
        for i in 60..<75 { rms[i] = -55 }
        let features = AudioFeatureSeries(hop: 0.1, rmsDB: rms, peakDB: rms, zeroCrossingRate: [Float](repeating: 0, count: 400), spectralFlux: [Float](repeating: 0, count: 400))
        let filled = RoomTone.fill(&timeline, features: [asset: features])
        XCTAssertEqual(filled, 1)
        let clips = timeline.tracks[0].clips
        XCTAssertEqual(clips.count, 3)
        let tone = clips[1]
        XCTAssertEqual(tone.name, "Room tone")
        XCTAssertEqual(tone.start, 10, accuracy: 1e-9)
        XCTAssertEqual(tone.sourceDuration, 0.5, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(tone.sourceIn, 6 - 1e-9)
        XCTAssertLessThanOrEqual(tone.sourceIn + 0.5, 7.5 + 1e-9)
        XCTAssertEqual(tone.audio.gainDB, -6)
        XCTAssertTrue(tone.aiGenerated)
        // A second pass finds nothing left to fill; a wide gap is left alone.
        XCTAssertEqual(RoomTone.fill(&timeline, features: [asset: features]), 0)
        timeline.tracks[0].clips[2].start = 15
        XCTAssertEqual(RoomTone.fill(&timeline, features: [asset: features]), 0, "a 4.5 s gap is a real pause")
        XCTAssertNil(RoomTone.quietestWindow(in: TimeRange(start: 0, end: 0.2), features: features, length: 1), "too short for the window")
    }

    // MARK: #295 — instrumental stems

    func testInstrumentalStemsAreFoundByTitle() {
        let song = MediaAsset(name: "Neon Drive", path: "/m/neon.mp3", kind: .audio, role: .music)
        let inst = MediaAsset(name: "Neon Drive (Instrumental)", path: "/m/neon-inst.mp3", kind: .audio, role: .music)
        let other = MediaAsset(name: "Other Song - Instrumental", path: "/m/other.mp3", kind: .audio, role: .music)
        let video = MediaAsset(name: "Neon Drive instrumental", path: "/m/neon.mp4", kind: .video, role: .main)
        XCTAssertTrue(MusicStems.isInstrumental("Neon Drive (Instrumental)"))
        XCTAssertTrue(MusicStems.isInstrumental("Neon Drive - no vocals"))
        XCTAssertFalse(MusicStems.isInstrumental("Neon Drive"))
        XCTAssertEqual(MusicStems.baseTitle("Neon Drive (Instrumental)"), "neon drive")
        XCTAssertEqual(MusicStems.baseTitle("Neon_Drive - Inst Version"), "neon drive")
        XCTAssertEqual(MusicStems.instrumental(for: song, in: [song, inst, other, video])?.id, inst.id)
        XCTAssertNil(MusicStems.instrumental(for: song, in: [song, other, video]), "a video with the name doesn't count")
        XCTAssertNil(MusicStems.instrumental(for: inst, in: [song, inst]), "already instrumental")
        XCTAssertEqual(MusicStems.preferringInstrumentals([song, other], library: [song, inst, other]).map(\.id), [inst.id, other.id])
    }
}
