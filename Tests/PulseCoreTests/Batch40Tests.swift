import XCTest
@testable import PulseCore

final class Batch40Tests: XCTestCase {
    // MARK: #363 — the big-face cutout thumbnail

    func testCutoutLayoutPlacesThePersonOnAWashAndFallsBackWithoutOne() {
        let face = NormRect(x: 0.55, y: 0.25, width: 0.2, height: 0.3)
        let doc = ThumbnailDesigner.design(.cutout, framePath: "/tmp/frame.jpg", sourceAspect: 16.0 / 9.0, face: face,
                                           headline: "NO WAY", cutoutPath: "/tmp/person.png")
        XCTAssertEqual(doc.layers.map(\.name), ["PULSE frame", "Wash", "Person", "Headline"])
        guard case .image(let person) = doc.layers[2].kind else { return XCTFail("no person layer") }
        XCTAssertEqual(person.path, "/tmp/person.png")
        XCTAssertGreaterThan(doc.layers[2].x, 0.6, "the person sits on the right")
        XCTAssertLessThan(doc.layers[3].x, 0.4, "the text on the left")
        XCTAssertLessThan(doc.layers[1].opacity, 1, "a translucent wash over the frame")
        // No cutout → the face zoom look instead.
        let plain = ThumbnailDesigner.design(.cutout, framePath: "/tmp/frame.jpg", sourceAspect: 16.0 / 9.0, face: face, headline: "NO WAY")
        XCTAssertFalse(plain.layers.contains { $0.name == "Person" })
        XCTAssertTrue(plain.layers.contains { $0.name == "Headline" })
        XCTAssertEqual(ThumbnailLayout.cutout.displayName, "Big Face Cutout")
        XCTAssertFalse(ThumbnailLayout.cutout.symbol.isEmpty)
        XCTAssertTrue(ThumbnailLayout.allCases.contains(.cutout))
    }
}
