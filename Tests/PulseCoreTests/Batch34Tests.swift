import XCTest
@testable import PulseCore

final class Batch34Tests: XCTestCase {
    // MARK: #289 — what's under the playhead renders first

    func testPlayheadOrderPutsTheCurrentRangeFirstThenWhatPlaysNext() {
        let ranges = [TimeRange(start: 0, end: 4), TimeRange(start: 8, end: 12), TimeRange(start: 14, end: 18),
                      TimeRange(start: 30, end: 35), TimeRange(start: 5, end: 9)]
        let ordered = PlayheadOrder.sorted(ranges, around: 10) { $0 }
        XCTAssertEqual(ordered.map(\.start), [8, 5, 14, 0, 30])
        XCTAssertEqual(PlayheadOrder.cost(TimeRange(start: 8, end: 12), playhead: 10), 0)
        XCTAssertEqual(PlayheadOrder.cost(TimeRange(start: 14, end: 18), playhead: 10), 4)
        XCTAssertEqual(PlayheadOrder.cost(TimeRange(start: 0, end: 4), playhead: 10), 9, "behind the playhead costs half again as much")
        // Ties keep their order.
        let tied = [TimeRange(start: 20, end: 21), TimeRange(start: 20, end: 22)]
        XCTAssertEqual(PlayheadOrder.sorted(tied, around: 0) { $0 }.map(\.end), [21, 22])
    }

    // MARK: #327 — multicam sensitivity and cutting on the beat

    func testSwitchTuningMapsTheSliderToShotLengthAndCrosstalk() {
        let patient = MulticamEditor.SwitchTuning(sensitivity: 0)
        let eager = MulticamEditor.SwitchTuning(sensitivity: 1)
        let middle = MulticamEditor.SwitchTuning(sensitivity: 0.5)
        XCTAssertEqual(patient.minimumShot, 4, accuracy: 1e-9)
        XCTAssertEqual(patient.crosstalkDB, 6, accuracy: 1e-6)
        XCTAssertEqual(eager.minimumShot, 1.25, accuracy: 1e-9)
        XCTAssertEqual(eager.crosstalkDB, 2, accuracy: 1e-6)
        XCTAssertGreaterThan(middle.minimumShot, eager.minimumShot)
        XCTAssertLessThan(middle.minimumShot, patient.minimumShot)
        XCTAssertEqual(MulticamEditor.SwitchTuning(sensitivity: 7).minimumShot, eager.minimumShot, "clamped")
    }

    func testSwitchesSnapToNearbyBeatsAndStayGapless() {
        let a = UUID(), b = UUID()
        let cuts = [MulticamCut(range: TimeRange(start: 0, end: 5), assetID: a),
                    MulticamCut(range: TimeRange(start: 5, end: 10), assetID: b),
                    MulticamCut(range: TimeRange(start: 10, end: 15), assetID: a),
                    MulticamCut(range: TimeRange(start: 15, end: 20), assetID: b)]
        let snapped = MulticamEditor.snapped(cuts, toBeats: [4.8, 10.2, 12, 16.5])
        XCTAssertEqual(snapped[0].range.end, 4.8, accuracy: 1e-9)
        XCTAssertEqual(snapped[1].range.start, 4.8, accuracy: 1e-9)
        XCTAssertEqual(snapped[1].range.end, 10.2, accuracy: 1e-9)
        XCTAssertEqual(snapped[2].range.start, 10.2, accuracy: 1e-9)
        XCTAssertEqual(snapped[2].range.end, 15, "no beat within a third of a second → stays")
        XCTAssertEqual(snapped.last?.range.end, 20)
        XCTAssertEqual(snapped.map(\.assetID), cuts.map(\.assetID))
        // A move that would squeeze a shot below the minimum is skipped.
        let short = [MulticamCut(range: TimeRange(start: 0, end: 1), assetID: a), MulticamCut(range: TimeRange(start: 1, end: 10), assetID: b)]
        XCTAssertEqual(MulticamEditor.snapped(short, toBeats: [0.7], minimumShot: 0.5)[0].range.end, 0.7, accuracy: 1e-9)
        XCTAssertEqual(MulticamEditor.snapped(short, toBeats: [0.4], minimumShot: 0.5)[0].range.end, 1)
        XCTAssertEqual(MulticamEditor.snapped(cuts, toBeats: []).map(\.range.end), cuts.map(\.range.end))
    }

    // MARK: #489 — my own style, measured from a finished edit

    private func assets() -> (video: MediaAsset, music: MediaAsset, sfx: MediaAsset) {
        (MediaAsset(name: "VOD", path: "/tmp/vod.mp4", kind: .video, role: .main, metadata: MediaMetadata(duration: 600, width: 1920, height: 1080)),
         MediaAsset(name: "Song", path: "/tmp/song.m4a", kind: .audio, role: .music, metadata: MediaMetadata(duration: 180)),
         MediaAsset(name: "Whoosh", path: "/tmp/whoosh.wav", kind: .audio, role: .soundEffect, metadata: MediaMetadata(duration: 1)))
    }

    private func edit() -> (Timeline, [MediaAsset]) {
        let (video, music, sfx) = assets()
        var v1 = Track(kind: .video, name: "V1")
        for i in 0..<6 {
            var clip = TimelineClip(name: "Shot \(i)", content: .media(assetID: video.id), start: Double(i) * 10, sourceIn: Double(i) * 30, sourceDuration: 10)
            if i == 2 {
                _ = clip.transform.zoom.setKeyframe(at: 1, value: 1)
                _ = clip.transform.zoom.setKeyframe(at: 1.3, value: 1.2)
            }
            if i == 4 { clip.transitionIn = ClipTransition(kind: .fadeToBlack, duration: 0.5) }
            v1.clips.append(clip)
        }
        var t1 = Track(kind: .text, name: "T1")
        t1.clips.append(TimelineClip(name: "Pop", content: .text(TextElement(text: "WOW")), start: 12, sourceDuration: 3))
        var a1 = Track(kind: .audio, name: "A1")
        a1.clips.append(TimelineClip(name: "Song", content: .media(assetID: music.id), start: 0, sourceDuration: 30, role: .music))
        a1.clips.append(TimelineClip(name: "Whoosh", content: .media(assetID: sfx.id), start: 40, sourceDuration: 1))
        a1.clips.append(TimelineClip(name: "Whoosh", content: .media(assetID: sfx.id), start: 50, sourceDuration: 1))
        return (Timeline(name: "My edit", canvas: .landscape1080, tracks: [v1, t1, a1]), [video, music, sfx])
    }

    func testOwnStyleIsMeasuredOffTheTimeline() throws {
        let (timeline, assets) = edit()
        let style = try XCTUnwrap(ReferenceStyleAnalyzer.measure(timeline: timeline, assets: assets))
        XCTAssertEqual(style.name, "My edit")
        XCTAssertEqual(style.duration, 60, accuracy: 1e-9)
        XCTAssertEqual(style.aspect, 16.0 / 9.0, accuracy: 1e-9)
        XCTAssertEqual(style.cutsPerMinute, 5, accuracy: 1e-9)
        XCTAssertEqual(style.averageShotLength, 10, accuracy: 1e-9)
        XCTAssertEqual(style.zoomsPerMinute, 1, accuracy: 1e-9)
        XCTAssertEqual(style.zoomScale, 1.2, accuracy: 1e-9)
        XCTAssertEqual(style.popupsPerMinute, 1, accuracy: 1e-9)
        XCTAssertEqual(style.musicBed, 0.5, accuracy: 1e-9, "the song sits under half the edit")
        XCTAssertEqual(style.effectsPerMinute, 2, accuracy: 1e-9, "the SFX role comes from the asset when the clip has none")
        XCTAssertEqual(style.fadesPerMinute, 1, accuracy: 1e-9)
        XCTAssertNil(style.captions)
        XCTAssertFalse(style.opensFast)
        // Too short to say anything.
        XCTAssertNil(ReferenceStyleAnalyzer.measure(timeline: Timeline(name: "Tiny", canvas: .vertical1080, tracks: []), assets: []))
    }

    func testAverageOfSamplesWeighsThemEquallyAndKeepsTheOwnStyleID() throws {
        let (timeline, assets) = edit()
        var a = try XCTUnwrap(ReferenceStyleAnalyzer.measure(timeline: timeline, assets: assets))
        var b = a, c = a
        a.cutsPerMinute = 10; b.cutsPerMinute = 20; c.cutsPerMinute = 30
        b.musicBed = 0; c.musicBed = 1
        let mean = try XCTUnwrap(ReferenceStyle.average(of: [a, b, c], name: "Mine"))
        XCTAssertEqual(mean.cutsPerMinute, 20, accuracy: 1e-9)
        XCTAssertEqual(mean.musicBed, 0.5, accuracy: 1e-9)
        XCTAssertEqual(mean.id, ReferenceStyle.ownStyleID)
        XCTAssertEqual(mean.name, "Mine")
        XCTAssertNil(ReferenceStyle.average(of: [], name: "Nothing"))
    }

    func testSettingsKeepTheLastTenEditsAndRoundTrip() throws {
        let (timeline, assets) = edit()
        let style = try XCTUnwrap(ReferenceStyleAnalyzer.measure(timeline: timeline, assets: assets))
        var settings = AppSettings()
        XCTAssertNil(settings.ownStyle)
        for i in 0..<12 {
            var s = style
            s.cutsPerMinute = Double(i)
            settings.noteOwnEdit(s)
        }
        XCTAssertEqual(settings.ownStyleSamples.count, 10)
        XCTAssertEqual(settings.ownStyleSamples.first?.cutsPerMinute, 11, "newest first")
        XCTAssertEqual(settings.ownStyle?.name, "My last 10 videos")
        XCTAssertEqual(settings.ownStyle!.cutsPerMinute, 6.5, accuracy: 1e-9, "the mean of 2…11")
        settings.multicamSensitivity = 0.8
        settings.multicamOnBeat = true
        let data = try JSONEncoder().encode(settings)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(back.ownStyleSamples.count, 10)
        XCTAssertEqual(back.multicamSensitivity, 0.8, accuracy: 1e-9)
        XCTAssertTrue(back.multicamOnBeat)
        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(legacy.ownStyleSamples.isEmpty)
        XCTAssertEqual(legacy.multicamSensitivity, 0.5, accuracy: 1e-9)
    }
}
