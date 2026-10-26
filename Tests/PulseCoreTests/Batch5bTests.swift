import XCTest
@testable import PulseCore

/// Roadmap batch 5b: snapshots (#185/#118), paste attributes (#165), default transition (#168), share copy
/// (#84), folder per project (#74), in → out export (#158), target readout (#179).
final class Batch5bTests: XCTestCase {
    func twoTouchingClips() -> Timeline {
        var t = Timeline.empty(name: "Cuts", canvas: .vertical1080)
        let a = TimelineClip(name: "A", content: .media(assetID: Fixtures.assetID), start: 0, sourceIn: 0, sourceDuration: 10)
        let b = TimelineClip(name: "B", content: .media(assetID: Fixtures.assetID), start: 10, sourceIn: 50, sourceDuration: 10)
        let c = TimelineClip(name: "C", content: .media(assetID: Fixtures.assetID), start: 25, sourceIn: 90, sourceDuration: 5)
        t.tracks[0].clips = [a, b, c]
        return t
    }

    // MARK: #185 / #118

    func testSnapshotsSaveRestoreAndCap() throws {
        var doc = ProjectDocument(name: "P")
        var timeline = twoTouchingClips()
        doc.timelines = [timeline]
        let saved = try XCTUnwrap(doc.snapshot(timelineID: timeline.id, name: "v1"))
        XCTAssertEqual(doc.snapshots(for: timeline.id).count, 1)
        timeline.tracks[0].clips.removeLast()
        doc.timelines[0] = timeline
        XCTAssertEqual(doc.timelines[0].allClips.count, 2)
        XCTAssertTrue(doc.restore(snapshotID: saved.id))
        XCTAssertEqual(doc.timelines[0].allClips.count, 3, "back to v1")
        XCTAssertEqual(doc.timelines[0].id, timeline.id, "same timeline, so the editor stays on it")
        let list = doc.snapshots(for: timeline.id)
        XCTAssertEqual(list.count, 2)
        XCTAssertTrue(list.contains { $0.automatic && $0.name.contains("Before restoring") }, "the live version was kept")
        XCTAssertFalse(doc.restore(snapshotID: UUID()))
        doc.deleteSnapshot(id: saved.id)
        XCTAssertEqual(doc.snapshots(for: timeline.id).count, 1)

        // The cap drops automatic snapshots before named ones.
        var crowded = ProjectDocument(name: "C")
        crowded.timelines = [timeline]
        crowded.snapshot(timelineID: timeline.id, name: "keep me", at: Date(timeIntervalSince1970: 0))
        for i in 0..<30 { crowded.snapshot(timelineID: timeline.id, name: "auto \(i)", automatic: true, at: Date(timeIntervalSince1970: Double(i + 1))) }
        XCTAssertEqual(crowded.snapshots(for: timeline.id).count, ProjectDocument.snapshotsPerTimeline)
        XCTAssertTrue(crowded.snapshots.contains { $0.name == "keep me" })
        XCTAssertFalse(crowded.snapshots.contains { $0.name == "auto 0" })

        // Old projects have no snapshots key.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as! [String: Any]
        json.removeValue(forKey: "snapshots")
        let decoded = try JSONDecoder().decode(ProjectDocument.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(decoded.snapshots.isEmpty)
        XCTAssertNil(decoded.timelines[0].targetDuration)
    }

    // MARK: #165

    func testPasteAttributesCopiesTheChosenParts() {
        var timeline = twoTouchingClips()
        var source = timeline.tracks[0].clips[0]
        source.transform.zoom = AnimatedDouble(1.3)
        source.color.saturation = 0.4
        source.audio.gainDB = -6
        source.audio.fadeIn = 1
        timeline.tracks[0].clips[0] = source
        var audioClip = TimelineClip(name: "A1", content: .media(assetID: Fixtures.assetID), start: 10, sourceIn: 50, sourceDuration: 10)
        audioClip.audio.fadeOut = 0.5
        timeline.tracks[3].clips = [audioClip]
        let targetID = timeline.tracks[0].clips[1].id
        let attributes = ClipAttributes(from: source)
        XCTAssertEqual(attributes.sourceName, "A")

        XCTAssertEqual(timeline.paste(attributes, onto: [targetID], parts: .look), 1)
        let target = timeline.tracks[0].clips[1]
        XCTAssertEqual(target.transform.zoom.value(at: 0), 1.3)
        XCTAssertEqual(target.color.saturation, 0.4)
        XCTAssertEqual(target.audio.gainDB, 0, "look only")

        XCTAssertEqual(timeline.paste(attributes, onto: [targetID, audioClip.id], parts: .audio), 2)
        XCTAssertEqual(timeline.tracks[0].clips[1].audio.gainDB, -6)
        XCTAssertEqual(timeline.tracks[3].clips[0].audio.gainDB, -6)
        XCTAssertEqual(timeline.tracks[3].clips[0].audio.fadeOut, 0.5, "the target keeps its own fades")
        XCTAssertEqual(timeline.tracks[3].clips[0].transform.zoom.value(at: 0), 1, "no look on an audio track")
        XCTAssertEqual(timeline.paste(attributes, onto: [audioClip.id], parts: .look), 0)
        XCTAssertEqual(ClipAttributes.Parts.look.displayName, "transform, style, color, effects")
    }

    // MARK: #168

    func testDefaultTransitionLandsOnTouchingEdgesOnly() {
        var timeline = twoTouchingClips()
        let ids = timeline.tracks[0].clips.map(\.id)
        let dissolve = ClipTransition(kind: .crossDissolve, duration: 0.4)
        XCTAssertEqual(timeline.addTransition(dissolve, toEdgesOf: [ids[1]]), 1, "B touches A; the gap to C gets nothing")
        XCTAssertEqual(timeline.tracks[0].clips[0].transitionOut, dissolve)
        XCTAssertEqual(timeline.tracks[0].clips[1].transitionIn, dissolve)
        XCTAssertNil(timeline.tracks[0].clips[1].transitionOut)
        XCTAssertEqual(timeline.addTransition(dissolve, toEdgesOf: [ids[0]]), 0, "already there")
        let point = timeline.editPoint(near: 10.2)
        XCTAssertEqual(point?.outgoing, ids[0])
        XCTAssertEqual(point?.incoming, ids[1])
        XCTAssertNil(timeline.editPoint(near: 25.1), "C starts after a gap: not a cut")
        XCTAssertNil(timeline.editPoint(near: 5))
    }

    // MARK: #84

    func testShareCopyFitsEachPlatform() {
        let copy = ClipCopy(titles: ["NAH THIS CANNOT BE REAL 😭"], shortsTitle: "", tiktokCaption: "", instagramCaption: "",
                            hashtags: ["#funny", "#gaming", "#clips", "#shorts", "#reaction", "#hype", "#fail"])
        let shorts = ShareCopy.text(for: .shorts, title: String(repeating: "A", count: 120), copy: copy, tags: [])
        XCTAssertLessThanOrEqual(shorts.count, 100)
        XCTAssertTrue(shorts.hasSuffix(" #shorts"))
        let tiktok = ShareCopy.text(for: .tiktok, title: "NAH THIS CANNOT BE REAL 😭", copy: copy, tags: [])
        XCTAssertTrue(tiktok.hasPrefix("Nah this cannot be real"), tiktok)
        XCTAssertEqual(tiktok.components(separatedBy: "#").count - 1, 5)
        XCTAssertFalse(tiktok.contains("#shorts"))
        let x = ShareCopy.text(for: .x, title: String(repeating: "word ", count: 80), copy: copy, tags: [])
        XCTAssertLessThanOrEqual(x.count, 280)
        XCTAssertEqual(x.components(separatedBy: "#").count - 1, 2)
        let reels = ShareCopy.text(for: .reels, title: "My Clip Title", copy: copy, tags: [])
        XCTAssertTrue(reels.hasPrefix("My Clip Title\n\n"), "mixed case stays as written")
        XCTAssertTrue(reels.contains("#reels"))
        // No copy yet: the tags provide hashtags.
        let bare = ShareCopy.text(for: .tiktok, title: "hi", copy: .empty, tags: [.funny, .gaming])
        XCTAssertTrue(bare.contains("#funny") && bare.contains("#gaming"))
    }

    // MARK: #74 / #158

    func testExportSettingsFolderAndJobRangeSurviveOldSaves() throws {
        var settings = ExportSettings(preset: .tiktok, outputDirectory: "/tmp/out")
        XCTAssertEqual(settings.outputDirectoryURL(projectName: "Stream: 10/26").path, "/tmp/out")
        settings.folderPerProject = true
        XCTAssertEqual(settings.outputDirectoryURL(projectName: "Stream: 10/26").lastPathComponent, ExportSettings.cleanComponent("Stream: 10/26"))
        XCTAssertFalse(settings.outputDirectoryURL(projectName: "Stream: 10/26").lastPathComponent.contains("/"))
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
        json.removeValue(forKey: "folderPerProject")
        let decoded = try JSONDecoder().decode(ExportSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(decoded.folderPerProject)
        XCTAssertEqual(decoded.presetID, settings.presetID)
        let round = try JSONDecoder().decode(ExportSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertTrue(round.folderPerProject)

        var job = ExportJob(projectID: UUID(), projectName: "P", timelineID: UUID(), timelineName: "T", settings: settings)
        var jobJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(job)) as! [String: Any]
        jobJSON.removeValue(forKey: "range")
        XCTAssertNil(try JSONDecoder().decode(ExportJob.self, from: JSONSerialization.data(withJSONObject: jobJSON)).range)
        job.range = TimeRange(start: 10, end: 20)
        XCTAssertEqual(try JSONDecoder().decode(ExportJob.self, from: JSONEncoder().encode(job)).range, TimeRange(start: 10, end: 20))
    }

    // MARK: #179

    func testEditMyVODRecordsItsTargetLength() {
        let duration: Seconds = 3000
        let analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: duration,
                                     audio: Fixtures.audio(duration: duration, spikes: Array(stride(from: 150.0, to: 2900, by: 230))),
                                     transcript: Fixtures.transcript(duration: duration), profile: .gameplay)
        let result = LongFormEditor.build(asset: Fixtures.mediaAsset(duration: duration), analysis: analysis)
        XCTAssertEqual(result.timeline.targetDuration, LongFormOptions().targetLength(forSource: duration))
        let round = try! JSONDecoder().decode(Timeline.self, from: JSONEncoder().encode(result.timeline))
        XCTAssertEqual(round.targetDuration, result.timeline.targetDuration)
    }
}
