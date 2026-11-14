import XCTest
@testable import PulseCore

/// Blocking reads must not be able to park every cooperative thread: that froze every `await` in the app
/// when a page of audio tiles asked for all of its waveforms at once.
final class BlockingWorkTests: XCTestCase {
    func testWorkReturnsItsValueAndSlowWorkThatReportsProgressFinishes() async {
        let quick = await BlockingWork.run(fallback: -1) { _ in 41 + 1 }
        XCTAssertEqual(quick, 42)

        // Ten steps of 0.1 s against a 0.4 s limit: slow, but never silent for long.
        let slow = await BlockingWork.run(stallLimit: 0.4, fallback: -1) { heartbeat in
            for _ in 0..<10 {
                Thread.sleep(forTimeInterval: 0.1)
                heartbeat.beat()
            }
            return 7
        }
        XCTAssertEqual(slow, 7)
    }

    func testWorkThatStopsIsGivenUpOnAndItsLateValueIsIgnored() async {
        let start = Date()
        let value = await BlockingWork.run(stallLimit: 0.3, fallback: -1) { _ in
            Thread.sleep(forTimeInterval: 2)
            return 9
        }
        XCTAssertEqual(value, -1, "the caller gets the fallback")
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.7, "and gets it before the work would have finished")
        // The abandoned work finishes later and tries to answer: nothing may crash or answer twice.
        try? await Task.sleep(nanoseconds: 2_000_000_000)
    }

    func testBlockedReadsLeaveTheRestOfTheAppRunning() async {
        // Three times as many blocked reads as cores: on the cooperative pool this stopped every other task.
        let count = max(6, ProcessInfo.processInfo.activeProcessorCount * 3)
        let reads = (0..<count).map { _ in
            Task { await BlockingWork.run(stallLimit: 10, fallback: 0) { _ in Thread.sleep(forTimeInterval: 1); return 1 } }
        }
        let start = Date()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.8, "a 0.1 s sleep still wakes on time")
        var finished = 0
        for read in reads { finished += await read.value }
        XCTAssertEqual(finished, count)
    }

    func testTheGateLetsAFewThroughAtATimeAndIsReusable() async {
        actor Peak {
            var now = 0
            var most = 0
            func up() { now += 1; most = max(most, now) }
            func down() { now -= 1 }
        }
        let gate = AsyncGate(limit: 2)
        let peak = Peak()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    await gate.enter()
                    await peak.up()
                    try? await Task.sleep(nanoseconds: 20_000_000)
                    await peak.down()
                    await gate.leave()
                }
            }
        }
        let most = await peak.most
        XCTAssertEqual(most, 2)

        // Every place came back: two more callers get straight in.
        let entered = Task { () -> Bool in
            await gate.enter()
            await gate.enter()
            await gate.leave()
            await gate.leave()
            return true
        }
        let ok = await entered.value
        XCTAssertTrue(ok)
        // A limit below one still lets work through.
        let narrow = AsyncGate(limit: 0)
        await narrow.enter()
        await narrow.leave()
    }
}
