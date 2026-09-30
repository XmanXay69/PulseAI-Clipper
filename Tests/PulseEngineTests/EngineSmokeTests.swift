import XCTest
@testable import PulseEngine

final class EngineSmokeTests: XCTestCase {
    func testVersion() {
        XCTAssertFalse(PulseEngineInfo.version.isEmpty)
    }
}
