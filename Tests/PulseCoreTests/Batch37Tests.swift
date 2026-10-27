import XCTest
@testable import PulseCore

final class Batch37Tests: XCTestCase {
    // MARK: #262 — loudness at the playhead

    private func features(_ rms: [Float], hop: Seconds = 0.1) -> AudioFeatureSeries {
        AudioFeatureSeries(hop: hop, rmsDB: rms, peakDB: rms, zeroCrossingRate: [Float](repeating: 0, count: rms.count), spectralFlux: [Float](repeating: 0, count: rms.count))
    }

    func testLoudnessSumsAudibleClipsThroughTheirGains() {
        let voice = UUID(), music = UUID()
        var a1 = Track(kind: .audio, name: "A1")
        a1.clips = [TimelineClip(name: "Voice", content: .media(assetID: voice), start: 0, sourceIn: 5, sourceDuration: 20)]
        var a2 = Track(kind: .audio, name: "A2")
        var bed = TimelineClip(name: "Music", content: .media(assetID: music), start: 0, sourceDuration: 20)
        bed.audio.gainDB = -20
        a2.clips = [bed]
        var timeline = Timeline(name: "T", canvas: .vertical1080, tracks: [a1, a2])
        let series = [voice: features([Float](repeating: -20, count: 400)), music: features([Float](repeating: -20, count: 400))]
        func f(_ id: UUID) -> AudioFeatureSeries? { series[id] }
        // −20 dB voice + (−20 − 20) dB music ≈ −19.96 dB.
        XCTAssertEqual(PlayheadLoudness.level(timeline, at: 3, features: f)!, -19.96, accuracy: 0.05)
        XCTAssertEqual(PlayheadLoudness.momentary(timeline, at: 3, features: f)!, -19.96, accuracy: 0.05)
        XCTAssertNil(PlayheadLoudness.level(timeline, at: 25, features: f), "nothing under the playhead")
        timeline.tracks[0].isMuted = true
        XCTAssertEqual(PlayheadLoudness.level(timeline, at: 3, features: f)!, -40, accuracy: 0.05, "muted voice leaves the quiet bed")
        timeline.tracks[0].isMuted = false
        timeline.tracks[0].volume = 0.5
        XCTAssertEqual(PlayheadLoudness.level(timeline, at: 3, features: f)!, -25.85, accuracy: 0.05, "half volume is −6 dB on the voice; the bed stays")
        XCTAssertEqual(PlayheadLoudness.verdict(-13.5, target: -14), .onTarget)
        XCTAssertEqual(PlayheadLoudness.verdict(-11, target: -14), .hot)
        XCTAssertEqual(PlayheadLoudness.verdict(-18, target: -14), .quiet)
    }

    func testIntegratedLoudnessGatesOutTheSilence() {
        let voice = UUID()
        var a1 = Track(kind: .audio, name: "A1")
        a1.clips = [TimelineClip(name: "Voice", content: .media(assetID: voice), start: 0, sourceDuration: 20)]
        let timeline = Timeline(name: "T", canvas: .vertical1080, tracks: [a1])
        // Speech at −18 for 10 s, then digital silence for 10 s.
        var rms = [Float](repeating: -18, count: 200)
        for i in 100..<200 { rms[i] = -100 }
        let series = features(rms)
        let integrated = PlayheadLoudness.integrated(timeline) { _ in series }!
        XCTAssertEqual(integrated, -18, accuracy: 0.6, "the silent half doesn't drag the reading down")
        XCTAssertNil(PlayheadLoudness.integrated(Timeline(name: "Empty", canvas: .vertical1080, tracks: [])) { _ in series })
    }

    // MARK: #361 — thumbnail frames ranked by reaction and room for text

    func testTextSpaceSitsBesideTheFaceAndReactionsRankHigher() {
        let left = NormRect(x: 0.1, y: 0.3, width: 0.25, height: 0.4)
        let room = ThumbnailPicker.textSpace(beside: left)
        XCTAssertGreaterThan(room.minX, left.maxX, "text goes to the right of a face on the left")
        XCTAssertGreaterThan(room.width, 0.4)
        let middle = NormRect(x: 0.3, y: 0.35, width: 0.4, height: 0.5)
        XCTAssertLessThanOrEqual(ThumbnailPicker.textSpace(beside: middle).maxY, middle.minY + 1e-9, "a centred face leaves the top band")
        XCTAssertEqual(ThumbnailPicker.textSpace(beside: nil).width, 0.92, accuracy: 1e-9)
        let pick = ThumbnailPick(time: 1, face: left, headline: "WOW", reason: "test")
        XCTAssertEqual(pick.textSpace, room)

        // Faces every 0.2 s: steady small face, then a head that doubles in size at 5 s.
        var samples: [FaceSample] = []
        var t: Seconds = 0
        while t <= 8 {
            let size = t >= 4.8 && t <= 5.4 ? 0.3 : 0.2
            samples.append(FaceSample(time: t, boxes: [NormRect(x: 0.1, y: 0.3, width: size, height: size)]))
            t += 0.2
        }
        let visual = VisualFeatureSeries(hop: 0.2, motion: [Float](repeating: 0, count: 41), brightness: [Float](repeating: 0.5, count: 41), sceneCuts: [], faces: samples)
        XCTAssertGreaterThan(ThumbnailPicker.reaction(at: 5, visual: visual), 0.5)
        XCTAssertEqual(ThumbnailPicker.reaction(at: 2, visual: visual), 0, accuracy: 1e-9)
        let best = ThumbnailPicker.alternates(in: TimeRange(start: 0, end: 8), visual: visual, count: 1)
        XCTAssertEqual(best.first!.time, 5, accuracy: 0.21, "the reaction frame wins")
    }

    // MARK: #479 — macros

    func testMacrosAreSavedAndReplaced() throws {
        var settings = AppSettings()
        let macro = EditorMacro(name: "Shorts pass", steps: ["tighten the pauses", "  add captions ", ""])
        XCTAssertEqual(macro.steps, ["tighten the pauses", "add captions"])
        XCTAssertEqual(macro.summary, "tighten the pauses → add captions")
        settings.rememberMacro(macro)
        settings.rememberMacro(EditorMacro(name: "shorts PASS", steps: ["add music"]))
        XCTAssertEqual(settings.macros.count, 1, "same name replaces")
        XCTAssertEqual(settings.macros.first?.steps, ["add music"])
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(back.macros, settings.macros)
        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).macros.isEmpty)
    }
}
