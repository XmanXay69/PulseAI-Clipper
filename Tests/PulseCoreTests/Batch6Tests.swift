import XCTest
@testable import PulseCore

/// Roadmap batch 6: caption edits (#237/#240/#250/#254/#259), AI provenance (#210/#230), de-esser (#264),
/// EQ presets (#265), audio-only export (#278).
final class Batch6Tests: XCTestCase {
    func track() -> CaptionTrack {
        let words = ["so", "the", "Valerant", "lobby", "hahaha", "lol", "went", "crazy."].enumerated().map {
            TranscriptWord(text: $1, start: Double($0) * 0.5, end: Double($0) * 0.5 + 0.4)
        }
        let transcript = Transcript(language: "en", words: words, source: .demo)
        return CaptionTrack.make(from: transcript, range: TimeRange(start: 0, end: 10), assetID: Fixtures.assetID, style: .tiktok, emphasize: false)
    }

    func testCaptionTimingTextAndEmojiEdits() {
        var captions = track()
        let first = captions.words[0].start
        XCTAssertEqual(captions.shiftTiming(by: 0.2), captions.words.count)
        XCTAssertEqual(captions.words[0].start, first + 0.2, accuracy: 1e-9)
        XCTAssertEqual(captions.shiftTiming(by: -5), captions.words.count)
        XCTAssertEqual(captions.words[0].start, 0, "never before zero")
        XCTAssertEqual(captions.words[0].end - captions.words[0].start, 0.4, accuracy: 1e-9, "a word keeps its length")
        XCTAssertEqual(captions.shiftTiming(by: 0), 0)

        XCTAssertEqual(captions.replaceAll("valerant", with: "Valorant"), 1)
        XCTAssertTrue(captions.words.contains { $0.text == "Valorant" })
        XCTAssertEqual(captions.replaceAll("valerant", with: "Valorant"), 0)
        XCTAssertEqual(captions.replaceAll("  ", with: "x"), 0)

        XCTAssertEqual(captions.addLaughEmoji(), 2, "hahaha and lol")
        XCTAssertTrue(captions.words.contains { $0.text == "hahaha 😂" })
        XCTAssertEqual(captions.addLaughEmoji(), 0, "not twice")
        XCTAssertFalse(captions.words.contains { $0.text.hasPrefix("went") && $0.text.contains("😂") })
    }

    func testShadowPresetsAndStyleSync() {
        var style = CaptionStyle.tiktok
        CaptionStyle.ShadowPreset.hard.apply(to: &style)
        XCTAssertTrue(CaptionStyle.ShadowPreset.hard.matches(style))
        XCTAssertFalse(CaptionStyle.ShadowPreset.soft.matches(style))
        CaptionStyle.ShadowPreset.none.apply(to: &style)
        XCTAssertEqual(style.text.shadowOpacity, 0)

        var doc = ProjectDocument(name: "P")
        var source = Fixtures.simpleTimeline()
        source.captions = track()
        source.captions?.style = .bold
        var split = Fixtures.simpleTimeline()
        split.layout = .splitScreen
        split.captions = track()
        split.captions?.style.positionY = 0.33
        var plain = Fixtures.simpleTimeline()
        plain.captions = track()
        let none = Fixtures.simpleTimeline()
        doc.timelines = [source, split, plain, none]
        XCTAssertEqual(doc.applyCaptionStyle(from: source.id), 2)
        XCTAssertEqual(doc.timelines[1].captions?.style.presetName, "Bold")
        XCTAssertEqual(doc.timelines[1].captions?.style.positionY, 0.33, "split layouts keep their caption height")
        XCTAssertEqual(doc.timelines[2].captions?.style.positionY, CaptionStyle.bold.positionY)
        XCTAssertNil(doc.timelines[3].captions)
        XCTAssertEqual(doc.applyCaptionStyle(from: UUID()), 0)
    }

    func testAIProvenanceAndMakeMine() {
        var clip = TimelineClip(name: "Replay", content: .media(assetID: Fixtures.assetID), start: 0, sourceDuration: 5, role: .graphic, aiGenerated: true)
        XCTAssertTrue(clip.aiPassDescription?.contains("Instant replays") ?? false)
        clip.name = "Meme: NO WAY"
        XCTAssertTrue(clip.aiPassDescription?.contains("Meme") ?? false)
        var sfx = TimelineClip(name: "Whoosh", content: .media(assetID: UUID()), start: 0, sourceDuration: 1, role: .soundEffect, aiGenerated: true)
        XCTAssertTrue(sfx.aiPassDescription?.contains("Sound effects") ?? false)
        sfx.aiGenerated = false
        XCTAssertNil(sfx.aiPassDescription, "your own clips say nothing")

        var mine = TimelineClip(name: "Gameplay", content: .media(assetID: Fixtures.assetID), start: 0, sourceDuration: 10)
        mine.transform.zoom.setKeyframe(at: 1, value: 1.2, aiGenerated: true)
        mine.transform.zoom.setKeyframe(at: 2, value: 1, aiGenerated: true)
        mine.transitionOut = ClipTransition(kind: .fadeToBlack, duration: 0.3, aiGenerated: true)
        XCTAssertTrue(mine.hasAIMarks)
        mine.stripAIFlags()
        XCTAssertFalse(mine.hasAIMarks)
        XCTAssertEqual(mine.transform.zoom.keyframes.count, 2, "values and keyframes stay")
        XCTAssertEqual(mine.transform.zoom.value(at: 1), 1.2)
        XCTAssertEqual(mine.transitionOut?.aiGenerated, false)
    }

    func testDeEsserTamesSibilanceAndLeavesTheVoice() {
        let rate = 48_000.0
        let n = Int(rate)
        var input = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / rate
            input[i] = 0.3 * Float(sin(2 * .pi * 300 * t))
            if t >= 0.5 && t < 0.6 { input[i] += 0.3 * Float(sin(2 * .pi * 7000 * t)) }
        }
        var channels = [input]
        AudioEnhanceChain.deEss(&channels, sampleRate: rate)
        func highBandRMS(_ x: [Float], from a: Double, to b: Double) -> Double {
            var hp = Biquad.highPass(frequency: 5000, sampleRate: rate)
            var y = x
            hp.process(&y)
            hp.process(&y)
            let slice = y[Int(a * rate)..<Int(b * rate)]
            return sqrt(slice.reduce(0.0) { $0 + Double($1 * $1) } / Double(slice.count))
        }
        func rms(_ x: [Float], from a: Double, to b: Double) -> Double {
            let slice = x[Int(a * rate)..<Int(b * rate)]
            return sqrt(slice.reduce(0.0) { $0 + Double($1 * $1) } / Double(slice.count))
        }
        let before = highBandRMS(input, from: 0.52, to: 0.6), after = highBandRMS(channels[0], from: 0.52, to: 0.6)
        XCTAssertLessThan(after, before * 0.5, "the 7 kHz burst comes down by at least 6 dB: \(before) → \(after)")
        XCTAssertEqual(rms(channels[0], from: 0.1, to: 0.4), rms(input, from: 0.1, to: 0.4), accuracy: 0.01, "the 300 Hz voice is untouched")
        var settings = AudioSettings()
        XCTAssertFalse(settings.needsProcessing)
        settings.deEss = true
        XCTAssertTrue(settings.needsProcessing)
        XCTAssertTrue(settings.enhanceFingerprint.contains("de"))
    }

    func testEQPresetsAndAudioOnlyExport() throws {
        XCTAssertEqual(EQSettings.presets.count, 3)
        XCTAssertTrue(EQSettings.warm.isEnabled)
        XCTAssertEqual(EQSettings.radio.presetName, "Radio")
        XCTAssertNil(EQSettings().presetName)
        var custom = EQSettings.clear
        custom.midGain += 1
        XCTAssertNil(custom.presetName)

        var settings = ExportSettings(preset: .youtube, outputDirectory: "/tmp/out")
        XCTAssertEqual(settings.outputExtension, "mp4")
        XCTAssertTrue(settings.filename(project: "P", clip: "C", index: 1).hasSuffix(".mp4"))
        settings.audioOnly = true
        XCTAssertEqual(settings.outputExtension, "m4a")
        XCTAssertTrue(settings.filename(project: "P", clip: "C", index: 1).hasSuffix(".m4a"))
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
        json.removeValue(forKey: "audioOnly")
        XCTAssertFalse(try JSONDecoder().decode(ExportSettings.self, from: JSONSerialization.data(withJSONObject: json)).audioOnly)
        XCTAssertTrue(try JSONDecoder().decode(ExportSettings.self, from: JSONEncoder().encode(settings)).audioOnly)
    }
}
