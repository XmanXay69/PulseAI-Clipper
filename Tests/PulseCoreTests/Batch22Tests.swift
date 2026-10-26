import XCTest
@testable import PulseCore

/// Roadmap batch 22: brand palette and typeface on cards (#364, #370), reference "last used" (#366).
final class Batch22Tests: XCTestCase {
    func testPaletteAndTypefaceLandOnCards() throws {
        var timeline = Fixtures.simpleTimeline(clipDuration: 60)
        let words = [TranscriptWord(text: "hi", start: 100, end: 100.3)]
        timeline.captions = CaptionTrack.make(from: Transcript(language: "en", words: words, source: .demo), range: TimeRange(start: 100, end: 160),
                                              assetID: Fixtures.assetID, style: .tiktok, emphasize: false)
        let t1 = timeline.tracks.firstIndex { $0.kind == .text }!
        timeline.tracks[t1].clips.append(TimelineClip(name: "Title Card", content: .text(TextElement(text: "ROUND 2")), start: 5, sourceDuration: 2, aiGenerated: true))
        timeline.tracks[t1].clips.append(TimelineClip(name: "Lower Third", content: .text(TextElement(text: "mine")), start: 10, sourceDuration: 2))
        EditPolish.addEndScreen(&timeline, length: 5, handle: "xay")
        var kit = BrandKit()
        kit.palette = [RGBAColor(hex: "#FF00AA")!, RGBAColor(hex: "#112233")!, RGBAColor(hex: "#222244")!]
        kit.fontName = "Montserrat"
        XCTAssertTrue(kit.hasAnything)
        BrandKitApplier.apply(kit, assets: BrandKitAssets(), to: &timeline, longForm: true)
        let card = timeline.tracks[t1].clips.first { $0.name == "Title Card" }!
        guard case .text(let element) = card.content else { return XCTFail() }
        XCTAssertEqual(element.style.color, kit.palette[0])
        XCTAssertEqual(element.style.strokeColor, kit.palette[1])
        XCTAssertEqual(element.style.fontName, "Montserrat")
        let mine = timeline.tracks[t1].clips.first { $0.name == "Lower Third" }!
        if case .text(let e) = mine.content { XCTAssertNotEqual(e.style.color, kit.palette[0], "your own text keeps its colour") }
        let slate = timeline.allClips.first { $0.name == "End Screen" }!
        if case .solid(let c) = slate.content { XCTAssertEqual(c, kit.palette[2]) } else { XCTFail("end screen slate") }
        XCTAssertEqual(timeline.captions?.style.text.fontName, "Montserrat")
        let decoded = try JSONDecoder().decode(BrandKit.self, from: Data("{}".utf8))
        XCTAssertTrue(decoded.palette.isEmpty)
        XCTAssertEqual(decoded.fontName, "")
    }
}
