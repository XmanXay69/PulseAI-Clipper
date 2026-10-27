import XCTest
@testable import PulseCore

final class Batch44Tests: XCTestCase {
    // MARK: #34 — per-game profiles

    func testDetectsTheGameFromNamesThenFromSpeech() {
        XCTAssertEqual(GameProfile.detect(in: ["VALORANT ranked grind 2024-03-01.mp4"])?.id, "shooter")
        XCTAssertEqual(GameProfile.detect(in: ["Cozy Sunday", "minecraft_hardcore_day_12"])?.id, "sandbox")
        XCTAssertEqual(GameProfile.detect(in: ["Just Chatting - Q&A"])?.id, "justChatting")
        XCTAssertNil(GameProfile.detect(in: ["my vacation vlog"]))
        // "girl" is not "irl": whole words only.
        XCTAssertNil(GameProfile.detect(in: ["girl talk"]))
        // A specific title beats the generic chatting label.
        XCTAssertEqual(GameProfile.detect(in: ["Just Chatting then Fortnite"])?.id, "shooter")
        // Named once in passing is not the game; twice is.
        XCTAssertNil(GameProfile.detect(in: ["stream"], spoken: ["we", "could", "play", "phasmophobia", "later"]))
        XCTAssertEqual(GameProfile.detect(in: ["stream"], spoken: ["phasmophobia", "is", "so", "scary", "phasmophobia", "ghost"])?.id, "horror")
        XCTAssertEqual(GameProfile.detect(in: ["stream"], spoken: ["league", "of", "legends", "ranked", "league", "of", "legends"])?.id, "strategy")
    }

    func testBuiltInProfilesAreDistinctAndFindable() {
        let ids = GameProfile.builtIn.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for profile in GameProfile.builtIn {
            XCTAssertEqual(GameProfile.profile(id: profile.id), profile)
            XCTAssertFalse(profile.keywords.isEmpty)
            XCTAssertFalse(profile.summary.isEmpty)
        }
        XCTAssertNil(GameProfile.profile(id: "nope"))
        XCTAssertTrue(GameProfile.Weights.neutral.isNeutral)
        XCTAssertFalse(GameProfile.shooter.weights.isNeutral)
    }

    func testWeightsDecodeWithMissingKeysAndRoundTrip() throws {
        let partial = try JSONDecoder().decode(GameProfile.Weights.self, from: Data(#"{"motion":1.5}"#.utf8))
        XCTAssertEqual(partial.motion, 1.5)
        XCTAssertEqual(partial.laughter, 1)
        let back = try JSONDecoder().decode(GameProfile.self, from: JSONEncoder().encode(GameProfile.horror))
        XCTAssertEqual(back, GameProfile.horror)
    }

    /// A flat voice with one burst of on-screen motion: the shooter profile rates the burst far above the
    /// chatting profile, and the re-normalized total keeps both curves in the same range.
    func testGameWeightsShiftWhatScoresHighest() {
        let duration: Seconds = 60
        let hop = 0.1
        let n = Int(duration / hop)
        let rms = [Float](repeating: -24, count: n)
        let audio = AudioFeatureSeries(hop: hop, rmsDB: rms, peakDB: rms.map { $0 + 6 }, zeroCrossingRate: [Float](repeating: 0.1, count: n),
                                       spectralFlux: [Float](repeating: 0.1, count: n))
        var motion = [Float](repeating: 0.02, count: n)
        for i in Int(20 / hop)..<Int(23 / hop) { motion[i] = 0.9 }
        let visual = VisualFeatureSeries(hop: hop, motion: motion, brightness: [Float](repeating: 0.5, count: n), sceneCuts: [], faces: [])
        var words: [TranscriptWord] = []
        for i in 0..<110 { words.append(TranscriptWord(text: "word", start: Double(i) * 0.5, end: Double(i) * 0.5 + 0.4)) }
        for i in 0..<4 { words.append(TranscriptWord(text: "haha", start: 40 + Double(i) * 0.4, end: 40.3 + Double(i) * 0.4)) }
        let transcript = Transcript(words: words.sorted { $0.start < $1.start }, source: .demo)

        func signals(_ profile: GameProfile?) -> EngagementSignals {
            EngagementModel.compute(duration: duration, audio: audio, transcript: transcript, visual: visual, gameplay: true, weights: profile?.weights ?? .neutral)
        }
        let neutral = signals(nil), shooter = signals(.shooter), chatting = signals(.justChatting)
        let burst = TimeRange(start: 20, end: 23), laugh = TimeRange(start: 40, end: 42)
        XCTAssertGreaterThan(shooter.max(shooter.excitement, in: burst), chatting.max(chatting.excitement, in: burst) * 1.5)
        XCTAssertGreaterThan(chatting.max(chatting.excitement, in: laugh), shooter.max(shooter.excitement, in: laugh))
        // Chatting: the laugh is the moment. Shooter: the fight is.
        XCTAssertGreaterThan(chatting.max(chatting.excitement, in: laugh), chatting.max(chatting.excitement, in: burst))
        XCTAssertGreaterThan(shooter.max(shooter.excitement, in: burst), shooter.max(shooter.excitement, in: laugh))
        for s in [neutral, shooter, chatting] {
            XCTAssertLessThanOrEqual(s.excitement.max() ?? 0, 1.2)
            XCTAssertGreaterThanOrEqual(s.excitement.min() ?? 0, 0)
        }
        // The neutral curve is unchanged by a neutral profile.
        let explicitNeutral = EngagementModel.compute(duration: duration, audio: audio, transcript: transcript, visual: visual, gameplay: true)
        XCTAssertEqual(neutral.excitement, explicitNeutral.excitement)
    }

    func testClipInputCarriesTheGameIntoTheGenerator() {
        var analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: 600, audio: Fixtures.audio(duration: 600, spikes: [100, 300]))
        analysis.profile = .gameplay
        let plain = ClipGenerator(input: ClipGenerationInput(analysis: analysis), settings: ClipGenerationSettings())
        let shooter = ClipGenerator(input: ClipGenerationInput(analysis: analysis, game: .shooter), settings: ClipGenerationSettings())
        XCTAssertNil(plain.input.game)
        XCTAssertEqual(shooter.input.game?.id, "shooter")
        XCTAssertEqual(plain.signals.count, shooter.signals.count)
    }

    func testProjectOverridesPinTheGame() throws {
        var overrides = ProjectOverrides()
        XCTAssertTrue(overrides.isEmpty)
        overrides.gameProfileID = "horror"
        XCTAssertFalse(overrides.isEmpty)
        XCTAssertEqual(overrides.count, 1)
        let back = try JSONDecoder().decode(ProjectOverrides.self, from: JSONEncoder().encode(overrides))
        XCTAssertEqual(back.gameProfileID, "horror")
        let old = try JSONDecoder().decode(ProjectOverrides.self, from: Data(#"{"loudnessTarget":-14}"#.utf8))
        XCTAssertNil(old.gameProfileID)
        XCTAssertEqual(old.count, 1)
    }

    // MARK: #9 — audio-only recordings get a waveform picture

    func testAudiogramBarsWindowAroundNow() {
        // 10 s of peaks at 50/s: silent except 4–5 s at full scale.
        var peaks = [Float](repeating: 0, count: 500)
        for i in 200..<250 { peaks[i] = 1 }
        let count = 64
        let bars = AudiogramLayout.bars(peaks: peaks, perSecond: 50, at: 4.5, count: count, span: 4)
        XCTAssertEqual(bars.count, count)
        let centre = AudiogramLayout.centreIndex(count: count)
        XCTAssertEqual(bars[centre], 1, "the loud second sits under the centre bar")
        XCTAssertEqual(bars[0], 0, "2 s before is silent")
        XCTAssertEqual(bars[count - 1], 0, "2 s after is silent")
        // Before the file starts and after it ends the bars are empty.
        XCTAssertEqual(AudiogramLayout.bars(peaks: peaks, perSecond: 50, at: -10, count: 8, span: 4), [Float](repeating: 0, count: 8))
        XCTAssertEqual(AudiogramLayout.bars(peaks: peaks, perSecond: 50, at: 30, count: 8, span: 4), [Float](repeating: 0, count: 8))
        XCTAssertTrue(AudiogramLayout.bars(peaks: peaks, perSecond: 0, at: 1).isEmpty)
        // Heights are clamped to 0…1 and the ease lifts quiet speech.
        XCTAssertEqual(AudiogramLayout.bars(peaks: [3, -1], perSecond: 1, at: 1, count: 2, span: 2), [1, 0])
        XCTAssertEqual(AudiogramLayout.eased(0.25), 0.5, accuracy: 0.001)
        XCTAssertEqual(AudiogramLayout.eased(0), 0)
        XCTAssertEqual(AudiogramLayout.eased(1), 1)
    }

    func testAudiogramPlacerMirrorsAudioCutsOntoTheVideoTrack() {
        let audioID = UUID(), visualID = UUID(), otherID = UUID()
        var timeline = Timeline.empty(name: "Podcast", canvas: .landscape1080)
        let group = UUID()
        var a1 = TimelineClip(name: "Hook", content: .media(assetID: audioID), start: 0, sourceIn: 300, sourceDuration: 20, linkGroup: group, role: .microphone)
        a1.speed = 1.25
        let a2 = TimelineClip(name: "Chapter 1", content: .media(assetID: audioID), start: 20, sourceIn: 0, sourceDuration: 60, role: .microphone)
        let a3 = TimelineClip(name: "Chapter 2", content: .media(assetID: audioID), start: 80, sourceIn: 100, sourceDuration: 60, role: .microphone)
        let other = TimelineClip(name: "Sting", content: .media(assetID: otherID), start: 20, sourceDuration: 1, role: .soundEffect)
        timeline.tracks[3].clips = [a1, a2, a3]
        timeline.tracks[4].clips = [other]
        // Something already fills 80–140 on V1: that stretch keeps its picture.
        timeline.tracks[0].clips = [TimelineClip(name: "Card", content: .media(assetID: otherID), start: 80, sourceDuration: 60)]

        let placed = AudiogramPlacer.place(&timeline, audioAssetID: audioID, visualAssetID: visualID)
        XCTAssertEqual(placed, 2)
        let video = timeline.tracks[0].clips
        XCTAssertEqual(video.count, 3)
        XCTAssertEqual(video.map(\.start), [0, 20, 80], "sorted by start")
        let hook = video[0]
        XCTAssertEqual(hook.content, .media(assetID: visualID))
        XCTAssertEqual(hook.sourceIn, 300)
        XCTAssertEqual(hook.sourceDuration, 20)
        XCTAssertEqual(hook.speed, 1.25)
        XCTAssertEqual(hook.linkGroup, group, "linked to its audio")
        XCTAssertEqual(hook.role, .main)
        XCTAssertTrue(hook.aiGenerated)
        XCTAssertNotNil(video[1].linkGroup, "an unlinked audio clip gets a fresh link group")
        XCTAssertEqual(video[2].name, "Card")
        // Running it again places nothing: everything is covered.
        XCTAssertEqual(AudiogramPlacer.place(&timeline, audioAssetID: audioID, visualAssetID: visualID), 0)
        XCTAssertEqual(AudiogramPlacer.tag(for: audioID), "audiogram:\(audioID.uuidString)")
    }

    func testAudiogramPlacerNeedsAVideoTrack() {
        var timeline = Timeline(name: "Audio only", canvas: .landscape1080, tracks: [Track(kind: .audio, name: "A1")])
        timeline.tracks[0].clips = [TimelineClip(name: "A", content: .media(assetID: Fixtures.assetID), start: 0, sourceDuration: 10)]
        XCTAssertEqual(AudiogramPlacer.place(&timeline, audioAssetID: Fixtures.assetID, visualAssetID: UUID()), 0)
    }
}
