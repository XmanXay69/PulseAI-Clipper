import XCTest
@testable import PulseCore

/// Roadmap batch 18: relinking (#6, #7), import sidecars (#13, #14), replace a clip's media (#164), the
/// cold-open card (#90), preferred sound effects (#105), the status board's stages (#474).
final class Batch18Tests: XCTestCase {
    func testRelinkerMatchesByNameThenSize() {
        var a = Fixtures.mediaAsset(duration: 100)
        a.path = "/old/stream.mp4"
        a.metadata.fileSize = 5_000
        var b = Fixtures.mediaAsset(duration: 10)
        b.id = UUID()
        b.path = "/old/cam.mov"
        b.metadata.fileSize = 0
        var c = Fixtures.mediaAsset(duration: 10)
        c.id = UUID()
        c.path = "/old/missing.mp4"
        let files = [MediaRelinker.Candidate(path: "/new/a/stream.mp4", size: 7_000), MediaRelinker.Candidate(path: "/new/b/Stream.MP4", size: 5_000),
                     MediaRelinker.Candidate(path: "/new/cam.mov", size: 99)]
        let matches = MediaRelinker.matches(missing: [a, b, c], files: files)
        XCTAssertEqual(matches[a.id], "/new/b/Stream.MP4", "the same size wins among same names, case ignored")
        XCTAssertEqual(matches[b.id], "/new/cam.mov")
        XCTAssertNil(matches[c.id])
        let roots = MediaRelinker.searchRoots(for: a, projectFolder: "/Users/me/PULSE/Stream.pulse", lastImportFolder: "/Volumes/SSD/VODs")
        XCTAssertEqual(roots, ["/old", "/", "/Users/me/PULSE/Stream.pulse", "/Users/me/PULSE", "/Volumes/SSD/VODs"].filter { $0 != "/" })
    }

    func testSidecarsComeAlongWithTheRecording() {
        let video = URL(fileURLWithPath: "/vods/night1.mp4")
        let folder: [URL] = ["night1.mp4", "night1.srt", "night1-chat.json", "night2.vtt", "notes.txt", "night1.json"].map { URL(fileURLWithPath: "/vods/" + $0) }
        let plan = ImportPlan.make(urls: [video], existingPaths: [], siblings: { _ in folder })
        XCTAssertEqual(plan.items.map(\.url), [video])
        XCTAssertEqual(plan.transcripts.map(\.lastPathComponent), ["night1.srt"])
        XCTAssertEqual(Set(plan.chatLogs.map(\.lastPathComponent)), ["night1-chat.json", "night1.json"])
        // A transcript dropped together with the video isn't listed twice.
        let both = ImportPlan.make(urls: [video, URL(fileURLWithPath: "/vods/night1.srt")], existingPaths: [], siblings: { _ in folder })
        XCTAssertEqual(both.transcripts.count, 1)
        XCTAssertTrue(ImportPlan.make(urls: [video], existingPaths: [], siblings: { _ in [] }).chatLogs.isEmpty)
    }

    func testReplacingAClipKeepsItsPlace() {
        var timeline = Fixtures.simpleTimeline(clipDuration: 30)   // V1 + linked A1, source 100…130
        let clip = timeline.tracks[0].clips[0]
        let other = UUID()
        XCTAssertTrue(timeline.replaceContent(clipID: clip.id, assetID: other, assetDuration: 600, name: "Other", hasAudio: true))
        let replaced = timeline.tracks[0].clips[0]
        XCTAssertEqual(replaced.content.assetID, other)
        XCTAssertEqual(replaced.name, "Other")
        XCTAssertEqual(replaced.start, 0)
        XCTAssertEqual(replaced.duration, 30, accuracy: 1e-9)
        XCTAssertEqual(replaced.sourceIn, 0)
        let audio = timeline.tracks[3].clips[0]
        XCTAssertEqual(audio.content.assetID, other, "linked sound follows")
        XCTAssertEqual(audio.linkGroup, replaced.linkGroup)
        // A silent, shorter file: the clip shrinks and the sound piece goes.
        var again = Fixtures.simpleTimeline(clipDuration: 30)
        let id = again.tracks[0].clips[0].id
        XCTAssertTrue(again.replaceContent(clipID: id, assetID: UUID(), assetDuration: 12, name: "Short", hasAudio: false))
        XCTAssertEqual(again.tracks[0].clips[0].duration, 12, accuracy: 1e-9)
        XCTAssertTrue(again.tracks[3].clips.isEmpty)
        XCTAssertFalse(again.replaceContent(clipID: UUID(), assetID: UUID(), assetDuration: 1, name: "x", hasAudio: true))
    }

    func testColdOpenCardSitsOverTheTeaser() {
        var timeline = Fixtures.simpleTimeline(clipDuration: 40)
        let assetID = timeline.tracks[0].clips[0].content.assetID!
        XCTAssertFalse(ColdOpenCard.add(&timeline, text: "WAIT"), "no teaser yet")
        XCTAssertTrue(EditPolish.coldOpen(&timeline, assetID: assetID, payoffAtSource: 125))
        XCTAssertTrue(ColdOpenCard.add(&timeline, text: ColdOpenCard.text(tags: [.fail], seed: 0)))
        let card = timeline.tracks.first { $0.kind == .text }!.clips.first { $0.name == ColdOpenCard.clipName }!
        XCTAssertEqual(card.start, 0.05, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(card.end, 1.6)
        if case .text(let element) = card.content { XCTAssertEqual(element.text, "OH NO…") } else { XCTFail() }
        XCTAssertFalse(ColdOpenCard.add(&timeline, text: "AGAIN"), "only once")
        XCTAssertEqual(ColdOpenCard.text(tags: [.question]), "GUESS WHAT HAPPENED")
        XCTAssertEqual(ColdOpenCard.text(tags: []), "WAIT FOR IT")
        XCTAssertTrue(ShortBuildOptions().coldOpenCard)
    }

    func testPreferredEffectsWinOverKeywords() {
        var impact = Fixtures.mediaAsset(duration: 1)
        impact.id = UUID(); impact.name = "Impact"; impact.role = .soundEffect; impact.tags = ["library:sfx.impact"]
        var boom = Fixtures.mediaAsset(duration: 1)
        boom.id = UUID(); boom.name = "Deep Boom"; boom.role = .soundEffect; boom.tags = ["library:sfx.boom"]
        let library = [impact, boom]
        XCTAssertEqual(ShortBuilder.pickSoundEffect(library, preferring: ["impact", "boom"])?.id, impact.id)
        XCTAssertEqual(ShortBuilder.pickSoundEffect(library, preferring: ["impact", "boom"], chosen: "deep boom")?.id, boom.id)
        XCTAssertEqual(ShortBuilder.pickSoundEffect(library, preferring: ["impact"], chosen: "sfx.boom")?.id, boom.id, "by library id too")
        XCTAssertEqual(ShortBuilder.pickSoundEffect(library, preferring: ["impact"], chosen: "Not Here")?.id, impact.id, "unknown choice falls back")
        let sounds = LongFormSounds(effects: library, preferred: ["hit": "Deep Boom"])
        XCTAssertEqual(sounds.effect(["impact", "boom"])?.id, boom.id)
        var settings = AISettings()
        settings.preferredEffects = ["whoosh": "Swoosh"]
        XCTAssertEqual(ShortBuildOptions(settings: settings).preferredEffects["whoosh"], "Swoosh")
        let decoded = try? JSONDecoder().decode(AISettings.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded?.preferredEffects, [:])
    }

    func testWorkflowStagesFollowContentsUntilPlaced() throws {
        var doc = ProjectDocument(name: "P")
        XCTAssertEqual(doc.summary.boardStage, .editing)
        doc.exportCount = 2
        XCTAssertEqual(doc.summary.boardStage, .exported)
        doc.workflowStage = .posted
        XCTAssertEqual(doc.summary.boardStage, .posted)
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(ProjectDocument.self, from: data)
        XCTAssertEqual(back.workflowStage, .posted)
        let old = try JSONDecoder().decode(ProjectDocument.self, from: JSONEncoder().encode(ProjectDocument(name: "Q")))
        XCTAssertNil(old.workflowStage)
        XCTAssertEqual(WorkflowStage.allCases.map(\.displayName), ["Editing", "Ready", "Exported", "Posted"])
    }
}
