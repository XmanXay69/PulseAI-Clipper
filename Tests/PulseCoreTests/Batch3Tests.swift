import XCTest
@testable import PulseCore

/// Roadmap batch 3: game banners (#27), platform specs (#333), stream setup (#441), audio censor (#243),
/// highlight presets (#232).
final class Batch3Tests: XCTestCase {
    // MARK: #27 Game banners

    func testBannerPhrasesMapToEventsLongestFirst() {
        XCTAssertEqual(HUDCues.event(forText: "DOUBLE KILL", at: 10)?.kind, .multiKill)
        XCTAssertEqual(HUDCues.event(forText: "#1 Victory Royale", at: 10)?.kind, .win)
        XCTAssertEqual(HUDCues.event(forText: "you were eliminated", at: 10)?.kind, .death, "the player died")
        XCTAssertEqual(HUDCues.event(forText: "ELIMINATED xXSniperXx", at: 10)?.kind, .kill, "the player got a kill")
        XCTAssertEqual(HUDCues.event(forText: "BOSS DEFEATED", at: 10)?.kind, .objective, "not a loss")
        XCTAssertEqual(HUDCues.event(forText: "Achievement unlocked: Sharpshooter", at: 10)?.kind, .achievement)
        XCTAssertNil(HUDCues.event(forText: "WINDOW", at: 10), "word boundaries")
        XCTAssertNil(HUDCues.event(forText: "chat: lol that kill was insane bro what a play seriously", at: 10), "long lines are chat, not banners")
        XCTAssertNil(HUDCues.event(forText: "", at: 10))
        XCTAssertEqual(HUDCues.event(forText: "1v3 CLUTCH", at: 10)?.kind, .clutch)
    }

    func testTheSameBannerSeenOnSeveralFramesIsOneEvent() {
        let frames = [0, 2, 4, 6].map { HUDEvent(time: Seconds(100 + $0), kind: .win, text: "VICTORY") }
            + [HUDEvent(time: 130, kind: .win, text: "VICTORY"), HUDEvent(time: 102, kind: .kill, text: "KILL")]
        let events = HUDCues.coalesce(frames, window: 4)
        XCTAssertEqual(events.map { "\($0.kind.rawValue)@\(Int($0.time))" }, ["win@100", "kill@102", "win@130"])
    }

    func testBannerSignalPeaksAtTheBannerAndLiftsExcitement() {
        let events = [HUDEvent(time: 50, kind: .win, text: "VICTORY")]
        let signal = HUDCues.signal(events: events, duration: 100, step: 0.5)
        XCTAssertEqual(signal.count, 200)
        let peakIndex = signal.indices.max { signal[$0] < signal[$1] }!
        XCTAssertEqual(Double(peakIndex) * 0.5, 50, accuracy: 0.6)
        XCTAssertGreaterThan(signal[peakIndex], 0.9)
        XCTAssertEqual(signal[0], 0)
        XCTAssertGreaterThan(signal[96], 0, "rises before the banner (the play came first)")
        XCTAssertEqual(signal[120], 0, "faded 10 s later")

        let duration: Seconds = 300
        let audio = Fixtures.audio(duration: duration)
        let plain = EngagementModel.compute(duration: duration, audio: audio, transcript: nil, visual: nil, gameplay: true)
        let withBanner = EngagementModel.compute(duration: duration, audio: audio, transcript: nil, visual: nil,
                                                 hud: [HUDEvent(time: 150, kind: .multiKill, text: "TRIPLE KILL")], gameplay: true)
        let i = plain.index(at: 150)
        XCTAssertGreaterThan(withBanner.excitement[i], plain.excitement[i] + 0.2)
        XCTAssertEqual(withBanner.hud.count, plain.count)
        XCTAssertTrue(plain.hud.isEmpty)
    }

    func testClipsAroundABannerAreTaggedByIt() {
        let duration: Seconds = 600
        var analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: duration, audio: Fixtures.audio(duration: duration, spikes: [200]),
                                     transcript: Fixtures.transcript(duration: duration), profile: .gameplay)
        analysis.hudEvents = [HUDEvent(time: 201, kind: .death, text: "YOU DIED")]
        let generator = ClipGenerator(input: ClipGenerationInput(analysis: analysis), settings: ClipGenerationSettings())
        let scores = ClipScores(hook: 0.5, emotion: 0.5, story: 0.3, entertainment: 0.5, audio: 0.5, visual: 0.3, reaction: 0.3, context: 0.3, ending: 0.3)
        let tags = generator.inferTags(range: TimeRange(start: 190, end: 215), payoff: 200, scores: scores)
        XCTAssertTrue(tags.contains(.fail), "\(tags)")
        let elsewhere = generator.inferTags(range: TimeRange(start: 400, end: 425), payoff: 410, scores: scores)
        XCTAssertFalse(elsewhere.contains(.fail), "\(elsewhere)")
    }

    func testAnalysisSpeedProfileKeepsOldSavesAndEstimatesTheBannerStage() throws {
        let old = Data(#"{"audio":0.5,"transcription":3,"video":1,"samples":4}"#.utf8)
        let profile = try JSONDecoder().decode(AnalysisSpeedProfile.self, from: old)
        XCTAssertEqual(profile.samples, 4)
        XCTAssertEqual(profile.hud, AnalysisSpeedProfile().hud)
        let estimate = profile.estimate(duration: 3600, hasAudio: true, transcribe: true, hasVideo: true, readHUD: true)
        XCTAssertNotNil(estimate.stages[.hud])
        XCTAssertNil(profile.estimate(duration: 3600, hasAudio: true, transcribe: true, hasVideo: true).stages[.hud])
        var learned = profile
        learned.learn(.hud, mediaDuration: 600, wallSeconds: 30)
        XCTAssertEqual(learned.hud, profile.hud + (3 - profile.hud) * 0.35, accuracy: 1e-9)
    }

    func testOldAnalysesLoadWithoutBanners() throws {
        let analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: 10)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(analysis)) as! [String: Any]
        json.removeValue(forKey: "hudEvents")
        let loaded = try JSONDecoder().decode(MediaAnalysis.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(loaded.hudEvents)
    }

    // MARK: #333 Platform specs

    func testPlatformNotesFlagLengthAndBitrate() {
        var shorts = ExportSettings(preset: .shorts, outputDirectory: "/tmp", quality: .standard)
        let tooLong = shorts.platformNotes(timelineDuration: 200, timelineFrameRate: 30)
        XCTAssertEqual(tooLong.count, 1)
        XCTAssertTrue(tooLong[0].contains("3:00") && tooLong[0].contains("3:20"), tooLong[0])
        XCTAssertTrue(shorts.platformNotes(timelineDuration: 59, timelineFrameRate: 30).isEmpty)

        shorts.quality = .draft   // 6 Mbps
        let soft = shorts.platformNotes(timelineDuration: 59, timelineFrameRate: 60)
        XCTAssertEqual(soft.count, 1)
        XCTAssertTrue(soft[0].contains("6 Mbps") && soft[0].contains("60 fps"), soft[0])

        var youtube = ExportSettings(preset: .youtube, outputDirectory: "/tmp", quality: .standard)
        XCTAssertTrue(youtube.platformNotes(timelineDuration: 3600, timelineFrameRate: 30).isEmpty, "no length limit")
        youtube.videoBitrate = 60_000_000
        XCTAssertTrue(youtube.platformNotes(timelineDuration: 60, timelineFrameRate: 30).first?.contains("bigger for nothing") ?? false)
        XCTAssertNotNil(ExportPreset.tiktok.platformGuidance)
        XCTAssertNil(ExportSettings(preset: .master).platformNotes(timelineDuration: 60, timelineFrameRate: 30).first)
    }

    // MARK: #441 Stream setup

    func testStreamSetupTurnsAnswersIntoSettingsOnce() {
        var settings = AppSettings()
        var setup = StreamSetup()
        setup.content = .battleRoyale
        setup.facecam = true
        setup.pace = .hype
        setup.shortsTarget = .shorts
        let changes = setup.apply(to: &settings)
        XCTAssertFalse(changes.isEmpty)
        XCTAssertTrue(settings.ai.editExtras.facecamPunchIns)
        XCTAssertTrue(settings.ai.editExtras.instantReplays)
        XCTAssertTrue(settings.ai.editExtras.beatSync)
        XCTAssertFalse(settings.ai.editExtras.speakerAware)
        XCTAssertTrue(settings.ai.hudCues)
        XCTAssertTrue(settings.ai.aiSoundEffects)
        XCTAssertEqual(settings.ai.defaultClipLength, .medium30)
        XCTAssertEqual(settings.ai.captionPresetName, "Gaming")
        XCTAssertEqual(settings.defaultExportPresetID, ExportPreset.shorts.id)
        XCTAssertEqual(settings.safeAreaPlatform, .youtubeShorts)
        XCTAssertEqual(settings.ai.clipAggressiveness, 0.65)
        XCTAssertTrue(settings.hasCompletedOnboarding)
        XCTAssertEqual(settings.streamSetup, setup)
        XCTAssertTrue(setup.apply(to: &settings).isEmpty, "applying again changes nothing")
        XCTAssertTrue(setup.changes(to: settings).isEmpty)

        var podcast = StreamSetup()
        podcast.content = .podcast
        podcast.facecam = false
        podcast.pace = .calm
        let podcastChanges = podcast.apply(to: &settings)
        XCTAssertFalse(podcastChanges.isEmpty)
        XCTAssertTrue(settings.ai.detectSpeakers)
        XCTAssertEqual(settings.ai.speakerCount, 2)
        XCTAssertTrue(settings.ai.fillerRemoval)
        XCTAssertFalse(settings.ai.hudCues)
        XCTAssertFalse(settings.ai.editExtras.instantReplays)
        XCTAssertTrue(settings.ai.editExtras.speakerAware)
        XCTAssertTrue(settings.ai.editExtras.brollClips)
        XCTAssertEqual(settings.ai.captionPresetName, "Podcast")
        XCTAssertEqual(settings.ai.silencePreset, .conservative)
        XCTAssertEqual(settings.ai.defaultClipLength, .long60)
        XCTAssertTrue(podcastChanges.contains { $0.hasPrefix("Speakers: 2") }, "\(podcastChanges)")
    }

    func testStreamSetupRoundTripsAndKeepsOldKeys() throws {
        var setup = StreamSetup()
        setup.content = .irl
        setup.captionPreset = "Bold"
        let data = try JSONEncoder().encode(setup)
        XCTAssertEqual(try JSONDecoder().decode(StreamSetup.self, from: data), setup)
        let partial = try JSONDecoder().decode(StreamSetup.self, from: Data(#"{"content":"moba"}"#.utf8))
        XCTAssertEqual(partial.content, .moba)
        XCTAssertEqual(partial.platform, .twitch)
        XCTAssertEqual(setup.effectiveCaptionPreset, "Bold")
        XCTAssertEqual(StreamSetup().effectiveCaptionPreset, "Gaming")
        var unknown = StreamSetup()
        unknown.captionPreset = "Nope"
        XCTAssertEqual(unknown.effectiveCaptionPreset, "Gaming", "unknown preset names fall back")
        // Settings carry the setup.
        var settings = AppSettings()
        setup.apply(to: &settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.streamSetup, setup)
    }

    // MARK: #243 Audio censor

    func testCensorRangesCoverTheSwearWordsAndMergeNeighbours() {
        let words = [TranscriptWord(text: "what", start: 10, end: 10.3), TranscriptWord(text: "the", start: 10.3, end: 10.4),
                     TranscriptWord(text: "Fuck", start: 10.4, end: 10.7), TranscriptWord(text: "fucking", start: 10.72, end: 11),
                     TranscriptWord(text: "darn", start: 20, end: 20.3), TranscriptWord(text: "shit", start: 40, end: 40.3)]
        let ranges = AudioCensor.ranges(words: words, in: TimeRange(start: 0, end: 30), extra: ["darn"])
        XCTAssertEqual(ranges.count, 2, "\(ranges)")
        XCTAssertEqual(ranges[0].start, 10.36, accuracy: 1e-9)
        XCTAssertEqual(ranges[0].end, 11.04, accuracy: 1e-9)
        XCTAssertEqual(ranges[1].start, 19.96, accuracy: 1e-9)
        XCTAssertTrue(AudioCensor.ranges(words: words, in: TimeRange(start: 0, end: 30)).count == 1, "'darn' only with the extra list")
    }

    func testCensorAppliesToTheAssetsClipsAndChangesTheRender() {
        var timeline = Fixtures.simpleTimeline(clipDuration: 30)
        let assetID = timeline.tracks[0].clips[0].content.assetID!
        // The fixture's clips start at source time 100; the linked video and audio pieces both carry the ranges.
        let words = [TranscriptWord(text: "shit", start: 105, end: 105.3), TranscriptWord(text: "fuck", start: 112, end: 112.4)]
        let count = AudioCensor.apply(.bleep, to: &timeline, words: words, assetID: assetID)
        XCTAssertEqual(count, 4)
        let clip = timeline.tracks[0].clips[0]
        XCTAssertEqual(timeline.tracks[3].clips[0].audio.censorRanges, clip.audio.censorRanges)
        XCTAssertEqual(clip.audio.censor, .bleep)
        XCTAssertEqual(clip.audio.censorRanges.count, 2)
        XCTAssertTrue(clip.audio.needsProcessing)
        XCTAssertTrue(clip.audio.enhanceFingerprint.contains("xbleep"))
        var muted = clip.audio
        muted.censor = .mute
        XCTAssertNotEqual(muted.enhanceFingerprint, clip.audio.enhanceFingerprint)
        AudioCensor.apply(.off, to: &timeline, words: words, assetID: assetID)
        XCTAssertFalse(timeline.tracks[0].clips[0].audio.needsProcessing)
        XCTAssertEqual(timeline.tracks[0].clips[0].audio.censor, .off)
        // Clips of other assets are left alone.
        var other = Fixtures.simpleTimeline(clipDuration: 30)
        XCTAssertEqual(AudioCensor.apply(.mute, to: &other, words: words, assetID: UUID()), 0)
    }

    func testMuteAndBleepReplaceOnlyTheRange() {
        let rate = 48_000.0
        var channels = [[Float]](repeating: [Float](repeating: 0.5, count: Int(rate)), count: 2)
        AudioCensor.process(&channels, sampleRate: rate, ranges: [TimeRange(start: 0.2, end: 0.4)], mode: .mute)
        XCTAssertEqual(channels[0][Int(0.1 * rate)], 0.5)
        XCTAssertEqual(channels[1][Int(0.3 * rate)], 0, accuracy: 1e-6)
        XCTAssertEqual(channels[0][Int(0.2 * rate) + 120], 0.25, accuracy: 0.02, "5 ms ramp in")
        XCTAssertEqual(channels[0][Int(0.5 * rate)], 0.5)

        var bleeped = [[Float](repeating: 0.5, count: Int(rate))]
        AudioCensor.process(&bleeped, sampleRate: rate, ranges: [TimeRange(start: 0.2, end: 0.4)], mode: .bleep)
        let inside = bleeped[0][Int(0.25 * rate)..<Int(0.35 * rate)]
        let peak = inside.map(abs).max()!
        XCTAssertEqual(Double(peak), pow(10, -14.0 / 20), accuracy: 0.01)
        XCTAssertLessThan(abs(inside.reduce(0, +) / Float(inside.count)), 0.02, "a tone, not the original level")
        XCTAssertEqual(bleeped[0][Int(0.6 * rate)], 0.5)

        // Through the enhance chain, source-time ranges are mapped by the clip's source start.
        var settings = AudioSettings()
        settings.censor = .mute
        settings.censorRanges = [TimeRange(start: 100.2, end: 100.4)]
        var chain = [[Float](repeating: 0.5, count: Int(rate))]
        AudioEnhanceChain.process(&chain, sampleRate: rate, settings: settings, sourceStart: 100)
        XCTAssertEqual(chain[0][Int(0.3 * rate)], 0, accuracy: 1e-6)
        XCTAssertEqual(chain[0][Int(0.1 * rate)], 0.5)
        AudioCensor.process(&chain, sampleRate: rate, ranges: [TimeRange(start: 5, end: 6)], mode: .mute)
        XCTAssertEqual(chain[0][Int(0.1 * rate)], 0.5, "ranges outside the buffer are ignored")
    }

    func testOldClipsDecodeWithoutCensorFields() throws {
        let data = try JSONEncoder().encode(AudioSettings())
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "censor")
        json.removeValue(forKey: "censorRanges")
        let decoded = try JSONDecoder().decode(AudioSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.censor, .off)
        XCTAssertTrue(decoded.censorRanges.isEmpty)
    }

    // MARK: #232 Highlight presets

    func testHighlightPresetsApplyAndMatch() {
        XCTAssertEqual(HighlightPreset.all.count, 6)
        XCTAssertEqual(Set(HighlightPreset.all.map(\.name)).count, 6)
        var style = CaptionStyle.tiktok
        HighlightPreset.fill.apply(to: &style)
        XCTAssertEqual(style.highlightMode, .box)
        XCTAssertEqual(style.highlightColor, .black)
        XCTAssertEqual(style.highlightBoxColor, .yellow)
        XCTAssertTrue(HighlightPreset.fill.matches(style))
        XCTAssertFalse(HighlightPreset.boxed.matches(style))
        HighlightPreset.subtle.apply(to: &style)
        XCTAssertEqual(style.highlightMode, .scale)
        XCTAssertTrue(HighlightPreset.subtle.matches(style))
        XCTAssertEqual(HighlightPreset.all.filter { $0.matches(style) }.count, 1)
    }
}
