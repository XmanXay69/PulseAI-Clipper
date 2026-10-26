import XCTest
@testable import PulseCore

final class Batch24Tests: XCTestCase {
    // MARK: #294 loop points

    private func envelope(seconds: Double, perSecond: Double, bar: Double = 2, _ pattern: (Double) -> Float) -> [Float] {
        (0..<Int(seconds * perSecond)).map { i in
            let t = Double(i) / perSecond
            return pattern(t.truncatingRemainder(dividingBy: bar))
        }
    }

    func testLoopFindsRepeatingBar() {
        // A 2-second bar repeated for 40 s: any seam a whole number of bars apart matches.
        let peaks = envelope(seconds: 40, perSecond: 50) { t in Float(0.3 + 0.5 * abs(sin(t * .pi))) }
        let loop = LoopPoints.find(peaks: peaks, perSecond: 50, minLength: 8)
        XCTAssertNotNil(loop)
        guard let loop else { return }
        XCTAssertGreaterThan(loop.score, 0.9)
        XCTAssertGreaterThanOrEqual(loop.length, 8)
        let bars = loop.length / 2
        XCTAssertEqual(bars, bars.rounded(), accuracy: 0.15, "the seam lands a whole number of bars apart")
    }

    func testLoopPrefersLongerLoopAmongEqualSeams() {
        let peaks = envelope(seconds: 60, perSecond: 10) { t in Float(0.4 + 0.4 * abs(sin(t * .pi))) }
        let loop = LoopPoints.find(peaks: peaks, perSecond: 10, minLength: 8)!
        XCTAssertGreaterThan(loop.length, 30, "with every bar identical the longest clean loop wins")
    }

    func testLoopRejectsSilenceAndShortTracks() {
        let silent = [Float](repeating: 0.01, count: 50 * 40)
        XCTAssertNil(LoopPoints.find(peaks: silent, perSecond: 50))
        let short = [Float](repeating: 0.5, count: 50 * 5)
        XCTAssertNil(LoopPoints.find(peaks: short, perSecond: 50, minLength: 8))
        // Noise with nothing in common anywhere scores too low to loop.
        var seed: UInt64 = 7
        let noise: [Float] = (0..<2000).map { _ in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float((seed >> 33) % 1000) / 1000
        }
        if let loop = LoopPoints.find(peaks: noise, perSecond: 50) { XCTAssertGreaterThanOrEqual(loop.score, 0.6) }
    }

    func testLoopSegmentsTileToDuration() {
        let loop = LoopPoints.Loop(start: 4, end: 20, score: 0.95)
        let segments = LoopPoints.segments(loop: loop, trackDuration: 30, duration: 50)
        XCTAssertEqual(segments.map(\.duration).reduce(0, +), 50, accuracy: 0.001)
        XCTAssertEqual(segments.first?.start, 0)
        XCTAssertEqual(segments.first?.duration, 20)
        XCTAssertEqual(segments[1].start, 4)
        XCTAssertEqual(segments[1].duration, 16)
        XCTAssertEqual(segments.last?.duration ?? 0, 14, accuracy: 0.001)
        // No loop: the track restarts from zero.
        let plain = LoopPoints.segments(loop: nil, trackDuration: 30, duration: 45)
        XCTAssertEqual(plain.map(\.start), [0, 0])
        XCTAssertEqual(plain.map(\.duration), [30, 15])
        XCTAssertTrue(LoopPoints.segments(loop: nil, trackDuration: 0, duration: 10).isEmpty)
    }

    func testAddMusicFollowsLoopSeam() {
        var timeline = Timeline(name: "Edit", canvas: .landscape1080,
                                tracks: [Track(kind: .video, name: "V1"), Track(kind: .audio, name: "A1 Dialogue"), Track(kind: .audio, name: "A2 Music")])
        timeline.tracks[0].clips = [TimelineClip(name: "vod", content: .solid(.black), start: 0, sourceDuration: 100)]
        let bed = MediaAsset(name: "bed", path: "/tmp/bed.mp3", kind: .audio, role: .music,
                             metadata: MediaMetadata(duration: 30, hasVideo: false, hasAudio: true, audioTrackCount: 1))
        let loop = LoopPoints.Loop(start: 4, end: 20, score: 0.95)
        LongFormEditor.addMusic([bed], chapters: [TimeRange(start: 0, end: 100)], to: &timeline, loops: [bed.id: loop])
        let clips = timeline.tracks[2].clips.sorted { $0.start < $1.start }
        XCTAssertGreaterThan(clips.count, 3)
        XCTAssertEqual(clips[0].sourceIn, 0)
        XCTAssertEqual(clips[0].sourceDuration, 20, accuracy: 0.001)
        for clip in clips.dropFirst() { XCTAssertEqual(clip.sourceIn, 4, accuracy: 0.001, "every repeat starts at the loop point") }
        XCTAssertEqual(clips.map(\.sourceDuration).reduce(0, +), 100, accuracy: 0.6)
        // Pieces inside the loop butt together without fades; the chapter still fades in and out.
        XCTAssertEqual(clips[1].audio.fadeIn, 0)
        XCTAssertEqual(clips[0].audio.fadeIn, 2.5)
        XCTAssertEqual(clips.last?.audio.fadeOut, 3)
        // No loop: the old behaviour, every piece from the top of the track.
        var plain = timeline
        LongFormEditor.addMusic([bed], chapters: [TimeRange(start: 0, end: 100)], to: &plain)
        XCTAssertTrue(plain.tracks[2].clips.allSatisfy { $0.sourceIn == 0 })
    }

    // MARK: #169 fade shapes, #170 pitch

    func testFadeShapes() {
        XCTAssertEqual(FadeShape.linear.apply(0.5), 0.5)
        XCTAssertEqual(FadeShape.equalPower.apply(0.5), sin(.pi / 4), accuracy: 1e-9)
        XCTAssertEqual(FadeShape.smooth.apply(0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(FadeShape.smooth.apply(0.25), 0.15625, accuracy: 1e-9)
        for shape in FadeShape.allCases {
            XCTAssertEqual(shape.apply(0), 0, accuracy: 1e-9)
            XCTAssertEqual(shape.apply(1), 1, accuracy: 1e-9)
            XCTAssertEqual(shape.apply(2), 1, accuracy: 1e-9, "clamped")
        }
        // Equal power: the two halves of a crossfade sum to constant power at the middle.
        let a = FadeShape.equalPower.apply(0.5), b = FadeShape.equalPower.apply(0.5)
        XCTAssertEqual(a * a + b * b, 1, accuracy: 1e-9)
    }

    func testGainUsesFadeShape() {
        var audio = AudioSettings()
        audio.fadeIn = 2
        audio.fadeShape = .equalPower
        XCTAssertEqual(audio.gain(at: 1, clipDuration: 10), sin(.pi / 4), accuracy: 1e-9)
        audio.fadeShape = .linear
        XCTAssertEqual(audio.gain(at: 1, clipDuration: 10), 0.5, accuracy: 1e-9)
        XCTAssertTrue(audio.preservePitch, "pitch is kept unless the editor turns it off")
    }

    func testAudioSettingsDecodeOldProjects() throws {
        let json = #"{"gainDB":0,"fadeIn":2}"#
        let decoded = try JSONDecoder().decode(AudioSettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.fadeShape, .linear)
        XCTAssertTrue(decoded.preservePitch)
        XCTAssertEqual(decoded.fadeIn, 2)
        XCTAssertEqual(decoded.gain(at: 1, clipDuration: 10), 0.5, accuracy: 1e-9)
        let color = try JSONDecoder().decode(ColorAdjustments.self, from: Data("{}".utf8))
        XCTAssertEqual(color.grain, 0)
        XCTAssertEqual(color.grainSize, 1)
        XCTAssertFalse(color.protectSkin)
        XCTAssertTrue(color.isIdentity)
    }

    // MARK: #315 grain counts as a grade

    func testGrainIsAnAdjustment() {
        var c = ColorAdjustments()
        XCTAssertTrue(c.isIdentity)
        c.grain = 0.3
        XCTAssertTrue(c.hasAdjustments)
        XCTAssertFalse(c.isIdentity)
        c.bypass = true
        XCTAssertTrue(c.isIdentity)
    }

    // MARK: #347 audio quality

    func testAudioQualityNearest() {
        XCTAssertEqual(AudioQuality.nearest(192_000), .high)
        XCTAssertEqual(AudioQuality.nearest(160_000), .standard)
        XCTAssertEqual(AudioQuality.nearest(1_000_000), .maximum)
        XCTAssertEqual(AudioQuality.nearest(10), .voice)
        XCTAssertEqual(AudioQuality.allCases.map(\.bitrate), AudioQuality.allCases.map(\.bitrate).sorted())
        for q in AudioQuality.allCases { XCTAssertFalse(q.detail.isEmpty) }
    }

    // MARK: #187 playback quality

    func testPlaybackQualityRenderSizes() {
        XCTAssertEqual(PlaybackQuality.half.renderSize(width: 1080, height: 1920).width, 540)
        XCTAssertEqual(PlaybackQuality.quarter.renderSize(width: 1080, height: 1920).height, 480)
        XCTAssertEqual(PlaybackQuality.quarter.renderSize(width: 1080, height: 1920).width, 270)
        XCTAssertEqual(PlaybackQuality.full.renderSize(width: 1080, height: 1920).width, 1080)
        XCTAssertEqual(PlaybackQuality.full.lower, .half)
        XCTAssertNil(PlaybackQuality.quarter.lower)
        let settings = try! JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.playbackQuality, .full)
        XCTAssertTrue(settings.autoPlaybackQuality)
        XCTAssertEqual(settings.thumbnailCacheMB, 200)
        XCTAssertEqual(settings.importPreset, .auto)
        XCTAssertFalse(settings.scrubTick)
    }

    // MARK: #25 import presets

    private func plan(_ names: [String]) -> ImportPlan {
        let items = names.map { name -> ImportPlan.Item in
            let url = URL(fileURLWithPath: "/tmp/\(name)")
            let kind: MediaKind = ["mp4", "mov", "mkv"].contains(url.pathExtension) ? .video : ["wav", "mp3", "m4a"].contains(url.pathExtension) ? .audio : .image
            return ImportPlan.Item(url: url, kind: kind, role: MediaTypes.suggestedRole(forFilename: name, kind: kind))
        }
        return ImportPlan(items: items, transcripts: [], rejected: [], duplicates: [])
    }

    func testImportPresets() {
        let obs = plan(["2026-10-01 12-00-00.mkv", "cam.mov", "mic.wav", "song.mp3"]).applying(.obsRecording)
        XCTAssertEqual(obs.items.map(\.role), [.gameplay, .webcam, .microphone, .music])
        XCTAssertTrue(obs.isMultiSourceSession)

        let twitch = plan(["vod.mp4", "gameplay.mp4"]).applying(.twitchVOD)
        XCTAssertEqual(twitch.items.map(\.role), [.main, .main])
        XCTAssertFalse(twitch.isMultiSourceSession)

        let podcast = plan(["host.wav", "guest.wav", "room.mov"]).applying(.podcast)
        XCTAssertEqual(podcast.items.map(\.role), [.microphone, .microphone, .camera])
        XCTAssertTrue(podcast.isMultiSourceSession)

        let auto = plan(["gameplay.mp4", "webcam.mp4"]).applying(.auto)
        XCTAssertEqual(auto.items.map(\.role), [.gameplay, .webcam])
        XCTAssertNil(auto.forcedSession)
        // A single file is never a "session", whatever the preset says.
        XCTAssertFalse(plan(["mic.wav"]).applying(.podcast).isMultiSourceSession)
    }
}
