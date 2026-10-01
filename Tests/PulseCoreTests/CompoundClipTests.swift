import XCTest
@testable import PulseCore

final class CompoundClipTests: XCTestCase {
    let asset = UUID()

    func makeTimeline() throws -> Timeline {
        var t = Timeline.empty(name: "Edit", canvas: .vertical1080)
        let v1 = t.tracks[0].id, t1 = t.tracks[2].id, a1 = t.tracks[3].id
        let g1 = UUID()
        try t.insert(TimelineClip(name: "A", content: .media(assetID: asset), start: 2, sourceIn: 10, sourceDuration: 4, linkGroup: g1), onTrack: v1)
        try t.insert(TimelineClip(name: "A audio", content: .media(assetID: asset), start: 2, sourceIn: 10, sourceDuration: 4, linkGroup: g1), onTrack: a1)
        try t.insert(TimelineClip(name: "B", content: .media(assetID: asset), start: 6, sourceIn: 30, sourceDuration: 3), onTrack: v1)
        try t.insert(TimelineClip(name: "Title", content: .text(TextElement(text: "HI")), start: 3, sourceDuration: 2), onTrack: t1)
        try t.insert(TimelineClip(name: "Outro", content: .media(assetID: asset), start: 12, sourceIn: 50, sourceDuration: 2), onTrack: v1)
        return t
    }

    func testMakeCompoundCollapsesSelectionAndKeepsTiming() throws {
        var t = try makeTimeline()
        let a = t.allClips.first { $0.name == "A" }!.id
        let b = t.allClips.first { $0.name == "B" }!.id
        let title = t.allClips.first { $0.name == "Title" }!.id
        let (nested, compoundID) = try CompoundEditor.makeCompound(in: &t, clipIDs: [a, b, title], name: "Intro")
        let compound = try XCTUnwrap(t.clip(id: compoundID))
        XCTAssertEqual(compound.content.compoundID, nested.id)
        XCTAssertEqual(compound.start, 2, accuracy: 1e-9)
        XCTAssertEqual(compound.duration, 7, accuracy: 1e-9)
        // A's linked audio went inside too; the outro stayed outside.
        XCTAssertEqual(nested.allClips.count, 4)
        XCTAssertNil(t.allClips.first { $0.name == "A audio" })
        XCTAssertNotNil(t.allClips.first { $0.name == "Outro" })
        XCTAssertEqual(nested.allClips.first { $0.name == "A" }?.start ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(nested.allClips.first { $0.name == "B" }?.start ?? -1, 4, accuracy: 1e-9)
        XCTAssertEqual(t.duration, 14, accuracy: 1e-9, "the edit's length doesn't change")
    }

    func testFlattenMapsIntoParentTimeAndTrimsToWindow() throws {
        var t = try makeTimeline()
        let ids = t.allClips.filter { ["A", "B", "Title"].contains($0.name) }.map(\.id)
        let (nested, compoundID) = try CompoundEditor.makeCompound(in: &t, clipIDs: ids, name: "Intro")
        // Trim 1 s off the compound's start and move it to 20 s.
        t.updateClip(id: compoundID) { c in
            c.sourceIn = 1
            c.sourceDuration = 5
            c.start = 20
        }
        let compound = t.clip(id: compoundID)!
        let pieces = CompoundEditor.flatten(compound, nested: nested)
        let a = try XCTUnwrap(pieces.first { $0.clip.name == "A" && $0.trackKind == .video }?.clip)
        XCTAssertEqual(a.start, 20, accuracy: 1e-9)
        XCTAssertEqual(a.sourceIn, 11, accuracy: 1e-9, "the trimmed second is skipped in the source too")
        XCTAssertEqual(a.duration, 3, accuracy: 1e-9)
        let b = try XCTUnwrap(pieces.first { $0.clip.name == "B" }?.clip)
        XCTAssertEqual(b.start, 23, accuracy: 1e-9)
        XCTAssertEqual(b.end, 25, accuracy: 1e-9, "cut off at the compound's end")
        XCTAssertTrue(pieces.allSatisfy { $0.clip.start >= 20 - 1e-9 && $0.clip.end <= 25 + 1e-9 })
    }

    func testBreakApartRestoresTheOriginalClips() throws {
        let original = try makeTimeline()
        var t = original
        let ids = t.allClips.filter { ["A", "B", "Title"].contains($0.name) }.map(\.id)
        let (nested, compoundID) = try CompoundEditor.makeCompound(in: &t, clipIDs: ids, name: "Intro")
        try CompoundEditor.breakApart(&t, clipID: compoundID, nested: nested)
        XCTAssertNil(t.allClips.first { $0.content.compoundID != nil })
        func summary(_ tl: Timeline) -> [String] {
            tl.allClips.map { String(format: "%@ %.3f %.3f %.3f", $0.name, $0.start, $0.sourceIn, $0.duration) }.sorted()
        }
        XCTAssertEqual(summary(t), summary(original))
        // Linked A/V pairs stay linked to each other after breaking apart.
        let a = t.allClips.first { $0.name == "A" }!, aAudio = t.allClips.first { $0.name == "A audio" }!
        XCTAssertNotNil(a.linkGroup)
        XCTAssertEqual(a.linkGroup, aAudio.linkGroup)
    }

    func testTrimStartCannotRevealBeforeCompoundContent() throws {
        var t = try makeTimeline()
        let ids = t.allClips.filter { ["A", "B", "Title"].contains($0.name) }.map(\.id)
        let (_, compoundID) = try CompoundEditor.makeCompound(in: &t, clipIDs: ids, name: "Intro")
        try t.trimStart(clipID: compoundID, to: 0)
        XCTAssertEqual(t.clip(id: compoundID)!.sourceIn, 0, accuracy: 1e-9)
        XCTAssertEqual(t.clip(id: compoundID)!.start, 2, accuracy: 1e-9)
    }

    func testDocumentFindsAndEditsCompoundTimelines() throws {
        var doc = ProjectDocument(name: "P")
        var t = try makeTimeline()
        let ids = t.allClips.filter { ["A", "B"].contains($0.name) }.map(\.id)
        let (nested, _) = try CompoundEditor.makeCompound(in: &t, clipIDs: ids, name: "Nested")
        doc.timelines = [t]
        doc.compounds = [nested]
        XCTAssertNotNil(doc.timeline(id: nested.id))
        XCTAssertTrue(doc.isCompound(nested.id))
        doc.editTimeline(id: nested.id) { $0.name = "Renamed" }
        XCTAssertEqual(doc.compounds[0].name, "Renamed")
        XCTAssertEqual(CompoundEditor.referencedCompounds(of: t, in: doc.compoundsByID), [nested.id])
        // Round-trips through the project file.
        let data = try ProjectStore.makeEncoder().encode(doc)
        let decoded = try ProjectStore.makeDecoder().decode(ProjectDocument.self, from: data)
        XCTAssertEqual(decoded.compounds.first?.id, nested.id)
        XCTAssertEqual(decoded.timelines[0].allClips.first { $0.content.compoundID != nil }?.content.compoundID, nested.id)
    }

    func testCompoundAtDoubleSpeedPlaysEverythingInsideTwiceAsFast() throws {
        var t = try makeTimeline()
        let ids = t.allClips.filter { ["A", "B", "Title"].contains($0.name) }.map(\.id)
        let (nested, compoundID) = try CompoundEditor.makeCompound(in: &t, clipIDs: ids, name: "Intro")
        try t.setSpeed(clipID: compoundID, speed: 2)
        let compound = try XCTUnwrap(t.clip(id: compoundID))
        XCTAssertEqual(compound.duration, 3.5, accuracy: 1e-9)
        XCTAssertEqual(t.allClips.first { $0.name == "Outro" }?.start ?? 0, 8.5, accuracy: 1e-9, "later clips ripple in")
        let pieces = CompoundEditor.flatten(compound, nested: nested)
        let b = try XCTUnwrap(pieces.first { $0.clip.name == "B" }?.clip)
        // B started 4 s into the compound → 2 s at double speed; still shows source 30…33.
        XCTAssertEqual(b.start, 2 + 2, accuracy: 1e-9)
        XCTAssertEqual(b.speed, 2, accuracy: 1e-9)
        XCTAssertEqual(b.sourceRange, TimeRange(start: 30, end: 33))
        XCTAssertEqual(b.end, compound.end, accuracy: 1e-9)
        // Breaking apart keeps the faster timing.
        try CompoundEditor.breakApart(&t, clipID: compoundID, nested: nested)
        XCTAssertEqual(t.allClips.first { $0.name == "B" }?.speed ?? 0, 2, accuracy: 1e-9)
    }
}
