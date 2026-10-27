import XCTest
@testable import PulseCore

final class Batch50Tests: XCTestCase {
    // MARK: #495 — plugins

    func testManifestParsesValidatesAndResolvesParameters() throws {
        let data = try JSONEncoder().encode(PluginLoader.exampleEffect)
        let m = try XCTUnwrap(PluginLoader.parse(data))
        XCTAssertEqual(m.id, "example.warm-glow")
        XCTAssertEqual(m.kind, .effect)
        XCTAssertTrue(PluginLoader.problems(in: m).isEmpty)
        XCTAssertEqual(m.defaultParameters["glow"], 0.4)
        let resolved = PluginLoader.resolve(m.filters![0], values: ["glow": 0.9], manifest: m)
        XCTAssertEqual(resolved["inputIntensity"], 0.9)
        XCTAssertEqual(resolved["inputRadius"], 14)
        XCTAssertEqual(PluginLoader.resolve(m.filters![1], values: [:], manifest: m)["inputTargetNeutral"], 7000, "defaults fill in")
        XCTAssertTrue(PluginLoader.problems(in: PluginLoader.exampleSignal).isEmpty)
        // Problems: an unlisted filter, an undeclared parameter, a non-number, an empty signal command.
        var bad = PluginLoader.exampleEffect
        bad.filters = [PluginManifest.FilterStep(filter: "CIQRCodeGenerator", inputs: ["inputX": "$nope", "inputY": "abc"])]
        let problems = PluginLoader.problems(in: bad)
        XCTAssertEqual(problems.count, 3)
        XCTAssertTrue(problems.contains { $0.contains("allowed list") })
        var noCommand = PluginLoader.exampleSignal
        noCommand.command = []
        XCTAssertEqual(PluginLoader.problems(in: noCommand), ["a signal plugin needs a command"])
        XCTAssertNil(PluginLoader.parse(Data("not json".utf8)))
        XCTAssertFalse(PluginLoader.exampleSignalScript.isEmpty)
    }

    func testPluginEffectInstanceRoundTripsAndOldEffectsDecode() throws {
        let effect = EffectInstance(plugin: PluginLoader.exampleEffect)
        XCTAssertEqual(effect.kind, .plugin)
        XCTAssertEqual(effect.pluginID, "example.warm-glow")
        XCTAssertEqual(effect.displayName, "Warm Glow")
        XCTAssertEqual(effect.parameter("glow", at: 0), 0.4)
        XCTAssertEqual(effect.parameterValues(at: 0)["warmth"], 7000)
        let back = try JSONDecoder().decode(EffectInstance.self, from: JSONEncoder().encode(effect))
        XCTAssertEqual(back.pluginID, effect.pluginID)
        XCTAssertEqual(back.displayName, "Warm Glow")
        let blur = EffectInstance(kind: .gaussianBlur)
        XCTAssertEqual(blur.displayName, "Blur")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(blur)) as! [String: Any]
        json["pluginID"] = nil
        json["pluginName"] = nil
        let old = try JSONDecoder().decode(EffectInstance.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.pluginID)
        XCTAssertFalse(EffectKind.builtIn.contains(.plugin))
        XCTAssertEqual(EffectKind.builtIn.count, EffectKind.allCases.count - 1)
        XCTAssertTrue(EffectKind.plugin.defaultParameters.isEmpty)
    }

    // MARK: #486 — dubbing

    func testDubLinesFollowTheTimelineAndTheRateFitsTheSlot() {
        let asset = Fixtures.assetID
        var timeline = Timeline.empty(name: "Short", canvas: .vertical1080)
        // Two cuts of the same recording: 100–110 and 200–205, back to back.
        timeline.tracks[0].clips = [TimelineClip(name: "A", content: .media(assetID: asset), start: 0, sourceIn: 100, sourceDuration: 10),
                                    TimelineClip(name: "B", content: .media(assetID: asset), start: 10, sourceIn: 200, sourceDuration: 5)]
        var words: [CaptionWord] = []
        for (i, w) in ["Hola", "a", "todos."].enumerated() { words.append(CaptionWord(text: w, start: 101 + Double(i) * 0.4, end: 101.3 + Double(i) * 0.4)) }
        for (i, w) in ["Qué", "día"].enumerated() { words.append(CaptionWord(text: w, start: 105 + Double(i) * 0.4, end: 105.3 + Double(i) * 0.4)) }
        for (i, w) in ["Adiós", "ya"].enumerated() { words.append(CaptionWord(text: w, start: 201 + Double(i) * 0.4, end: 201.3 + Double(i) * 0.4, speaker: 1)) }
        let track = CaptionTrack(sourceAssetID: asset, words: words, style: .tiktok)
        let lines = DubPlanner.lines(from: track, in: timeline)
        XCTAssertEqual(lines.map(\.text), ["Hola a todos.", "Qué día", "Adiós ya"])
        XCTAssertEqual(lines[0].start, 1, accuracy: 0.001, "timeline time, not source time")
        XCTAssertEqual(lines[1].start, 5, accuracy: 0.001)
        XCTAssertEqual(lines[2].start, 11, accuracy: 0.001)
        XCTAssertEqual(lines[2].speaker, 1)
        XCTAssertEqual(lines[0].wordCount, 3)
        XCTAssertEqual(DubPlanner.rate(wordCount: 27, seconds: 10), 0.5, accuracy: 0.01)
        XCTAssertEqual(DubPlanner.rate(wordCount: 60, seconds: 10), 0.62, "brisk at most")
        XCTAssertEqual(DubPlanner.rate(wordCount: 2, seconds: 10), 0.42, "unhurried at least")
        XCTAssertEqual(DubPlanner.rate(wordCount: 0, seconds: 10), 0.5)
    }

    func testPlacingADubAddsATrackAndLowersTheOriginalVoice() {
        var timeline = Timeline.empty(name: "Short", canvas: .vertical1080)
        let voice = TimelineClip(name: "Mic", content: .media(assetID: Fixtures.assetID), start: 0, sourceDuration: 20, role: .microphone)
        let music = TimelineClip(name: "Bed", content: .media(assetID: UUID()), start: 0, sourceDuration: 20, role: .music)
        timeline.tracks[3].clips = [voice]
        timeline.tracks[4].clips = [music]
        let before = timeline.tracks.count
        let dub = UUID()
        let lowered = DubPlanner.place(&timeline, dubAssetID: dub, duration: 20, language: "es")
        XCTAssertEqual(lowered, 1)
        XCTAssertEqual(timeline.tracks.count, before + 1)
        let dubTrack = timeline.tracks.last!
        XCTAssertEqual(dubTrack.kind, .audio)
        XCTAssertTrue(dubTrack.name.contains("Dub (es)"))
        XCTAssertEqual(dubTrack.clips.first?.content, .media(assetID: dub))
        XCTAssertEqual(dubTrack.clips.first?.role, .microphone)
        XCTAssertEqual(timeline.tracks[3].clips[0].audio.gainDB, -18)
        XCTAssertEqual(timeline.tracks[4].clips[0].audio.gainDB, 0, "music is left alone")
    }
}
