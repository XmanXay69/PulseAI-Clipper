import XCTest
@testable import PulseCore

final class Batch41Tests: XCTestCase {
    // MARK: #330 — the grid divider

    func testGridSlotsFollowTheSplit() {
        let landscape = CanvasSettings.landscape1080
        let even = MulticamGridLayout.twoUp.slots(count: 2, canvas: landscape, gap: 0)
        XCTAssertEqual(even[0].width, 0.5, accuracy: 1e-9)
        let wide = MulticamGridLayout.twoUp.slots(count: 2, canvas: landscape, gap: 0, split: 0.65)
        XCTAssertEqual(wide[0].width, 0.65, accuracy: 1e-9)
        XCTAssertEqual(wide[1].x, 0.65, accuracy: 1e-9)
        XCTAssertEqual(wide[1].width, 0.35, accuracy: 1e-9)
        let tall = MulticamGridLayout.threeUp.slots(count: 3, canvas: .vertical1080, gap: 0, split: 0.4)
        XCTAssertEqual(tall[0].height, 0.4, accuracy: 1e-9)
        XCTAssertEqual(tall[1].y, 0.4, accuracy: 1e-9)
        XCTAssertEqual(tall[2].height, 0.6, accuracy: 1e-9)
        let clamped = MulticamGridLayout.quad.slots(count: 4, canvas: landscape, gap: 0, split: 0.9)
        XCTAssertEqual(clamped[0].width, 0.7, accuracy: 1e-9, "the divider stays between 30 and 70 %")
        let featured = MulticamGridLayout.featured.slots(count: 4, canvas: landscape, gap: 0, split: 0.7)
        XCTAssertEqual(featured[0].width, 0.85, accuracy: 1e-9)
        XCTAssertEqual(MulticamGridLayout.featured.slots(count: 4, canvas: landscape, gap: 0, split: 0.3)[0].width, 0.55, accuracy: 1e-9)
        // Every layout still tiles the canvas.
        for layout in MulticamGridLayout.allCases {
            let area = layout.slots(count: layout.capacity, canvas: landscape, gap: 0, split: 0.6).map(\.area).reduce(0, +)
            XCTAssertEqual(area, 1, accuracy: 1e-9, "\(layout) tiles the canvas")
        }
    }

    // MARK: #325 — sync by timecode

    func testTimecodeOffsetsAreExactAndRefuseMidnightRollovers() throws {
        let a = UUID(), b = UUID(), c = UUID()
        let result = try XCTUnwrap(TimecodeSync.offsets(startTimecodes: [a: 36_005.0, b: 36_000.0, c: 36_012.5]))
        XCTAssertEqual(result.offsets[b]!, 0, accuracy: 1e-9)
        XCTAssertEqual(result.offsets[a]!, 5, accuracy: 1e-9)
        XCTAssertEqual(result.offsets[c]!, 12.5, accuracy: 1e-9)
        XCTAssertEqual(result.confidence, 1)
        XCTAssertEqual(TimecodeSync.describe(result), "Timecode")
        XCTAssertNil(TimecodeSync.offsets(startTimecodes: [a: 100.0]), "needs two")
        XCTAssertNil(TimecodeSync.offsets(startTimecodes: [a: 100.0, b: 82_800.0]), "a camera past midnight can't be trusted")
        XCTAssertEqual(TimecodeSync.describe(TimecodeSync.Result(offsets: [:], confidence: 0.82, method: "audio")), "Audio · 82 %")
        var asset = MediaAsset(name: "Cam", path: "/tmp/cam.mov", kind: .video)
        asset.metadata.startTimecode = 36_000
        asset.syncConfidence = 0.5
        let back = try JSONDecoder().decode(MediaAsset.self, from: JSONEncoder().encode(asset))
        XCTAssertEqual(back.metadata.startTimecode, 36_000)
        XCTAssertEqual(back.syncConfidence, 0.5)
    }
}
