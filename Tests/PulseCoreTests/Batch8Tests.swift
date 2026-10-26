import XCTest
@testable import PulseCore

/// Roadmap batch 8: hook variants (#89), length preview (#88), chapter lower-thirds (#91), hook title from the
/// transcript (#124), speed ramp (#80), to-do markers (#161), timecode styles (#180), edit decisions sync (#62).
final class Batch8Tests: XCTestCase {
    func stream() -> (MediaAsset, MediaAnalysis) {
        let duration: Seconds = 3000
        let spikes = Array(stride(from: 150.0, to: 2900, by: 230))
        var special: [(Seconds, String)] = []
        for s in spikes { for k in 0..<4 { special.append((s + 1 + Double(k) * 0.5, "hahaha")) } }
        let analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: duration,
                                     audio: Fixtures.audio(duration: duration, spikes: spikes),
                                     transcript: Fixtures.transcript(duration: duration, special: special), profile: .gameplay)
        return (Fixtures.mediaAsset(duration: duration), analysis)
    }

    func testPlanOffersHookVariantsAndPreviewsLengths() {
        let (_, analysis) = stream()
        let plan = LongFormEditor.planMoments(analysis: analysis, options: LongFormOptions())
        XCTAssertFalse(plan.hookCandidates.isEmpty)
        XCTAssertLessThanOrEqual(plan.hookCandidates.count, 3)
        XCTAssertTrue(plan.hookCandidates.allSatisfy { plan.selected.contains($0) }, "hooks come from the kept moments")
        XCTAssertEqual(plan.hookCandidates.first, plan.hook, "the suggested hook is the first variant")
        let shorter = plan.selection(forLength: plan.target * 0.5)
        let longer = plan.selection(forLength: plan.target * 1.5)
        XCTAssertLessThan(plan.keptLength(shorter), plan.keptLength(longer))
        XCTAssertTrue(shorter.isSubset(of: longer), "a longer video keeps everything a shorter one does")
        XCTAssertLessThanOrEqual(plan.keptLength(shorter), plan.target * 0.5 + 60)
    }

    func testChapterTitlesAndHookWords() {
        let (asset, analysis) = stream()
        var options = LongFormOptions()
        options.chapterTitles = true
        let result = LongFormEditor.build(asset: asset, analysis: analysis, options: options)
        let cards = result.timeline.tracks[1].clips.filter { $0.name == "Chapter Title" }
        XCTAssertFalse(cards.isEmpty, result.report)
        XCTAssertTrue(cards.allSatisfy { $0.duration < 3 && $0.transform.positionY.value(at: 0) > 0.7 })
        for (a, b) in zip(cards, cards.dropFirst()) { XCTAssertGreaterThanOrEqual(b.start - a.start, 6) }
        let hookEnd = result.timeline.tracks[0].clips[0].end
        XCTAssertTrue(cards.allSatisfy { $0.start >= hookEnd - 0.01 }, "never over the hook")
        let plain = LongFormEditor.build(asset: asset, analysis: analysis)
        XCTAssertFalse(plain.timeline.tracks[1].clips.contains { $0.name == "Chapter Title" })
        if let hookTitle = plain.timeline.tracks[1].clips.first(where: { $0.name == "Hook Title" }), case .text(let element) = hookTitle.content {
            XCTAssertFalse(element.text.isEmpty)
        }
    }

    func testSpeedRampSplitsAroundThePayoff() throws {
        var timeline = Fixtures.simpleTimeline(clipDuration: 60)   // source 100…160
        let assetID = timeline.tracks[0].clips[0].content.assetID!
        let before = timeline.duration
        XCTAssertTrue(EditPolish.speedRamp(&timeline, assetID: assetID, payoffAtSource: 130))
        let ramps = timeline.tracks[0].clips.filter { $0.name == "Ramp" }
        XCTAssertEqual(ramps.count, 2)
        XCTAssertEqual(ramps[0].speed, 0.9, accuracy: 1e-9)
        XCTAssertEqual(ramps[1].speed, 1.1, accuracy: 1e-9)
        XCTAssertEqual(ramps[0].sourceDuration, 1.2, accuracy: 1e-6)
        XCTAssertEqual(ramps[1].sourceDuration, 0.8, accuracy: 1e-6)
        XCTAssertEqual(timeline.duration, before - 1.2 - 0.8 + 1.2 / 0.9 + 0.8 / 1.1, accuracy: 1e-6)
        XCTAssertTrue(EditQualityCheck.blackGaps(in: timeline.tracks[0].clips).isEmpty)
        XCTAssertEqual(timeline.tracks[3].clips.filter { $0.name == "Ramp" }.count, 2, "linked audio follows")
        XCTAssertFalse(EditPolish.speedRamp(&timeline, assetID: assetID, payoffAtSource: 100.5), "no room before the payoff")
        var settings = AISettings()
        settings.speedRamp = true
        XCTAssertTrue(ShortBuildOptions(settings: settings).speedRamp)
        XCTAssertFalse(ShortBuildOptions().speedRamp)
    }

    func testToDoMarkersShowUpInTheEditCheck() {
        var timeline = Fixtures.simpleTimeline(clipDuration: 30)
        timeline.markers = [Marker(time: 2, name: "TODO fix the zoom", color: .red), Marker(time: 5, name: "Chapter 1", color: .blue),
                            Marker(time: 8, name: "Hmm", note: "todo: check audio", color: .blue)]
        let report = EditQualityCheck.run(&timeline, autofix: false)
        let todo = report.issues.first { $0.title == "To-do markers" }
        XCTAssertNotNil(todo, "\(report.issues)")
        XCTAssertTrue(todo?.detail.hasPrefix("2 left") ?? false, todo?.detail ?? "")
        timeline.markers = []
        XCTAssertNil(EditQualityCheck.run(&timeline, autofix: false).issues.first { $0.title == "To-do markers" })
    }

    func testTimecodeStylesAndEditDecisionsSync() throws {
        XCTAssertEqual(Timecode.display(61.5, fps: 30, style: .seconds), "61.50 s")
        XCTAssertEqual(Timecode.display(1, fps: 30, style: .frames), "30 f")
        XCTAssertEqual(Timecode.display(61.5, fps: 30, style: .timecode), Timecode.string(61.5, fps: 30))
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded.timecodeStyle, .timecode)

        var doc = ProjectDocument(name: "P")
        var source = Fixtures.simpleTimeline()
        source.layout = .facecamCorner
        source.canvas.backgroundBlur = true
        source.aiFramingEnabled = false
        var other = Fixtures.simpleTimeline()
        other.layout = .fullFrame
        doc.timelines = [source, other]
        XCTAssertEqual(doc.applyEditDecisions(from: source.id), 1)
        XCTAssertEqual(doc.timelines[1].layout, .facecamCorner)
        XCTAssertEqual(doc.timelines[1].canvas.backgroundBlur, true)
        XCTAssertFalse(doc.timelines[1].aiFramingEnabled)
        XCTAssertEqual(doc.applyEditDecisions(from: UUID()), 0)
    }
}
