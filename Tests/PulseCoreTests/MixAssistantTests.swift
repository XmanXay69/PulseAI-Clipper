import XCTest
@testable import PulseCore

/// #761: a dialogue-first mix: the voice is the reference and everything else is placed under it.
final class MixAssistantTests: XCTestCase {
    private let voiceID = UUID(), gameID = UUID(), musicID = UUID(), boomID = UUID()

    /// A minute of voice on A1 with optional game sound, a music bed and one effect.
    private func mix(game: Bool = false, music: Bool = true, effect: Bool = true) -> Timeline {
        var t = Timeline.empty(name: "Mix", canvas: .vertical1080)
        t.tracks[3].clips = [TimelineClip(name: "Mic", content: .media(assetID: voiceID), start: 0, sourceIn: 0, sourceDuration: 60, role: .microphone)]
        if game {
            let track = t.addTrack(kind: .audio)
            let i = t.trackIndex(id: track)!
            t.tracks[i].clips = [TimelineClip(name: "Game", content: .media(assetID: gameID), start: 0, sourceIn: 0, sourceDuration: 60, role: .gameplay)]
        }
        if music {
            let track = t.addTrack(kind: .audio)
            let i = t.trackIndex(id: track)!
            t.tracks[i].clips = [TimelineClip(name: "Bed", content: .media(assetID: musicID), start: 0, sourceIn: 0, sourceDuration: 60, role: .music)]
        }
        if effect {
            let track = t.addTrack(kind: .audio)
            let i = t.trackIndex(id: track)!
            t.tracks[i].clips = [TimelineClip(name: "Boom", content: .media(assetID: boomID), start: 20, sourceIn: 0, sourceDuration: 1, role: .soundEffect)]
        }
        return t
    }

    private func clip(_ name: String, in timeline: Timeline) -> TimelineClip { timeline.allClips.first { $0.name == name }! }

    func testMusicAndEffectsThatFightTheVoiceAreBroughtUnderIt() throws {
        var timeline = mix()
        // The voice at a normal level; the bed only 6 dB under it and the effect louder than the voice.
        let levels = [voiceID: -18.0, musicID: -24.0, boomID: -10.0]
        let plan = MixAssistant.plan(timeline: timeline, levels: levels)
        XCTAssertEqual(plan.voiceLevel ?? 0, -18, accuracy: 0.01)
        let bed = try XCTUnwrap(plan.adjustments.first { $0.clipID == clip("Bed", in: timeline).id })
        XCTAssertEqual(bed.gain, -14, accuracy: 0.01, "to 20 dB under the voice")
        XCTAssertEqual(bed.duck, -6)
        let boom = try XCTUnwrap(plan.adjustments.first { $0.clipID == clip("Boom", in: timeline).id })
        XCTAssertEqual(boom.gain, -12, accuracy: 0.01, "to 4 dB under the voice")
        XCTAssertNil(boom.duck, "an effect is a moment, not a bed")
        XCTAssertFalse(plan.adjustments.contains { $0.clipID == clip("Mic", in: timeline).id }, "the voice is fine as it is")
        // What changed is said in words.
        XCTAssertTrue(plan.changes.contains { $0.stem == .music && $0.text.contains("14 dB") && $0.text.contains("while someone talks") }, "\(plan.changes)")
        XCTAssertTrue(plan.changes.contains { $0.stem == .effects })
        XCTAssertFalse(plan.summary.isEmpty)

        XCTAssertEqual(MixAssistant.apply(plan, to: &timeline), 2)
        XCTAssertEqual(clip("Bed", in: timeline).audio.gainDB, -14, accuracy: 0.01)
        XCTAssertTrue(clip("Bed", in: timeline).audio.duckUnderDialogue)
        XCTAssertEqual(clip("Bed", in: timeline).audio.duckAmountDB, -6)
        XCTAssertEqual(clip("Mic", in: timeline).audio.gainDB, 0)
        // Done once, there is nothing left to do.
        XCTAssertTrue(MixAssistant.plan(timeline: timeline, levels: levels).isEmpty)
    }

    func testAQuietVoiceComesUpAndEverythingFollowsItsNewLevel() throws {
        let timeline = mix(effect: false)
        let plan = MixAssistant.plan(timeline: timeline, levels: [voiceID: -30.0, musicID: -40.0])
        let mic = try XCTUnwrap(plan.adjustments.first { $0.clipID == clip("Mic", in: timeline).id })
        XCTAssertEqual(mic.gain, 12, accuracy: 0.01, "raised towards a speaking level, by no more than 12 dB")
        XCTAssertEqual(plan.voiceLevel ?? 0, -18, accuracy: 0.01)
        // The bed was 10 under the old voice; against the raised voice it is 22 under, which is where it belongs.
        let bed = plan.adjustments.first { $0.clipID == clip("Bed", in: timeline).id }
        XCTAssertEqual(bed?.gain ?? 0, 0, accuracy: 0.01)
        XCTAssertEqual(bed?.duck, -6, "it still learns to duck")
        XCTAssertTrue(plan.changes.contains { $0.stem == .voice && $0.text.contains("up 12 dB") }, "\(plan.changes)")
    }

    func testGameSoundUnderASeparateMicIsTheGameAndDucks() throws {
        var timeline = mix(game: true, music: false, effect: false)
        let plan = MixAssistant.plan(timeline: timeline, levels: [voiceID: -18.0, gameID: -15.0])
        let game = try XCTUnwrap(plan.adjustments.first { $0.clipID == clip("Game", in: timeline).id })
        XCTAssertEqual(game.gain, -13, accuracy: 0.01, "to 10 dB under the voice")
        XCTAssertEqual(game.duck, -9)
        MixAssistant.apply(plan, to: &timeline)
        XCTAssertTrue(clip("Game", in: timeline).audio.duckUnderDialogue)

        // The same recording with no separate mic over it carries the talking: it is the voice, and stays.
        var single = Timeline.empty(name: "Single", canvas: .vertical1080)
        single.tracks[3].clips = [TimelineClip(name: "VOD", content: .media(assetID: gameID), start: 0, sourceIn: 0, sourceDuration: 60, role: .main)]
        let one = MixAssistant.plan(timeline: single, levels: [gameID: -17.0])
        XCTAssertTrue(one.isEmpty)
        XCTAssertEqual(one.voiceLevel ?? 0, -17, accuracy: 0.01)
    }

    func testNothingIsGuessedAndAMixWithNoVoiceIsLeftAlone() {
        // The bed's level isn't known: it is left alone rather than moved blind.
        let timeline = mix(effect: false)
        XCTAssertTrue(MixAssistant.plan(timeline: timeline, levels: [voiceID: -18.0]).isEmpty)
        // Music only: nothing to mix around.
        var bedOnly = Timeline.empty(name: "Bed", canvas: .vertical1080)
        bedOnly.tracks[3].clips = [TimelineClip(name: "Bed", content: .media(assetID: musicID), start: 0, sourceIn: 0, sourceDuration: 60, role: .music)]
        let none = MixAssistant.plan(timeline: bedOnly, levels: [musicID: -6.0])
        XCTAssertTrue(none.isEmpty)
        XCTAssertNil(none.voiceLevel)
        // A muted clip or track isn't part of the mix.
        var muted = mix(effect: false)
        let bedTrack = muted.tracks.firstIndex { $0.clips.contains { $0.name == "Bed" } }!
        muted.tracks[bedTrack].isMuted = true
        XCTAssertTrue(MixAssistant.plan(timeline: muted, levels: [voiceID: -18.0, musicID: -6.0]).isEmpty)
        // A bed nobody can hear comes up a little.
        let faint = MixAssistant.plan(timeline: mix(effect: false), levels: [voiceID: -18.0, musicID: -60.0])
        XCTAssertGreaterThan(faint.adjustments.first { $0.duck != nil }?.gain ?? 0, 0)
    }

    func testLevelsComeFromAnAnalysisOrAWaveform() throws {
        let audio = Fixtures.audio(duration: 60, silences: [TimeRange(start: 10, end: 30)])
        let level = try XCTUnwrap(MixAssistant.level(of: audio))
        XCTAssertEqual(level, -24, accuracy: 2.5, "the talking, not the silence")
        XCTAssertNil(MixAssistant.level(of: Fixtures.audio(duration: 60, silences: [TimeRange(start: 0, end: 60)])))
        let peaks = [Float](repeating: 0.25, count: 200) + [Float](repeating: 0, count: 100)
        XCTAssertEqual(try XCTUnwrap(MixAssistant.level(ofPeaks: peaks)), 20 * log10(0.25) - 3, accuracy: 0.01)
        XCTAssertNil(MixAssistant.level(ofPeaks: []))
    }
}
