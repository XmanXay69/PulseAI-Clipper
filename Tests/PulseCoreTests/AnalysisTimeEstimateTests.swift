import XCTest
@testable import PulseCore

final class AnalysisTimeEstimateTests: XCTestCase {
    func testEstimateScalesWithLengthAndSkipsStagesThatWontRun() {
        let speed = AnalysisSpeedProfile()
        let hour = speed.estimate(duration: 3600, hasAudio: true, transcribe: true, hasVideo: true)
        let twoHours = speed.estimate(duration: 7200, hasAudio: true, transcribe: true, hasVideo: true)
        XCTAssertEqual(twoHours.total / hour.total, 2, accuracy: 0.05)
        XCTAssertGreaterThan(hour.weight(.transcription), hour.weight(.video), "speech-to-text dominates")
        let audioOnly = speed.estimate(duration: 3600, hasAudio: true, transcribe: false, hasVideo: false)
        XCTAssertNil(audioOnly.stages[.transcription])
        XCTAssertEqual(audioOnly.weight(.audio), 1, accuracy: 1e-9)
    }

    func testLearningMovesTowardMeasuredSpeed() {
        var speed = AnalysisSpeedProfile()
        // A fast Mac: transcribing 60 min took 60 s (1 s per minute).
        speed.learn(stageSeconds: [.transcription: 60], mediaDuration: 3600)
        XCTAssertLessThan(speed.transcription, 2.2)
        XCTAssertEqual(speed.samples, 1)
        for _ in 0..<6 { speed.learn(stageSeconds: [.transcription: 60], mediaDuration: 3600) }
        XCTAssertEqual(speed.transcription, 1, accuracy: 0.05)
        // Tiny clips don't teach anything.
        let before = speed
        speed.learn(.video, mediaDuration: 5, wallSeconds: 100)
        XCTAssertEqual(speed.video, before.video)
    }

    func testClockConvergesOnTheObservedRateAndCountsDown() {
        // Expected 100 s, but the job is really running twice as slow (200 s total).
        var clock = ProgressClock(expectedTotal: 100)
        var last = Double.greatestFiniteMagnitude
        var values: [Double] = []
        for t in stride(from: 10.0, through: 180, by: 10) {
            let value = clock.remaining(elapsed: t, fraction: t / 200)!
            values.append(value)
            if t > 90 { XCTAssertLessThanOrEqual(value, last + 1, "keeps counting down once it has settled") }
            last = value
        }
        XCTAssertEqual(values.last!, 20, accuracy: 5, "near the true 20 s left at the end")
        XCTAssertEqual(clock.remaining(elapsed: 200, fraction: 1), 0)
        // When the estimate was right, it simply counts down.
        var exact = ProgressClock(expectedTotal: 100)
        for t in stride(from: 5.0, through: 95, by: 5) {
            XCTAssertEqual(exact.remaining(elapsed: t, fraction: t / 100)!, 100 - t, accuracy: 1)
        }
    }

    func testFriendlyDurations() {
        XCTAssertEqual(DurationText.approximate(30), "less than a minute")
        XCTAssertEqual(DurationText.approximate(240), "about 4 min")
        XCTAssertEqual(DurationText.approximate(4800), "about 1 h 20 min")
        XCTAssertEqual(DurationText.remaining(240), "~4 min left")
        XCTAssertEqual(DurationText.remaining(8), "almost done")
        XCTAssertEqual("less than a minute left".capitalizedFirst, "Less than a minute left")
    }
}
