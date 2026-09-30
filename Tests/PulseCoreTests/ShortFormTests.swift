import XCTest
@testable import PulseCore

final class ShortFormTests: XCTestCase {
    func captionTimeline() -> Timeline {
        var t = Fixtures.simpleTimeline(clipDuration: 10) // source 100…110
        var words: [CaptionWord] = []
        for i in 0..<16 {
            var text = "word\(i)"
            if i == 5 { text = "insane!" }
            if i == 9 { text = "fuck" }
            let start: Double = 100 + Double(i) * 0.5
            words.append(CaptionWord(text: text, start: start, end: start + 0.4))
        }
        var style = CaptionStyle.bold
        style.maxWordsPerPage = 3
        t.captions = CaptionTrack(sourceAssetID: Fixtures.assetID, words: words, style: style)
        return t
    }

    func testCaptionsMapThroughTimelineAndFollowCuts() {
        var t = captionTimeline()
        var words = CaptionLayoutEngine.timelineWords(t.captions!, in: t)
        XCTAssertEqual(words.count, 16, "linked video+audio clips must not duplicate words")
        XCTAssertEqual(words[2].start, 1.0, accuracy: 1e-9)
        // Cut out source 101.0–102.0 (words 2 and 3) — later words shift left by 1 s.
        t.removeSourceRanges([TimeRange(start: 101, end: 102)], assetID: Fixtures.assetID, reason: .transcriptEdit)
        words = CaptionLayoutEngine.timelineWords(t.captions!, in: t)
        XCTAssertEqual(words.count, 14)
        XCTAssertEqual(words[2].start, 1.0, accuracy: 1e-6, "word4 now sits where word2 was")
        XCTAssertEqual(words[2].text, "WORD4", "bold preset uppercases")
    }

    func testCaptionPagingAndActiveWord() {
        let t = captionTimeline()
        let words = CaptionLayoutEngine.timelineWords(t.captions!, in: t)
        let pages = CaptionLayoutEngine.pages(words, style: t.captions!.style)
        XCTAssertTrue(pages.allSatisfy { $0.words.count <= 3 })
        // "insane!" ends a sentence → page break after it.
        XCTAssertTrue(pages.contains { $0.words.last?.text == "INSANE!" })
        let page = CaptionLayoutEngine.page(at: 1.1, in: pages)
        XCTAssertNotNil(page)
        let active = CaptionLayoutEngine.activeWordIndex(in: page!, at: 1.1)
        XCTAssertEqual(page!.words[active!].text, "WORD2")
        XCTAssertNil(CaptionLayoutEngine.page(at: 50, in: pages))
    }

    func testProfanityMasking() {
        var t = captionTimeline()
        t.captions!.profanity = .mask
        let words = CaptionLayoutEngine.timelineWords(t.captions!, in: t)
        XCTAssertTrue(words.contains { $0.text == "F***" })
        t.captions!.profanity = .hide
        XCTAssertEqual(CaptionLayoutEngine.timelineWords(t.captions!, in: t).count, 15)
    }

    func testCaptionWordEditingSplitsTiming() {
        var track = captionTimeline().captions!
        let id = track.words[0].id
        track.setWordText(id: id, text: "hello there")
        XCTAssertEqual(track.words.count, 17)
        XCTAssertEqual(track.words[0].text, "hello")
        XCTAssertEqual(track.words[1].end, 100.4, accuracy: 1e-9)
        track.toggleEmphasis(id: track.words[3].id)
        XCTAssertTrue(track.words[3].isEmphasized)
        XCTAssertFalse(track.words[3].emphasisIsAI)
    }

    func testEmphasisDetectorPicksImportantWords() {
        let words = ["I", "literally", "fell", "off", "the", "map", "and", "it", "was", "INSANE!"]
        let picks = EmphasisDetector.emphasisIndices(words)
        XCTAssertTrue(picks.contains(9))
        XCTAssertFalse(picks.contains(0))
    }

    func testSafeAreaClamp() {
        let y = SafeAreaPlatform.tiktok.clampCenterY(0.95, blockHeight: 0.1)
        XCTAssertLessThanOrEqual(y + 0.05, 1 - SafeAreaPlatform.tiktok.insets.bottom + 1e-9)
    }

    func testSplitScreenLayoutPlacesGameplayTopAndWebcamBottom() {
        var t = Fixtures.simpleTimeline(clipDuration: 10)
        LayoutEngine.ensureWebcamLayer(in: &t, assetID: Fixtures.assetID)
        let webcamRegion = NormRect(x: 0.75, y: 0.7, width: 0.25, height: 0.3)
        let context = LayoutContext(sourceSize: Size2(1920, 1080), webcamRegion: webcamRegion, faceCenter: Vec2(0.87, 0.8), profile: .gameplayWithFacecam)
        LayoutEngine.apply(.splitScreen, to: &t, context: context)
        let gameplay = t.allClips.first { $0.role == .gameplay }!
        let webcam = t.allClips.first { $0.role == .webcam }!
        XCTAssertEqual(gameplay.linkGroup, webcam.linkGroup, "facecam is linked to the gameplay clip")
        let canvas = t.canvas.size
        let g = LayerGeometry.resolve(gameplay.transform, at: 0, sourceSize: context.sourceSize, canvasSize: canvas)
        let w = LayerGeometry.resolve(webcam.transform, at: 0, sourceSize: context.sourceSize, canvasSize: canvas)
        XCTAssertEqual(g.frame.y, 0, accuracy: 2)
        XCTAssertEqual(g.frame.height, 1920 * 0.58, accuracy: 2)
        XCTAssertEqual(w.frame.y, 1920 * 0.58, accuracy: 2)
        XCTAssertEqual(w.frame.y + w.frame.height, 1920, accuracy: 2)
        // Webcam crop stays within the detected webcam region.
        XCTAssertGreaterThanOrEqual(webcam.transform.crop.minX, webcamRegion.minX - 1e-6)
        XCTAssertLessThanOrEqual(webcam.transform.crop.maxY, webcamRegion.maxY + 1e-6)
        XCTAssertEqual(t.layout, .splitScreen)
    }

    func testLayoutWithoutWebcamFallsBackToFullFrame() {
        var t = Fixtures.simpleTimeline(clipDuration: 10)
        LayoutEngine.apply(.splitScreen, to: &t, context: LayoutContext(sourceSize: Size2(1920, 1080)))
        let gameplay = t.allClips.first { $0.role == .gameplay }!
        XCTAssertEqual(gameplay.transform.crop.pixelAspect(in: Size2(1920, 1080)), 9.0 / 16.0, accuracy: 1e-6)
    }

    func testWebcamEstimatorFindsCornerFacecam() {
        let samples = (0..<20).map { i in
            FaceSample(time: Double(i), boxes: [NormRect(x: 0.84 + Double(i % 2) * 0.004, y: 0.74, width: 0.06, height: 0.11)])
        }
        let estimate = WebcamEstimator.estimate(faces: samples, frameSize: Size2(1920, 1080))
        XCTAssertEqual(estimate?.profile, .gameplayWithFacecam)
        XCTAssertTrue(estimate!.region.contains(estimate!.face.center))
        XCTAssertEqual(estimate!.region.maxX, 1, accuracy: 1e-6, "snapped to the right edge")

        let big = (0..<10).map { FaceSample(time: Double($0), boxes: [NormRect(x: 0.35, y: 0.2, width: 0.3, height: 0.5)]) }
        XCTAssertEqual(WebcamEstimator.estimate(faces: big, frameSize: Size2(1920, 1080))?.profile, .talkingHead)
        XCTAssertNil(WebcamEstimator.estimate(faces: [], frameSize: Size2(1920, 1080)))
    }

    func testPunchInsAreAIAndSpaced() {
        var t = Fixtures.simpleTimeline(clipDuration: 20)
        PunchInGenerator.apply(moments: [.reaction(5), .punchline(6), .statement(15)], to: &t, trackID: t.tracks[0].id)
        let zoom = t.tracks[0].clips[0].transform.zoom
        XCTAssertTrue(zoom.isAnimated)
        XCTAssertTrue(zoom.keyframes.allSatisfy(\.aiGenerated))
        XCTAssertEqual(zoom.value(at: 5.5), 1.2, accuracy: 1e-9, "reaction wins over nearby punchline")
        XCTAssertEqual(zoom.value(at: 15.5), 1.08, accuracy: 1e-9)
        XCTAssertEqual(zoom.value(at: 11), 1, accuracy: 1e-9)
    }

    func testAutoReframeFollowsFace() {
        var clip = TimelineClip(name: "C", content: .media(assetID: Fixtures.assetID), start: 0, sourceIn: 0, sourceDuration: 10)
        clip.transform.crop = NormRect.crop(aspect: 9.0 / 16.0, frameSize: Size2(1920, 1080))
        let faces = (0..<10).map { i in FaceSample(time: Double(i), boxes: [NormRect(center: Vec2(i < 5 ? 0.3 : 0.7, 0.4), width: 0.1, height: 0.2)]) }
        AutoReframer.applyFaceTracking(to: &clip, faces: faces)
        XCTAssertTrue(clip.transform.panX.isAnimated)
        XCTAssertLessThan(clip.transform.effectiveCrop(at: 1).center.x, 0.45)
        XCTAssertGreaterThan(clip.transform.effectiveCrop(at: 9.5).center.x, 0.55)
    }

    func testDuckingEnvelope() {
        var music = TimelineClip(name: "M", content: .media(assetID: UUID()), start: 0, sourceDuration: 10, role: .music)
        music.audio.duckUnderDialogue = true
        let ramps = DuckingPlanner.envelope(for: music, dialogue: [TimeRange(start: 2, end: 4)])
        XCTAssertTrue(ramps.contains { $0.gain < 0.3 })
        XCTAssertEqual(ramps.first?.gain, 1)
        XCTAssertEqual(ramps.last?.gain, 1)
        XCTAssertEqual(ramps.map(\.time), ramps.map(\.time).sorted())
    }
}
