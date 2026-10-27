import XCTest
@testable import PulseCore

final class Batch31Tests: XCTestCase {
    func testJoinInOrderKeepsStoryOrder() {
        let a = LongFormSegment(range: TimeRange(start: 100, end: 130), payoff: 120, potential: 80, title: "Payoff", tags: [])
        let b = LongFormSegment(range: TimeRange(start: 10, end: 40), payoff: 20, potential: 60, title: "Setup", tags: [])
        let c = LongFormSegment(range: TimeRange(start: 35, end: 60), payoff: 50, potential: 70, title: "Overlaps setup", tags: [])
        let kept = LongFormEditor.joinInOrder([a, b, c])
        XCTAssertEqual(kept.map(\.title), ["Payoff", "Overlaps setup"], "the payoff stays first; the overlapping pair joins")
        XCTAssertEqual(kept[1].range, TimeRange(start: 10, end: 60))
        let sorted = LongFormEditor.merge([a, b, c], gap: 8)
        XCTAssertEqual(sorted.first?.range.start, 10, "the default still re-sorts")
        XCTAssertFalse(LongFormOptions().keepStoryOrder)
    }

    func testRetentionCurveFallsSlowerWhenLively() {
        let flat = RetentionPredictor.predict(excitement: [Float](repeating: 0.05, count: 600), step: 1)
        let lively = RetentionPredictor.predict(excitement: [Float](repeating: 0.9, count: 600), step: 1)
        XCTAssertEqual(flat.values.count, 600)
        XCTAssertLessThan(flat.value(at: 599), lively.value(at: 599))
        XCTAssertGreaterThan(lively.value(at: 599), 0.4)
        XCTAssertLessThan(flat.value(at: 599), 0.05)
        XCTAssertEqual(flat.value(at: -5), flat.values[0])
        // Cuts slow the loss a little.
        let withCuts = RetentionPredictor.predict(excitement: [Float](repeating: 0.3, count: 300), step: 1, cuts: Array(stride(from: 5.0, to: 300, by: 5)))
        let without = RetentionPredictor.predict(excitement: [Float](repeating: 0.3, count: 300), step: 1)
        XCTAssertGreaterThan(withCuts.value(at: 299), without.value(at: 299))
        // The steepest drops land in the dead stretch of a mixed curve.
        var mixed = [Float](repeating: 0.9, count: 300)
        for i in 120..<200 { mixed[i] = 0.02 }
        let drops = RetentionPredictor.predict(excitement: mixed, step: 1).steepestDrops(count: 1)
        XCTAssertEqual(drops.count, 1)
        XCTAssertTrue((110...200).contains(drops[0]), "drop at \(drops[0])")
        XCTAssertEqual(RetentionPredictor.predict(excitement: [], step: 1).values, [1])
    }

    func testTextTemplatesApplyAndCapture() throws {
        XCTAssertEqual(TextTemplates.builtIn.count, 5)
        XCTAssertTrue(TextTemplates.builtIn.allSatisfy(\.builtIn))
        var clip = TimelineClip(name: "Title", content: .text(TextElement(text: "Hello there")), start: 2, sourceDuration: 3)
        TextTemplates.meme.apply(to: &clip)
        guard case .text(let element) = clip.content else { return XCTFail("still a text clip") }
        XCTAssertEqual(element.text, "Hello there", "the words stay")
        XCTAssertEqual(element.style.fontName, "Impact")
        XCTAssertEqual(element.style.textCase, .uppercase)
        XCTAssertEqual(clip.transform.positionY.value(at: 0), 0.12, accuracy: 1e-9)
        let captured = try XCTUnwrap(TextTemplate.capture(clip, name: "Mine"))
        XCTAssertEqual(captured.style, element.style)
        XCTAssertFalse(captured.builtIn)
        let back = try JSONDecoder().decode(TextTemplate.self, from: JSONEncoder().encode(captured))
        XCTAssertEqual(back, captured)
        var solid = TimelineClip(name: "Colour", content: .solid(.black), start: 0, sourceDuration: 1)
        TextTemplates.meme.apply(to: &solid)
        XCTAssertNil(TextTemplate.capture(solid, name: "x"))
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(settings.textTemplates.isEmpty)
    }
}
