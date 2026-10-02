import XCTest
@testable import PulseCore

final class ReferenceStyleTests: XCTestCase {
    /// A 2-minute, fast-cut YouTube-style reference: a cut every 4 s, six punch-ins, wall-to-wall talking
    /// with music under it, four sound-effect hits, one dip to black, captions and two meme pop-ups.
    func fastReference() -> (MediaAnalysis, [TextSample]) {
        let duration: Seconds = 120
        let hop: Seconds = 0.5
        let n = Int(duration / hop)
        let cuts = stride(from: 4.0, to: duration, by: 4).map { $0 }
        let zoomTimes: [Seconds] = [10, 30, 50, 70, 90, 110]
        let small = NormRect(x: 0.4, y: 0.3, width: 0.2, height: 0.2)
        let big = NormRect(center: small.center, width: 0.264, height: 0.264)
        var faces: [FaceSample] = []
        for i in 0..<n {
            let t = Double(i) * hop
            let zoomed = zoomTimes.contains { t >= $0 && t < $0 + 2 }
            faces.append(FaceSample(time: t, boxes: [zoomed ? big : small]))
        }
        var brightness = [Float](repeating: 0.5, count: n)
        brightness[120] = 0.02
        brightness[121] = 0.02
        let visual = VisualFeatureSeries(hop: hop, motion: [Float](repeating: 0.02, count: n), brightness: brightness, sceneCuts: cuts, faces: faces)

        let hits: [Seconds] = [15, 45, 75, 105]
        let audioHop: Seconds = 0.1
        let m = Int(duration / audioHop)
        var flux = [Float](repeating: 1, count: m)
        for h in hits { flux[Int(h / audioHop)] = 30 }
        let audio = AudioFeatureSeries(hop: audioHop, rmsDB: [Float](repeating: -20, count: m), peakDB: [Float](repeating: -6, count: m),
                                       zeroCrossingRate: [Float](repeating: 0.1, count: m), spectralFlux: flux)
        var words: [TranscriptWord] = []
        var t = 0.2
        while t < duration - 0.5 {
            if !hits.contains(where: { abs($0 - t) < 0.4 }) { words.append(TranscriptWord(text: "word", start: t, end: t + 0.25)) }
            t += 0.3
        }
        var analysis = MediaAnalysis(assetID: UUID(), duration: duration, audio: audio, visual: visual,
                                     transcript: Transcript(language: "en", words: words, source: .demo))
        analysis.profile = .talkingHead

        var text: [TextSample] = []
        for s in 0..<120 {
            let time = Double(s) + 0.5
            var boxes = [TextBox(rect: NormRect(x: 0.02, y: 0.02, width: 0.2, height: 0.03), text: "@streamer"),
                         TextBox(rect: NormRect(x: 0.3, y: 0.675, width: 0.4, height: 0.05), text: "THIS IS LINE\(s)")]
            if [20, 21, 80].contains(s) {
                boxes.append(TextBox(rect: NormRect(x: 0.3, y: 0.12, width: 0.4, height: 0.15), text: "NO WAY"))
            }
            text.append(TextSample(time: time, boxes: boxes))
        }
        return (analysis, text)
    }

    func testMeasuresTheEditingOfAFastReference() {
        let (analysis, text) = fastReference()
        let style = ReferenceStyleAnalyzer.measure(name: "Fast Edit", analysis: analysis, text: text, frameSize: Size2(1920, 1080))
        XCTAssertEqual(style.cutsPerMinute, 14.5, accuracy: 0.01)
        XCTAssertEqual(style.averageShotLength, 4, accuracy: 0.01)
        XCTAssertEqual(style.zoomsPerMinute, 3, accuracy: 0.01)
        XCTAssertEqual(style.zoomScale, 1.32, accuracy: 0.01)
        XCTAssertLessThan(style.pauseRatio ?? 1, 0.06, "tight jump cuts")
        XCTAssertTrue(style.hasMusic, "level never drops between words")
        XCTAssertEqual(style.effectsPerMinute, 2, accuracy: 0.01)
        XCTAssertEqual(style.fadesPerMinute, 0.5, accuracy: 0.01)
        XCTAssertEqual(style.popupsPerMinute, 1, accuracy: 0.01, "two short NO WAY pop-ups; the @streamer overlay is ignored")
        let look = try? XCTUnwrap(style.captions)
        XCTAssertEqual(look?.positionY ?? 0, 0.7, accuracy: 0.01)
        XCTAssertEqual(look?.lineHeight ?? 0, 0.05, accuracy: 0.001)
        XCTAssertEqual(look?.wordsOnScreen ?? 0, 3, accuracy: 0.01)
        XCTAssertEqual(look?.uppercase, true)
        XCTAssertGreaterThan(look?.coverage ?? 0, 0.9)
        XCTAssertEqual(style.pace, .fast)
        XCTAssertFalse(style.isVertical)
        XCTAssertGreaterThanOrEqual(style.traits.count, 8)
    }

    func testAStaticTitleIsNotCaptions() {
        let samples = (0..<30).map { TextSample(time: Double($0), boxes: [TextBox(rect: NormRect(x: 0.2, y: 0.8, width: 0.6, height: 0.05), text: "Episode 4")]) }
        XCTAssertNil(ReferenceStyleAnalyzer.captions(in: samples).look)
    }

    func testCopyingClosely() {
        let (analysis, text) = fastReference()
        let style = ReferenceStyleAnalyzer.measure(name: "Fast Edit", analysis: analysis, text: text, frameSize: Size2(1920, 1080))
        let answers = ReferenceAnswers.recommended(for: style)
        XCTAssertEqual(answers.length, .likeReference)
        let o = style.longFormOptions(answers)
        XCTAssertEqual(o.minimumLength, 96, accuracy: 0.01)
        XCTAssertEqual(o.maximumLength, 144, accuracy: 0.01)
        XCTAssertEqual(o.silencePreset, .aggressive)
        XCTAssertTrue(o.zooms)
        XCTAssertEqual(o.zoomSpacing, 20, accuracy: 0.01)
        XCTAssertEqual(o.style?.rhythmZooms, true)
        XCTAssertEqual(o.style?.rhythmSpacing ?? 0, 4, accuracy: 0.01)
        XCTAssertNotNil(o.style?.captionLook)
        XCTAssertTrue(o.music)
        XCTAssertTrue(o.soundEffects)
        XCTAssertTrue(o.memes)
        XCTAssertEqual(o.memeSpacing, 60, accuracy: 0.01)
        XCTAssertEqual(o.style?.fades, true)
        XCTAssertEqual(o.restraint, .energetic)

        var loose = answers
        loose.closeness = .loosely
        let l = style.longFormOptions(loose)
        XCTAssertEqual(l.silencePreset, .balanced)
        XCTAssertEqual(l.zoomSpacing, 21, accuracy: 0.01)
        XCTAssertEqual(l.restraint, .balanced)

        var mine = answers
        mine.copyCaptions = false
        mine.focus = .funny
        let m = style.longFormOptions(mine)
        XCTAssertNil(m.style?.captionLook, "PULSE's own captions")
        XCTAssertTrue(m.captions)
        XCTAssertEqual(m.style?.focusTags.first, .funny)
    }

    func testACalmReferenceTurnsThingsOff() {
        let calm = ReferenceStyle(name: "Calm", duration: 900, aspect: 16.0 / 9.0, cutsPerMinute: 0.5, averageShotLength: 120,
                                  zoomsPerMinute: 0, zoomScale: 1.16, captions: nil, popupsPerMinute: 0, wordsPerMinute: 140,
                                  pauseRatio: 0.2, musicBed: 0.05, effectsPerMinute: 0, fadesPerMinute: 0, opensFast: false)
        let o = calm.longFormOptions(ReferenceAnswers.recommended(for: calm))
        XCTAssertFalse(o.zooms)
        XCTAssertFalse(o.captions)
        XCTAssertFalse(o.music)
        XCTAssertFalse(o.soundEffects)
        XCTAssertFalse(o.memes)
        XCTAssertEqual(o.silencePreset, .conservative)
        XCTAssertEqual(o.restraint, .subtle)
        XCTAssertTrue(o.coldOpen, "long references still get a hook by default")
        XCTAssertEqual(calm.pace, .calm)

        let vertical = ReferenceStyle(name: "Short", duration: 45, aspect: 9.0 / 16.0, cutsPerMinute: 20, averageShotLength: 3,
                                      zoomsPerMinute: 6, zoomScale: 1.2, captions: nil, popupsPerMinute: 0, wordsPerMinute: nil,
                                      pauseRatio: nil, musicBed: 0.6, effectsPerMinute: 2, fadesPerMinute: 0, opensFast: true)
        XCTAssertEqual(ReferenceAnswers.recommended(for: vertical).length, .shorts)
        let shorts = vertical.shortOptions(ReferenceAnswers.recommended(for: vertical), base: ShortBuildOptions(settings: AISettings()))
        XCTAssertTrue(shorts.punchIns)
        XCTAssertEqual(shorts.punchInSettings.minimumSpacing, 10, accuracy: 0.01)
        XCTAssertEqual(shorts.punchInSettings.reactionZoom, 1.2, accuracy: 0.001)
        XCTAssertEqual(shorts.silence, .aggressive)
        XCTAssertTrue(vertical.shortWantsMusic(ReferenceAnswers(), default: false))
    }

    func testCaptionLookBecomesACaptionStyle() {
        let look = ReferenceStyle.CaptionLook(coverage: 0.9, positionY: 0.55, lineHeight: 0.05, wordsOnScreen: 1, uppercase: true)
        let style = look.captionStyle(canvasHeight: 1920, landscape: false)
        XCTAssertEqual(style.presetName, "Matched")
        XCTAssertEqual(style.displayMode, .wordByWord)
        XCTAssertEqual(style.maxWordsPerPage, 1)
        XCTAssertEqual(style.text.textCase, .uppercase)
        XCTAssertEqual(style.positionY, 0.55, accuracy: 0.001)
        XCTAssertEqual(style.text.fontSize, 81.6, accuracy: 0.01)

        let subtitles = ReferenceStyle.CaptionLook(coverage: 0.9, positionY: 0.88, lineHeight: 0.04, wordsOnScreen: 7, uppercase: false)
        let s = subtitles.captionStyle(canvasHeight: 1080, landscape: true)
        XCTAssertEqual(s.displayMode, .phrase)
        XCTAssertEqual(s.maxWordsPerPage, 7)
        XCTAssertEqual(s.text.textCase, .asTyped)
    }

    func testStyledEditFollowsTheReference() {
        let duration: Seconds = 1500
        let spikes = stride(from: 150.0, to: 1400, by: 200).map { $0 }
        var special: [(Seconds, String)] = []
        for s in spikes { for k in 0..<4 { special.append((s + 1 + Double(k) * 0.5, "hahaha")) } }
        let analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: duration,
                                     audio: Fixtures.audio(duration: duration, spikes: spikes),
                                     transcript: Fixtures.transcript(duration: duration, special: special), profile: .gameplay)
        let asset = Fixtures.mediaAsset(duration: duration)
        let plain = LongFormEditor.build(asset: asset, analysis: analysis,
                                         options: LongFormOptions(minimumLength: 240, maximumLength: 400, memes: false, soundEffects: false, music: false))
        let tuning = StyleTuning(name: "Fast Edit", silence: .aggressive, zoomSpacing: 10, zoomScale: 1.25, rhythmZooms: true, rhythmSpacing: 4,
                                 captionLook: ReferenceStyle.CaptionLook(coverage: 1, positionY: 0.6, lineHeight: 0.05, wordsOnScreen: 1, uppercase: true),
                                 fades: true)
        let styled = LongFormEditor.build(asset: asset, analysis: analysis,
                                          options: LongFormOptions(minimumLength: 240, maximumLength: 400, memes: false, soundEffects: false,
                                                                   music: false, style: tuning))
        func zooms(_ t: Timeline) -> Int { t.tracks[0].clips.reduce(0) { $0 + $1.transform.zoom.keyframes.filter(\.aiGenerated).count } }
        XCTAssertTrue(styled.timeline.name.contains("like Fast Edit"))
        XCTAssertTrue(styled.report.contains("styled like"), styled.report)
        XCTAssertEqual(styled.timeline.captions?.style.presetName, "Matched")
        XCTAssertEqual(styled.timeline.captions?.style.displayMode, .wordByWord)
        XCTAssertGreaterThan(zooms(styled.timeline), zooms(plain.timeline), "punches in on sentences too")
        if styled.segments.count > 1 {
            XCTAssertTrue(styled.timeline.tracks[0].clips.contains { $0.transitionOut?.kind == .fadeToBlack && $0.transitionOut?.duration == 0.3 })
        }
        XCTAssertGreaterThanOrEqual(styled.timeline.removedSections.count, plain.timeline.removedSections.count, "tighter jump cuts")
    }

    func testSavedStylesAreKeptNewestFirst() {
        var settings = AppSettings()
        let a = ReferenceStyle(name: "A", duration: 60, aspect: 1.77, cutsPerMinute: 1, averageShotLength: 30, zoomsPerMinute: 0, zoomScale: 1.16,
                               captions: nil, popupsPerMinute: 0, wordsPerMinute: nil, pauseRatio: nil, musicBed: 0, effectsPerMinute: 0,
                               fadesPerMinute: 0, opensFast: false)
        var b = a
        b.id = UUID()
        b.name = "B"
        settings.rememberStyle(a)
        settings.rememberStyle(b)
        var a2 = a
        a2.id = UUID()
        settings.rememberStyle(a2)
        XCTAssertEqual(settings.referenceStyles.map(\.name), ["A", "B"], "re-studying replaces the old one")
        let data = try? JSONEncoder().encode(settings)
        let back = data.flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) }
        XCTAssertEqual(back?.referenceStyles.count, 2)
    }
}
