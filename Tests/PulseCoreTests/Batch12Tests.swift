import XCTest
@testable import PulseCore

/// Roadmap batch 12: proxies by codec (#16), variable frame rate (#23), facecam presence (#47), loudness curve
/// (#140), learned emphasis (#238), bleep tone (#277), loudness target (#279), blended references (#367).
final class Batch12Tests: XCTestCase {
    func testProxiesSkipIntraCodecs() {
        let proxy = ProxySettings()
        XCTAssertTrue(proxy.shouldGenerateProxy(sourceHeight: 2160, duration: 600, codec: "hvc1"))
        XCTAssertFalse(proxy.shouldGenerateProxy(sourceHeight: 2160, duration: 600, codec: "apcn"), "ProRes decodes frame by frame")
        XCTAssertTrue(proxy.shouldGenerateProxy(sourceHeight: 4320, duration: 600, codec: "apcn"), "8K ProRes still gets one")
        XCTAssertFalse(proxy.shouldGenerateProxy(sourceHeight: 1080, duration: 600, codec: "avc1"))
        XCTAssertTrue(proxy.shouldGenerateProxy(sourceHeight: 1080, duration: 3 * 3600, codec: nil), "very long recordings always do")
        XCTAssertTrue(proxy.proxyReason(sourceHeight: 1080, duration: 60, codec: "apcn").contains("frame by frame"))
        XCTAssertTrue(proxy.proxyReason(sourceHeight: 2160, duration: 60, codec: "hvc1").contains("Above"))
        var off = proxy
        off.enabled = false
        XCTAssertFalse(off.shouldGenerateProxy(sourceHeight: 4320, duration: 60, codec: "hvc1"))
    }

    func testVariableFrameRateDecodesWhenMissing() throws {
        var meta = MediaMetadata(duration: 10, width: 1920, height: 1080, frameRate: 30)
        meta.variableFrameRate = true
        let data = try JSONEncoder().encode(meta)
        XCTAssertEqual(try JSONDecoder().decode(MediaMetadata.self, from: data).variableFrameRate, true)
        let old = try JSONDecoder().decode(MediaMetadata.self, from: Data(#"{"duration":5,"width":1,"height":1,"frameRate":30,"hasVideo":true,"hasAudio":false,"audioTrackCount":0,"audioChannels":0,"audioSampleRate":0,"fileSize":1}"#.utf8))
        XCTAssertNil(old.variableFrameRate)
    }

    func testFacecamAbsenceIsFoundBetweenFaces() {
        let region = NormRect(x: 0.75, y: 0.7, width: 0.22, height: 0.26)
        let face = NormRect(x: 0.8, y: 0.75, width: 0.1, height: 0.14)
        let elsewhere = NormRect(x: 0.1, y: 0.1, width: 0.1, height: 0.14)
        var faces: [FaceSample] = []
        for t in stride(from: 0.0, through: 60, by: 2) {
            // Present 0–20 s, gone 20–40 s (a face elsewhere doesn't count), back 40–60 s.
            faces.append(FaceSample(time: t, boxes: t >= 20 && t < 40 ? [elsewhere] : [face]))
        }
        let absent = FacecamPresence.absentRanges(faces: faces, region: region, duration: 70)
        XCTAssertEqual(absent.count, 1, "\(absent)")
        XCTAssertEqual(absent.first?.start ?? -1, 20, accuracy: 1e-9)
        XCTAssertEqual(absent.first?.end ?? -1, 40, accuracy: 1e-9)
        let tail = FacecamPresence.absentRanges(faces: faces + [FaceSample(time: 62, boxes: [])], region: region, duration: 70)
        XCTAssertEqual(tail.last?.end ?? -1, 70, accuracy: 1e-9, "absent to the end counts")
        XCTAssertTrue(FacecamPresence.absentRanges(faces: [], region: region, duration: 70).isEmpty)
        XCTAssertTrue(FacecamPresence.absentRanges(faces: faces, region: region, duration: 70, minimum: 30).isEmpty, "shorter than the minimum")
    }

    func testShortTermLoudnessCurve() {
        var meter = StreamingLoudness(sampleRate: 48_000)
        let loud = (0..<48_000).map { Float(sin(Double($0) * 2 * .pi * 440 / 48_000)) * 0.5 }
        let quiet = loud.map { $0 * 0.05 }
        for _ in 0..<5 { meter.add([loud, loud]) }
        for _ in 0..<5 { meter.add([quiet, quiet]) }
        let curve = meter.shortTermCurve
        XCTAssertEqual(curve.count, 10, "\(curve)")
        XCTAssertGreaterThan(curve[2], curve[9] + 15, "the quiet half reads far lower")
        XCTAssertTrue(curve.allSatisfy { $0 <= 0 && $0 >= -70 })
        XCTAssertTrue(StreamingLoudness(sampleRate: 48_000).shortTermCurve.isEmpty)
    }

    func testCaptionsLearnWhatYouEmphasise() {
        EmphasisDetector.learned = [:]
        defer { EmphasisDetector.learned = [:] }
        let words = ["so", "we", "walked", "to", "the", "shop", "and", "then", "nothing", "much"]
        XCTAssertFalse(EmphasisDetector.emphasisIndices(words).contains(5), "“shop” is nobody's hype word")
        EmphasisDetector.learned = ["shop": 3]
        XCTAssertTrue(EmphasisDetector.emphasisIndices(words).contains(5), "until you keep bolding it")
        EmphasisDetector.learned = ["insane": -2]
        let hype = ["that", "was", "insane", "bro"]
        XCTAssertFalse(EmphasisDetector.emphasisIndices(hype).contains(2), "a word you keep un-bolding stops being picked")
        EmphasisDetector.learned = [:]
        XCTAssertTrue(EmphasisDetector.emphasisIndices(hype).contains(2))
    }

    func testBleepToneFollowsTheSetting() {
        let rate = 48_000.0
        var low = [[Float](repeating: 0.3, count: Int(rate))]
        var high = low
        AudioCensor.process(&low, sampleRate: rate, ranges: [TimeRange(start: 0.1, end: 0.9)], mode: .bleep, frequency: 400)
        AudioCensor.process(&high, sampleRate: rate, ranges: [TimeRange(start: 0.1, end: 0.9)], mode: .bleep, frequency: 1600)
        func crossings(_ s: [Float]) -> Int {
            var n = 0
            for i in (Int(rate * 0.2))..<Int(rate * 0.8) where (s[i] >= 0) != (s[i - 1] >= 0) { n += 1 }
            return n
        }
        XCTAssertEqual(crossings(low[0]), 480, accuracy: 4, "400 Hz over 0.6 s")
        XCTAssertEqual(crossings(high[0]), 1920, accuracy: 4, "1600 Hz over 0.6 s")
        var timeline = Fixtures.simpleTimeline(clipDuration: 30)
        let words = [TranscriptWord(text: "fuck", start: 105, end: 105.3)]
        XCTAssertEqual(AudioCensor.apply(.bleep, to: &timeline, words: words, assetID: Fixtures.assetID, tone: 700), 2)
        XCTAssertEqual(timeline.tracks[3].clips[0].audio.censorTone, 700)
        XCTAssertNotEqual(timeline.tracks[3].clips[0].audio.enhanceFingerprint, { var a = timeline.tracks[3].clips[0].audio; a.censorTone = 1000; return a.enhanceFingerprint }(),
                          "a different tone renders a different file")
    }

    func testLoudnessTargetGainIsCappedByHeadroom() {
        XCTAssertEqual(LoudnessVerdict.gain(from: -20, to: -14, peakDB: -8), 6, accuracy: 1e-9)
        XCTAssertEqual(LoudnessVerdict.gain(from: -20, to: -14, peakDB: -3), 2, accuracy: 1e-9, "only 2 dB of headroom below −1 dBTP")
        XCTAssertEqual(LoudnessVerdict.gain(from: -10, to: -14, peakDB: -0.5), -4, accuracy: 1e-9, "lowering is never capped")
        XCTAssertEqual(LoudnessVerdict.gain(from: -.infinity, to: -14, peakDB: -60), 0, "silence stays silent")
        var timeline = Fixtures.simpleTimeline(clipDuration: 10)
        XCTAssertEqual(LoudnessVerdict.adjustGain(&timeline, by: 3), 1)
        XCTAssertEqual(timeline.tracks[3].clips[0].audio.gainDB, 3, accuracy: 1e-9)
        XCTAssertEqual(LoudnessVerdict.adjustGain(&timeline, by: 0.01), 0)
        let settings = try? JSONDecoder().decode(ExportSettings.self, from: Data("{}".utf8))
        XCTAssertNil(settings?.loudnessTarget)
    }

    func testBlendedReferenceSitsBetween() {
        let a = ReferenceStyle(name: "A", duration: 600, aspect: 1.78, cutsPerMinute: 4, averageShotLength: 15, zoomsPerMinute: 1, zoomScale: 1.1,
                               captions: ReferenceStyle.CaptionLook(coverage: 0.9, positionY: 0.8, lineHeight: 0.06, wordsOnScreen: 3, uppercase: true),
                               popupsPerMinute: 0, wordsPerMinute: 150, pauseRatio: 0.1, musicBed: 0.2, effectsPerMinute: 0.2, fadesPerMinute: 0, opensFast: false)
        let b = ReferenceStyle(name: "B", duration: 1200, aspect: 1.78, cutsPerMinute: 12, averageShotLength: 5, zoomsPerMinute: 3, zoomScale: 1.3,
                               captions: nil, popupsPerMinute: 1, wordsPerMinute: nil, pauseRatio: 0.04, musicBed: 0.8, effectsPerMinute: 1, fadesPerMinute: 0.5, opensFast: true)
        let mid = a.blended(with: b)
        XCTAssertEqual(mid.cutsPerMinute, 8, accuracy: 1e-9)
        XCTAssertEqual(mid.zoomScale, 1.2, accuracy: 1e-9)
        XCTAssertEqual(mid.wordsPerMinute, 150, "a missing measurement doesn't drag the other down")
        XCTAssertEqual(mid.pauseRatio ?? 0, 0.07, accuracy: 1e-9)
        XCTAssertNotNil(mid.captions, "halfway keeps the captions of the one that has them")
        XCTAssertNil(a.blended(with: b, weight: 0.9).captions)
        XCTAssertEqual(mid.name, "A + B")
        XCTAssertTrue(a.blended(with: b, weight: 1).opensFast)
        XCTAssertEqual(a.blended(with: b, weight: 0).cutsPerMinute, 4)
    }
}
