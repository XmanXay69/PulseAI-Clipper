import XCTest
@testable import PulseCore

/// Roadmap batch 20: energy search (#285), low-priority export flag (#342), the performance log (#395).
final class Batch20Tests: XCTestCase {
    func testEnergySearch() {
        let driving = SoundLibrary.search("driving", kind: .music)
        XCTAssertFalse(driving.isEmpty)
        XCTAssertTrue(driving.allSatisfy { ($0.bpm ?? 0) >= 120 }, "\(driving.map { "\($0.name) \($0.bpm ?? 0)" })")
        let calm = SoundLibrary.search("calm", kind: .music)
        XCTAssertTrue(calm.contains { ($0.bpm ?? 999) < 95 })
        XCTAssertNil(SoundLibrary.effects[0].energy)
        XCTAssertEqual(SoundLibrary.music.first { $0.name == "Clutch Moment" }?.energy, "driving")
    }

    func testLowPriorityExportDecodesOff() throws {
        let settings = try JSONDecoder().decode(ExportSettings.self, from: Data("{}".utf8))
        XCTAssertFalse(settings.lowPriority)
    }

    func testPerfLogKeepsTheLastTwoHundred() {
        PerfLog.clear()
        for i in 0..<250 { PerfLog.record("job \(i)", seconds: Double(i)) }
        XCTAssertEqual(PerfLog.entries.count, PerfLog.capacity)
        XCTAssertEqual(PerfLog.entries.first?.label, "job 50")
        XCTAssertTrue(PerfLog.text(limit: 1).hasSuffix("job 249  249.0 s"))
        PerfLog.clear()
        XCTAssertTrue(PerfLog.entries.isEmpty)
    }
}
