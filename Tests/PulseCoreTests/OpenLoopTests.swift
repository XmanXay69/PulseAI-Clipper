import XCTest
@testable import PulseCore

/// #582: a tease in the first half minute that points at a real later moment, and a check that it is paid off.
final class OpenLoopTests: XCTestCase {
    private func recording() -> (MediaAsset, MediaAnalysis) {
        let duration: Seconds = 3000
        let analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: duration,
                                     audio: Fixtures.audio(duration: duration, spikes: Array(stride(from: 150.0, to: 2900, by: 230))),
                                     transcript: Fixtures.transcript(duration: duration), profile: .gameplay)
        return (Fixtures.mediaAsset(duration: duration), analysis)
    }

    func testEditMyVODPlantsATeaseForAMomentThatReallyLandsLate() throws {
        let (asset, analysis) = recording()
        var options = LongFormOptions()
        options.openLoop = true
        let result = LongFormEditor.build(asset: asset, analysis: analysis, options: options)
        let edit = result.timeline
        let loop = try XCTUnwrap(edit.openLoops?.first, result.report)
        let tease = try XCTUnwrap(edit.allClips.first { $0.id == loop.teaseClipID })
        XCTAssertEqual(tease.name, OpenLoopBuilder.clipName)
        XCTAssertLessThanOrEqual(tease.start, 26, "in the first half minute")
        XCTAssertGreaterThanOrEqual(tease.start, 6)
        XCTAssertTrue(loop.text.hasPrefix("COMING UP: "))
        // The promise is kept: the moment plays in the second half, well after the tease.
        let landed = try XCTUnwrap(OpenLoopBuilder.payoffTime(of: loop, in: edit))
        XCTAssertGreaterThanOrEqual(landed, max(edit.duration * 0.5, 60) - 0.01)
        XCTAssertTrue(OpenLoopBuilder.unpaid(in: edit).isEmpty)
        XCTAssertTrue(result.report.contains("a tease for a later moment"), result.report)
        // It survives a save, and an edit without the option has none.
        let saved = try JSONDecoder().decode(Timeline.self, from: JSONEncoder().encode(edit))
        XCTAssertEqual(saved.openLoops, edit.openLoops)
        XCTAssertNil(LongFormEditor.build(asset: asset, analysis: analysis).timeline.openLoops)
        // The styles built on a promise plant one; a calm one doesn't.
        XCTAssertTrue(EditorPlaybook.retention.styled(LongFormOptions()).openLoop)
        XCTAssertTrue(EditorPlaybook.story.styled(LongFormOptions()).openLoop)
        XCTAssertFalse(EditorPlaybook.commentary.styled(LongFormOptions()).openLoop)
    }

    func testCuttingThePromisedMomentIsCaughtAndTheCoachSaysSo() throws {
        let (asset, analysis) = recording()
        var options = LongFormOptions()
        options.openLoop = true
        var edit = LongFormEditor.build(asset: asset, analysis: analysis, options: options).timeline
        let loop = try XCTUnwrap(edit.openLoops?.first)
        let landed = try XCTUnwrap(OpenLoopBuilder.payoffTime(of: loop, in: edit))

        // Cut ten seconds around the promised moment out of the edit.
        edit.rippleDelete(range: TimeRange(start: max(0, landed - 5), end: min(edit.duration, landed + 5)))
        let unpaid = OpenLoopBuilder.unpaid(in: edit)
        XCTAssertEqual(unpaid.count, 1)
        XCTAssertTrue(unpaid[0].reason.contains("cut"), unpaid[0].reason)
        let review = EditCoach.review(edit, analysis: analysis)
        let told = try XCTUnwrap(review.suggestions.first { $0.id == "tease-unpaid" })
        XCTAssertEqual(told.fix, .removeTease)
        XCTAssertEqual(told.severity, .recommended)
        XCTAssertFalse(review.suggestions.contains { $0.id == "tease" }, "not offered a second tease while the first is broken")

        // Taking the tease off settles it, and so does deleting the tease by hand.
        var removed = edit
        OpenLoopBuilder.remove(from: &removed)
        XCTAssertNil(removed.openLoops)
        XCTAssertFalse(removed.allClips.contains { $0.name == OpenLoopBuilder.clipName })
        XCTAssertTrue(OpenLoopBuilder.unpaid(in: removed).isEmpty)
        var byHand = edit
        for i in byHand.tracks.indices { byHand.tracks[i].clips.removeAll { $0.id == loop.teaseClipID } }
        XCTAssertTrue(OpenLoopBuilder.unpaid(in: byHand).isEmpty, "a tease you deleted makes no promise")
    }

    func testALongVideoWithNoTeaseIsOfferedOneAndAShortOneIsNot() throws {
        let (asset, analysis) = recording()
        let plain = LongFormEditor.build(asset: asset, analysis: analysis)
        XCTAssertGreaterThan(plain.timeline.duration, 300)
        let offered = try XCTUnwrap(EditCoach.review(plain.timeline, analysis: analysis).suggestions.first { $0.id == "tease" })
        XCTAssertEqual(offered.fix, .plantTease)
        XCTAssertEqual(EditSuggestion.Fix.plantTease.buttonTitle, "Plant Tease")
        XCTAssertEqual(EditSuggestion.Fix.removeTease.buttonTitle, "Remove Tease")

        // Planting by hand from the plan: one tease, replaced by the next.
        var edit = plain.timeline
        let plan = try XCTUnwrap(OpenLoopBuilder.plan(timeline: edit, moments: plain.segments, assetID: asset.id))
        OpenLoopBuilder.plant(plan, in: &edit, assetID: asset.id)
        OpenLoopBuilder.plant(plan, in: &edit, assetID: asset.id)
        XCTAssertEqual(edit.allClips.filter { $0.name == OpenLoopBuilder.clipName }.count, 1)
        XCTAssertEqual(edit.openLoops?.count, 1)
        XCTAssertFalse(EditCoach.review(edit, analysis: analysis).suggestions.contains { $0.id == "tease" })

        // A short, or an edit under three minutes, needs no tease and gets no plan.
        let short = Fixtures.simpleTimeline(clipDuration: 30)
        XCTAssertNil(OpenLoopBuilder.plan(timeline: short, moments: plain.segments, assetID: asset.id))
        XCTAssertFalse(EditCoach.review(short, analysis: analysis).suggestions.contains { $0.id == "tease" })
        // What a moment is called follows what kind it is.
        XCTAssertEqual(OpenLoopBuilder.promise(for: [.gaming, .fail]), "THE WORST FAIL")
        XCTAssertEqual(OpenLoopBuilder.promise(for: [.reaction]), "THE BEST MOMENT")
    }
}
