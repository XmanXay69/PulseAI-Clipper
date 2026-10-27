import XCTest
@testable import PulseCore

final class Batch46Tests: XCTestCase {
    // MARK: #263 — noise profile learned from a marked silence

    func testNoiseProfileFoldsBinsIntoBandsAndBack() throws {
        // A rising ramp over 512 bins folds into 64 rising bands and expands back smoothly.
        let bins = (0..<512).map { Float($0) / 511 }
        let profile = NoiseProfile(bins: bins, learnedFrom: TimeRange(start: 10, end: 12), seconds: 2)
        XCTAssertEqual(profile.bands.count, NoiseProfile.bandCount)
        XCTAssertLessThan(profile.bands[0], profile.bands[63])
        XCTAssertEqual(profile.bands[0], (0..<8).map { Float($0) / 511 }.reduce(0, +) / 8, accuracy: 1e-6)
        let back = profile.expanded()
        XCTAssertEqual(back.count, 512)
        for k in 1..<512 { XCTAssertGreaterThanOrEqual(back[k], back[k - 1] - 1e-6, "monotone after expansion") }
        XCTAssertEqual(back[256], 0.5, accuracy: 0.02)
        XCTAssertFalse(profile.isEmpty)
        XCTAssertTrue(NoiseProfile(bands: [Float](repeating: 0, count: 64)).isEmpty)
        XCTAssertTrue(NoiseProfile(bins: []).isEmpty)
        let decoded = try JSONDecoder().decode(NoiseProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.fingerprint, profile.fingerprint)
        XCTAssertNotEqual(NoiseProfile(bins: bins.map { $0 * 2 }).fingerprint, profile.fingerprint)
    }

    func testAudioSettingsCarryTheProfileAndOldProjectsDecode() throws {
        var settings = AudioSettings()
        XCTAssertNil(settings.noiseProfile)
        settings.noiseReduction = 0.5
        settings.noiseMethod = .spectral
        let before = settings.enhanceFingerprint
        settings.noiseProfile = NoiseProfile(bins: [Float](repeating: 0.01, count: 512), seconds: 1.5)
        XCTAssertNotEqual(settings.enhanceFingerprint, before, "a learned profile changes the cached render")
        let back = try JSONDecoder().decode(AudioSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(back.noiseProfile?.seconds, 1.5)
        let old = try JSONDecoder().decode(AudioSettings.self, from: Data(#"{"noiseReduction":0.4}"#.utf8))
        XCTAssertNil(old.noiseProfile)
        // The neural method ignores the profile, so it doesn't fork the cache key there.
        settings.noiseMethod = .voiceIsolation
        XCTAssertFalse(settings.enhanceFingerprint.contains("np"))
    }

    // MARK: #56 — vertical reframe that follows the action

    private func gameplay(duration: Seconds = 30, hop: Seconds = 1) -> VisualFeatureSeries {
        let n = Int(duration / hop)
        var motion = [Float](repeating: 0.002, count: n)
        var x = [Float](repeating: 0.5, count: n)
        // A fight on the left for 10 s, calm, then on the right for 10 s.
        for i in 0..<10 { motion[i] = 0.08; x[i] = 0.2 }
        for i in 20..<30 { motion[i] = 0.08; x[i] = 0.8 }
        return VisualFeatureSeries(hop: hop, motion: motion, brightness: [Float](repeating: 0.5, count: n), sceneCuts: [], faces: [],
                                   actionX: x, actionY: [Float](repeating: 0.5, count: n))
    }

    func testActionReframerPansTowardTheAction() {
        let visual = gameplay()
        XCTAssertTrue(visual.tracksAction)
        XCTAssertEqual(visual.actionCenter(at: 5)?.x ?? 0, 0.2, accuracy: 1e-6)
        XCTAssertEqual(visual.actionCenter(at: 25)?.x ?? 0, 0.8, accuracy: 1e-6)
        var clip = TimelineClip(name: "Game", content: .media(assetID: Fixtures.assetID), start: 0, sourceIn: 0, sourceDuration: 30, role: .gameplay)
        clip.transform.crop = NormRect(x: 0.3, y: 0, width: 0.4, height: 1)   // a tall crop out of a 16:9 frame
        let added = ActionReframer.applyActionTracking(to: &clip, visual: visual)
        XCTAssertGreaterThanOrEqual(added, 2)
        let keys = clip.transform.panX.keyframes.filter(\.aiGenerated)
        XCTAssertEqual(keys.count, added)
        XCTAssertLessThan(clip.transform.panX.value(at: 2), 0, "early on the crop leans left")
        XCTAssertGreaterThan(clip.transform.panX.value(at: 29), 0, "later it leans right")
        // The crop never leaves the frame: |pan| ≤ centre − half width.
        for k in keys { XCTAssertLessThanOrEqual(abs(k.value), 0.3 + 1e-6) }
        // Each step is capped so a cut-away never whips.
        let values = keys.map(\.value)
        for i in 1..<values.count { XCTAssertLessThanOrEqual(abs(values[i] - values[i - 1]), 0.25 + 1e-6) }
    }

    func testActionReframerHoldsStillWithoutMotionOrTracking() {
        let n = 30
        let calm = VisualFeatureSeries(hop: 1, motion: [Float](repeating: 0.001, count: n), brightness: [Float](repeating: 0.5, count: n), sceneCuts: [], faces: [],
                                       actionX: (0..<n).map { Float($0 % 2) }, actionY: [Float](repeating: 0.5, count: n))
        var clip = TimelineClip(name: "Game", content: .media(assetID: Fixtures.assetID), start: 0, sourceDuration: 30, role: .gameplay)
        clip.transform.crop = NormRect(x: 0.3, y: 0, width: 0.4, height: 1)
        // Flat motion: the median threshold means nothing stands out enough to steer.
        XCTAssertEqual(ActionReframer.applyActionTracking(to: &clip, visual: calm), 0)
        XCTAssertTrue(clip.transform.panX.keyframes.isEmpty)
        let untracked = VisualFeatureSeries(hop: 1, motion: [Float](repeating: 0.08, count: n), brightness: [Float](repeating: 0.5, count: n), sceneCuts: [], faces: [])
        XCTAssertFalse(untracked.tracksAction)
        XCTAssertNil(untracked.actionCenter(at: 3))
        XCTAssertEqual(ActionReframer.applyActionTracking(to: &clip, visual: untracked), 0)
    }

    func testOldVisualSeriesDecodeWithoutActionAndNewOnesRoundTrip() throws {
        let series = gameplay()
        let back = try JSONDecoder().decode(VisualFeatureSeries.self, from: JSONEncoder().encode(series))
        XCTAssertEqual(back.actionX?.values, series.actionX?.values)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(series)) as! [String: Any]
        json["actionX"] = nil
        json["actionY"] = nil
        let old = try JSONDecoder().decode(VisualFeatureSeries.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.actionX)
        XCTAssertFalse(old.tracksAction)
    }

    func testShortBuilderFollowsTheActionOnTallGameplayShorts() {
        var asset = MediaAsset(name: "ranked.mp4", path: "/tmp/ranked.mp4", kind: .video, role: .gameplay)
        asset.metadata = MediaMetadata(duration: 600, width: 1920, height: 1080, frameRate: 30, hasVideo: true, hasAudio: true)
        var analysis = MediaAnalysis(assetID: asset.id, duration: 600, audio: Fixtures.audio(duration: 600, spikes: [100]))
        analysis.profile = .gameplay
        analysis.visual = gameplay(duration: 600)
        // The fight moves across the screen inside the clip's range.
        for i in 90..<110 { analysis.visual?.motion.values[i] = 0.08; analysis.visual?.actionX?.values[i] = i < 100 ? 0.15 : 0.85 }
        let candidate = ClipGenerator(input: ClipGenerationInput(analysis: analysis), settings: ClipGenerationSettings(targetDuration: 20, minimumPotential: 0))
            .candidate(for: TimeRange(start: 88, end: 112))
        var options = ShortBuildOptions.oneClick
        options.layout = .fullFrame
        options.aiFraming = true
        let timeline = ShortBuilder.build(ShortBuildInput(candidate: candidate, asset: asset, analysis: analysis), options: options)
        let game = timeline.tracks[0].clips.first { $0.role == .gameplay || $0.role == .main }
        XCTAssertNotNil(game)
        XCTAssertFalse(game?.transform.panX.keyframes.filter(\.aiGenerated).isEmpty ?? true, "a tall gameplay short pans with the action")
    }
}
