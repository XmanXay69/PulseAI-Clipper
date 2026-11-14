import XCTest
@testable import PulseCore

/// #521: music in the recording is found from its steady level and regular beat, and flagged where an edit uses it.
final class MusicDetectorTests: XCTestCase {
    /// A recording made of parts, each `(length, kind)`.
    private enum Sound { case music(beat: Seconds), speech, noise, silence, musicUnderSpeech }

    private func recording(_ parts: [(Seconds, Sound)], hop: Seconds = 0.1) -> AudioFeatureSeries {
        var rms: [Float] = [], flux: [Float] = [], zcr: [Float] = []
        var rng = SeededGenerator(seed: 521)
        func random() -> Float { Float(rng.next() % 10_000) / 10_000 }
        for (length, sound) in parts {
            let frames = Int(length / hop)
            for i in 0..<frames {
                let t = Double(i) * hop
                switch sound {
                case .music(let beat):
                    // A track: a level that barely moves and a kick on every beat.
                    let onBeat = (t / beat).rounded() * beat
                    rms.append(-20 + random() * 2 - 1)
                    flux.append(abs(t - onBeat) < hop / 2 ? 2.4 + random() * 0.4 : 0.15 + random() * 0.1)
                    zcr.append(0.12)
                case .speech:
                    // Words and pauses of uneven length, onsets at no fixed interval.
                    let talking = (Int(t * 1.7) + Int(t * 0.6)) % 3 != 0
                    rms.append(talking ? -16 + random() * 6 - 3 : -52 + random() * 4)
                    flux.append(random() < 0.12 ? 1.5 + random() * 1.5 : 0.1 + random() * 0.2)
                    zcr.append(talking ? 0.1 + random() * 0.3 : 0.05)
                case .noise:
                    // Rain, an engine: steady, with nothing repeating.
                    rms.append(-28 + random() * 2 - 1)
                    flux.append(0.2 + random() * 0.25)
                    zcr.append(0.3)
                case .silence:
                    rms.append(-80)
                    flux.append(0)
                    zcr.append(0)
                case .musicUnderSpeech:
                    // The track fills the pauses: the level never falls away, and the beat still shows.
                    let talking = (Int(t * 1.7) + Int(t * 0.6)) % 3 != 0
                    let onBeat = (t / 0.5).rounded() * 0.5
                    rms.append(talking ? -17 + random() * 3 : -23 + random() * 2)
                    flux.append(abs(t - onBeat) < hop / 2 ? 2.2 + random() * 0.5 : (random() < 0.08 ? 1.0 : 0.15 + random() * 0.1))
                    zcr.append(0.15)
                }
            }
        }
        return AudioFeatureSeries(hop: hop, rmsDB: rms, peakDB: rms.map { $0 + 6 }, zeroCrossingRate: zcr, spectralFlux: flux)
    }

    func testATrackIsFoundAndTalkingNoiseAndSilenceAreNot() throws {
        let audio = recording([(60, .speech), (45, .music(beat: 0.5)), (40, .noise), (20, .silence), (60, .speech)])
        let found = MusicDetector.stretches(in: audio)
        XCTAssertEqual(found.count, 1, "\(found)")
        let stretch = try XCTUnwrap(found.first)
        XCTAssertEqual(stretch.range.start, 60, accuracy: 8)
        XCTAssertEqual(stretch.range.end, 105, accuracy: 8)
        XCTAssertGreaterThan(stretch.confidence, 0.6)
        // Nothing but talking, steady noise or silence: nothing flagged.
        XCTAssertTrue(MusicDetector.stretches(in: recording([(120, .speech)])).isEmpty)
        XCTAssertTrue(MusicDetector.stretches(in: recording([(120, .noise)])).isEmpty)
        XCTAssertTrue(MusicDetector.stretches(in: recording([(120, .silence)])).isEmpty)
    }

    func testOtherTemposAndMusicUnderTalkingAreHeardAndAJingleIsNot() {
        // 100 and 150 beats a minute.
        XCTAssertEqual(MusicDetector.stretches(in: recording([(30, .speech), (40, .music(beat: 0.6)), (30, .speech)])).count, 1)
        XCTAssertEqual(MusicDetector.stretches(in: recording([(30, .speech), (40, .music(beat: 0.4)), (30, .speech)])).count, 1)
        // A track playing while the streamer talks over it: the commonest way a stream gets claimed.
        let under = MusicDetector.stretches(in: recording([(40, .speech), (60, .musicUnderSpeech), (40, .speech)]))
        XCTAssertEqual(under.count, 1, "\(under)")
        // Eight seconds of a jingle isn't a stretch worth flagging.
        XCTAssertTrue(MusicDetector.stretches(in: recording([(60, .speech), (8, .music(beat: 0.5)), (60, .speech)])).isEmpty)
        // Only the parts asked about are searched.
        let audio = recording([(60, .speech), (45, .music(beat: 0.5)), (60, .speech)])
        XCTAssertTrue(MusicDetector.stretches(in: audio, within: [TimeRange(start: 0, end: 40)]).isEmpty)
        XCTAssertEqual(MusicDetector.stretches(in: audio, within: [TimeRange(start: 70, end: 90)]).count, 1)
        // Too short to judge, or nothing at all: no crash, nothing flagged.
        XCTAssertTrue(MusicDetector.stretches(in: recording([(5, .music(beat: 0.5))])).isEmpty)
        XCTAssertTrue(MusicDetector.stretches(in: AudioFeatureSeries(hop: 0.1, rmsDB: [], peakDB: [], zeroCrossingRate: [], spectralFlux: [])).isEmpty)
    }

    func testAnEditIsFlaggedWhereItUsesTheMusicAndMutingSilencesOnlyThat() throws {
        // The fixture edit shows 100…160 s of a recording with a track playing from 120 to 150 s.
        let audio = recording([(120, .speech), (30, .music(beat: 0.5)), (50, .speech)])
        let analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: 200, audio: audio, transcript: nil, profile: .gameplay)
        var edit = Fixtures.simpleTimeline(clipDuration: 60)
        let flags = MusicRisk.flags(in: edit, analysis: analysis)
        XCTAssertEqual(flags.count, 1, "\(flags)")
        let flag = try XCTUnwrap(flags.first)
        XCTAssertEqual(flag.range.start, 20, accuracy: 8, "120 s in the recording is 20 s into the edit")
        XCTAssertEqual(flag.range.end, 50, accuracy: 8)
        XCTAssertFalse(MusicRisk.describe(flags).isEmpty)

        XCTAssertEqual(MusicRisk.mute(flags, in: &edit, assetID: Fixtures.assetID), 1)
        let sound = try XCTUnwrap(edit.tracks[3].clips.first)
        XCTAssertEqual(sound.audio.volume.value(at: flag.range.midpoint), 0, accuracy: 0.001)
        XCTAssertEqual(sound.audio.volume.value(at: 5), 1, accuracy: 0.001, "the talking before it is untouched")
        XCTAssertEqual(sound.audio.volume.value(at: 57), 1, accuracy: 0.001, "and so is the talking after")
        XCTAssertEqual(edit.duration, 60, accuracy: 0.001, "nothing is cut")
        XCTAssertEqual(edit.tracks[0].clips.count, 1, "the picture isn't split")
        // Once silenced it is no longer flagged.
        XCTAssertTrue(MusicRisk.flags(in: edit, analysis: analysis).isEmpty)

        // An edit that doesn't use that part, a muted track, or no analysis: no flags.
        XCTAssertTrue(MusicRisk.flags(in: Fixtures.simpleTimeline(clipDuration: 15), analysis: analysis).isEmpty)
        var muted = Fixtures.simpleTimeline(clipDuration: 60)
        muted.tracks[3].isMuted = true
        XCTAssertTrue(MusicRisk.flags(in: muted, analysis: analysis).isEmpty)
        XCTAssertTrue(MusicRisk.flags(in: Fixtures.simpleTimeline(clipDuration: 60), analysis: nil).isEmpty)
    }
}
