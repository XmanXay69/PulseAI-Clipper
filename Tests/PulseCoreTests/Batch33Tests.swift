import XCTest
@testable import PulseCore

final class Batch33Tests: XCTestCase {
    func testTwoFacesAreFramedTogetherWhenTheyFit() {
        let left = NormRect(x: 0.2, y: 0.3, width: 0.12, height: 0.2)
        let right = NormRect(x: 0.55, y: 0.3, width: 0.11, height: 0.19)
        // A 9:16 crop of a 16:9 frame is about 0.56 wide: both faces span 0.46, so the middle wins.
        XCTAssertEqual(AutoReframer.followX(boxes: [left, right], cropWidth: 0.56)!, (0.2 + 0.66) / 2, accuracy: 1e-9)
        // Too far apart for the crop: follow the bigger face.
        let far = NormRect(x: 0.85, y: 0.3, width: 0.11, height: 0.19)
        XCTAssertEqual(AutoReframer.followX(boxes: [left, far], cropWidth: 0.56)!, left.center.x, accuracy: 1e-9)
        // A tiny second face (someone in the background) doesn't count.
        let tiny = NormRect(x: 0.5, y: 0.3, width: 0.03, height: 0.05)
        XCTAssertEqual(AutoReframer.followX(boxes: [left, tiny], cropWidth: 0.56)!, left.center.x, accuracy: 1e-9)
        XCTAssertNil(AutoReframer.followX(boxes: [], cropWidth: 0.5))
    }
}
