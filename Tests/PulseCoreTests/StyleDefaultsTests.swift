import XCTest
@testable import PulseCore

/// #626 (a built-in style as the default for each kind of recording) and #627 (the same VOD in two styles).
final class StyleDefaultsTests: XCTestCase {
    func testTheSwitchIsOffUntilAskedAndThenFollowsTheRecording() throws {
        var settings = AISettings()
        XCTAssertFalse(settings.autoEditStyle, "edits keep PULSE's own way until the switch is on")
        XCTAssertNil(settings.defaultPlaybook(for: .gameplay))
        XCTAssertNil(settings.defaultPlaybook(for: .gameplay, format: .short))

        settings.autoEditStyle = true
        XCTAssertEqual(settings.defaultPlaybook(for: .gameplayWithFacecam)?.id, "retention")
        XCTAssertEqual(settings.defaultPlaybook(for: .podcast)?.id, "commentary")
        XCTAssertEqual(settings.defaultPlaybook(for: .talkingHead)?.id, "commentary")
        XCTAssertEqual(settings.defaultPlaybook(for: .unknown)?.id, "story")
        XCTAssertEqual(settings.defaultPlaybook(for: .podcast, format: .short)?.id, "short", "shorts get the short-form style whatever the recording")
        XCTAssertEqual(settings.editStyleID(for: .gameplay), "retention")
    }

    func testAKindCanBeGivenAnotherStyleOrPulsesOwn() throws {
        var settings = AISettings()
        settings.autoEditStyle = true
        settings.editStyleByProfile[ContentProfile.gameplay.rawValue] = "smooth"
        settings.editStyleByProfile[ContentProfile.podcast.rawValue] = AISettings.ownStyle
        XCTAssertEqual(settings.defaultPlaybook(for: .gameplay)?.id, "smooth")
        XCTAssertNil(settings.defaultPlaybook(for: .podcast), "this kind keeps PULSE's own way")
        XCTAssertEqual(settings.editStyleID(for: .podcast), AISettings.ownStyle)
        XCTAssertEqual(settings.defaultPlaybook(for: .gameplayWithFacecam)?.id, "retention", "other kinds are untouched")

        // A short-form style or a name that no longer exists can't be a long-form default.
        settings.editStyleByProfile[ContentProfile.gameplay.rawValue] = "short"
        XCTAssertEqual(settings.defaultPlaybook(for: .gameplay)?.id, "retention")
        XCTAssertEqual(settings.editStyleID(for: .gameplay), "retention")
        settings.editStyleByProfile[ContentProfile.gameplay.rawValue] = "gone"
        XCTAssertEqual(settings.defaultPlaybook(for: .gameplay)?.id, "retention")

        // The choice survives a save, and settings saved before this version read as off.
        let saved = try JSONDecoder().decode(AISettings.self, from: JSONEncoder().encode(settings))
        XCTAssertTrue(saved.autoEditStyle)
        XCTAssertEqual(saved.editStyleByProfile[ContentProfile.podcast.rawValue], AISettings.ownStyle)
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        json["autoEditStyle"] = nil
        json["editStyleByProfile"] = nil
        let older = try JSONDecoder().decode(AISettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(older.autoEditStyle)
        XCTAssertTrue(older.editStyleByProfile.isEmpty)
    }

    private func recording() -> (MediaAsset, MediaAnalysis) {
        let duration: Seconds = 3000
        let analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: duration,
                                     audio: Fixtures.audio(duration: duration, spikes: Array(stride(from: 150.0, to: 2900, by: 230))),
                                     transcript: Fixtures.transcript(duration: duration), profile: .gameplay)
        return (Fixtures.mediaAsset(duration: duration), analysis)
    }

    func testAnEditsRetentionCurveFollowsItsCutsAndRewardsChangesOfPicture() {
        let (asset, analysis) = recording()
        let signals = EngagementModel.compute(analysis: analysis)
        let edit = LongFormEditor.build(asset: asset, analysis: analysis).timeline
        let curve = RetentionPredictor.predict(edit: edit, signals: signals, assetID: asset.id)
        XCTAssertEqual(Double(curve.values.count), edit.duration, accuracy: 1.5)
        XCTAssertLessThanOrEqual(curve.values.first ?? 2, 1)
        XCTAssertGreaterThan(curve.atEnd, 0)
        XCTAssertLessThan(curve.atEnd, curve.values[0])
        XCTAssertTrue(zip(curve.values, curve.values.dropFirst()).allSatisfy { $0 >= $1 }, "viewers only leave")
        XCTAssertGreaterThan(curve.average, curve.atEnd)

        // The same picture with every zoom, pop-up and cut-in removed holds people a little less well.
        var bare = edit
        for ti in bare.tracks.indices {
            if bare.tracks[ti].kind == .text { bare.tracks[ti].clips = [] }
            for ci in bare.tracks[ti].clips.indices { bare.tracks[ti].clips[ci].transform.zoom = AnimatedDouble(1) }
        }
        let flat = RetentionPredictor.predict(edit: bare, signals: signals, assetID: asset.id)
        XCTAssertLessThanOrEqual(flat.atEnd, curve.atEnd)
        // No signals, or an empty edit: a flat line, not a crash.
        XCTAssertEqual(RetentionPredictor.predict(edit: Timeline(name: "Empty"), signals: signals).values, [1])
    }

    func testTheSameRecordingInTwoStylesGivesTwoDifferentEditsAndAVerdict() throws {
        let (asset, analysis) = recording()
        var base = LongFormOptions()
        base.minimumLength = 300
        base.maximumLength = 600
        let fast = StyleComparison.trial(.retention, asset: asset, analysis: analysis, base: base)
        let calm = StyleComparison.trial(.commentary, asset: asset, analysis: analysis, base: base)
        let own = StyleComparison.trial(nil, asset: asset, analysis: analysis, base: base)

        XCTAssertEqual(fast.id, "retention")
        XCTAssertEqual(fast.timeline.editStyle, "retention")
        XCTAssertEqual(calm.timeline.editStyle, "commentary")
        XCTAssertEqual(own.id, AISettings.ownStyle)
        XCTAssertNil(own.timeline.editStyle)
        XCTAssertEqual(own.name, "PULSE's own")
        // The length asked for is kept whatever the style's own video ran to.
        XCTAssertEqual(fast.options.minimumLength, 300)
        XCTAssertEqual(calm.options.maximumLength, 600)
        // The fast style changes the picture more often than the calm one.
        XCTAssertGreaterThan(fast.facts.zooms, calm.facts.zooms)
        XCTAssertFalse(fast.facts.summary.isEmpty)
        XCTAssertTrue(fast.facts.summary.contains("zoom"))
        XCTAssertTrue((0...100).contains(fast.score))
        XCTAssertGreaterThan(fast.retention.values.count, 10)

        let verdict = StyleComparison.verdict(fast, calm)
        XCTAssertFalse(verdict.headline.isEmpty)
        XCTAssertTrue(verdict.reasons.contains { $0.hasPrefix("Predicted average watched") })
        if let winner = verdict.winner { XCTAssertTrue([fast.id, calm.id].contains(winner)) }
        // Order doesn't change who wins, and a trial against itself is a draw.
        XCTAssertEqual(StyleComparison.verdict(calm, fast).winner, verdict.winner)
        let draw = StyleComparison.verdict(fast, fast)
        XCTAssertNil(draw.winner)
        XCTAssertTrue(draw.headline.hasPrefix("Too close to call"))
    }
}
