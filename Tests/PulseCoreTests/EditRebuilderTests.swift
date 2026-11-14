import XCTest
@testable import PulseCore

/// #1101: one pass of an edit made again with new settings, the rest left alone.
final class EditRebuilderTests: XCTestCase {
    private func recording() -> (MediaAsset, MediaAnalysis) {
        let duration: Seconds = 3000
        let analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: duration,
                                     audio: Fixtures.audio(duration: duration, spikes: Array(stride(from: 150.0, to: 2900, by: 230))),
                                     transcript: Fixtures.transcript(duration: duration), profile: .gameplay)
        return (Fixtures.mediaAsset(duration: duration), analysis)
    }

    private func aiZooms(_ timeline: Timeline) -> Int {
        timeline.tracks.filter { $0.kind == .video }.flatMap(\.clips).reduce(0) { $0 + PlaybookCoach.zoomArrivals(of: $1, aiOnly: true) }
    }

    private func popUps(_ timeline: Timeline) -> [TimelineClip] {
        timeline.allClips.filter { clip in
            guard clip.aiGenerated, case .text = clip.content else { return false }
            return true
        }
    }

    func testOnlyTheZoomsChangeWhenTheZoomsAreRedoneInAnotherStyle() throws {
        let (asset, analysis) = recording()
        let calm = EditorPlaybook.commentary.styled(LongFormOptions())
        var edit = LongFormEditor.build(asset: asset, analysis: analysis, options: calm).timeline
        let cutBefore = edit.tracks[0].clips.map { [$0.start, $0.duration, $0.sourceIn] }
        let popUpsBefore = popUps(edit).map(\.start)
        let captionsBefore = edit.captions
        let zoomsBefore = aiZooms(edit)

        // The same cut, zoomed the Retention cut way: more of them, and they snap.
        let fast = EditorPlaybook.retention.styled(LongFormOptions())
        let report = EditRebuilder.rebuild(.zooms, in: &edit, asset: asset, analysis: analysis, options: fast)
        XCTAssertEqual(report.pass, .zooms)
        XCTAssertEqual(report.removed, zoomsBefore)
        XCTAssertEqual(report.added, aiZooms(edit))
        XCTAssertGreaterThan(report.added, zoomsBefore, "the fast style zooms more often than the calm one")
        XCTAssertLessThan(PlaybookCoach.zoomArrivals(in: edit).filter { $0 > 0 }.max() ?? 9, 0.35, "and its zooms snap in")
        // Nothing else moved.
        XCTAssertEqual(edit.tracks[0].clips.map { [$0.start, $0.duration, $0.sourceIn] }, cutBefore)
        XCTAssertEqual(popUps(edit).map(\.start), popUpsBefore)
        XCTAssertEqual(edit.captions, captionsBefore)
        XCTAssertTrue(report.summary.hasPrefix("Zooms redone"))
    }

    func testANewZoomLandsOnTheSameInstantOfTheRecordingAfterTheEditWasTrimmedByHand() throws {
        let (asset, analysis) = recording()
        let options = EditorPlaybook.retention.styled(LongFormOptions())
        let built = LongFormEditor.build(asset: asset, analysis: analysis, options: options).timeline
        // Where each zoom peaks, in the recording's own time.
        func peaks(_ timeline: Timeline) -> [Seconds] {
            var out: [Seconds] = []
            for clip in timeline.tracks[0].clips {
                for (a, b) in zip(clip.transform.zoom.keyframes, clip.transform.zoom.keyframes.dropFirst()) where a.aiGenerated && b.value > a.value + 1e-3 {
                    out.append(clip.sourceTime(atTimeline: clip.start + b.time))
                }
            }
            return out.sorted()
        }
        // Cut 40 s out of the middle by hand, then redo the zooms with the same settings.
        var trimmed = built
        let middle = built.duration / 2
        trimmed.rippleDelete(range: TimeRange(start: middle - 20, end: middle + 20))
        let before = peaks(trimmed)
        EditRebuilder.rebuild(.zooms, in: &trimmed, asset: asset, analysis: analysis, options: options)
        let after = peaks(trimmed)
        XCTAssertFalse(after.isEmpty)
        // Every zoom that survived the trim comes back on the instant of the recording it was on.
        let matched = before.filter { was in after.contains { abs($0 - was) < 0.3 } }
        XCTAssertGreaterThan(Double(matched.count), Double(before.count) * 0.7, "\(before.count) before, \(after.count) after, \(matched.count) on the same instants")
        // And none lands on a part of the recording the edit no longer holds.
        let held = trimmed.tracks[0].clips.map(\.sourceRange)
        XCTAssertTrue(after.allSatisfy { peak in held.contains { $0.start - 0.01 <= peak && peak <= $0.end + 0.01 } })
    }

    func testPopUpsSoundEffectsTheCaptionLookAndTheTeaseAreEachTheirOwnPass() throws {
        let (asset, analysis) = recording()
        var plain = LongFormOptions()
        plain.memes = false
        var edit = LongFormEditor.build(asset: asset, analysis: analysis, options: plain).timeline
        XCTAssertTrue(popUps(edit).filter { $0.name.hasPrefix("Meme") }.isEmpty)
        let zooms = aiZooms(edit)

        // Pop-ups on: they arrive without the zooms being touched.
        var withMemes = plain
        withMemes.memes = true
        let memes = EditRebuilder.rebuild(.popUps, in: &edit, asset: asset, analysis: analysis, options: withMemes)
        XCTAssertGreaterThan(popUps(edit).filter { $0.name.hasPrefix("Meme") }.count, 0, memes.summary)
        XCTAssertEqual(aiZooms(edit), zooms)
        // A text clip of your own survives a redo; PULSE's own are replaced, not doubled.
        edit.tracks[1].clips.append(TimelineClip(name: "My title", content: .text(TextElement(text: "MINE")), start: 3, sourceIn: 0, sourceDuration: 2))
        let count = popUps(edit).count
        EditRebuilder.rebuild(.popUps, in: &edit, asset: asset, analysis: analysis, options: withMemes)
        XCTAssertEqual(popUps(edit).count, count)
        XCTAssertTrue(edit.allClips.contains { $0.name == "My title" })

        // The caption look follows the style; the words stay.
        let words = edit.captions?.words
        let look = EditRebuilder.rebuild(.captionLook, in: &edit, asset: asset, analysis: analysis, options: EditorPlaybook.retention.styled(LongFormOptions()))
        XCTAssertEqual(look.added, 1)
        XCTAssertEqual(edit.captions?.words, words)

        // The tease is planted, and planted again rather than twice.
        let tease = EditRebuilder.rebuild(.tease, in: &edit, asset: asset, analysis: analysis, options: withMemes)
        if tease.added == 1 {
            XCTAssertEqual(edit.openLoops?.count, 1)
            let again = EditRebuilder.rebuild(.tease, in: &edit, asset: asset, analysis: analysis, options: withMemes)
            XCTAssertEqual(again.removed, 1)
            XCTAssertEqual(edit.allClips.filter { $0.name == OpenLoopBuilder.clipName }.count, 1)
            XCTAssertTrue(OpenLoopBuilder.unpaid(in: edit).isEmpty)
        }
        // Every pass has a name and a symbol for the menu.
        for pass in EditPass.allCases { XCTAssertFalse(pass.displayName.isEmpty); XCTAssertFalse(pass.symbolName.isEmpty) }
        // An edit that holds none of the recording's moments is left as it is.
        var empty = Timeline.empty(name: "Empty", canvas: .vertical1080)
        XCTAssertEqual(EditRebuilder.rebuild(.zooms, in: &empty, asset: asset, analysis: analysis, options: plain).added, 0)
    }
}
