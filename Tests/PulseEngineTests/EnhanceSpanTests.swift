import XCTest
@testable import PulseCore
@testable import PulseEngine

final class EnhanceSpanTests: XCTestCase {
    func testJumpCutPiecesShareOneRenderPerStretch() {
        // 200 jump-cut pieces from three stretches of the stream, plus one with different settings.
        var inputs: [CompositionBuilder.EnhanceSpanInput] = []
        for stretch in [100.0, 1000.0, 5000.0] {
            for k in 0..<66 {
                let start = stretch + Double(k) * 1.5
                inputs.append(.init(clipID: UUID(), group: "a|n", range: TimeRange(start: start, end: start + 1.2)))
            }
        }
        let odd = CompositionBuilder.EnhanceSpanInput(clipID: UUID(), group: "a|nv", range: TimeRange(start: 101, end: 102))
        inputs.append(odd)
        let spans = CompositionBuilder.enhanceSpans(inputs)
        XCTAssertEqual(spans.count, inputs.count, "every clip gets a stretch")
        XCTAssertEqual(Set(spans.values).count, 4, "three stretches + the clip with other settings")
        for input in inputs {
            let span = spans[input.clipID]!
            XCTAssertTrue(span.contains(input.range), "a clip's audio lies inside its stretch")
        }
        XCTAssertEqual(spans[odd.clipID], odd.range)
    }

    func testStretchesStayUnderTenMinutes() {
        let inputs = (0..<100).map { k in
            CompositionBuilder.EnhanceSpanInput(clipID: UUID(), group: "a", range: TimeRange(start: Double(k) * 15, end: Double(k) * 15 + 10))
        }
        let spans = Set(CompositionBuilder.enhanceSpans(inputs).values)
        XCTAssertTrue(spans.allSatisfy { $0.duration <= 600 })
        XCTAssertGreaterThan(spans.count, 2)
    }
}
