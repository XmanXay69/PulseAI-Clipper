import XCTest
@testable import PulseCore

final class CalibrationTests: XCTestCase {
    func testReadsYouTubeStudioAndTikTokExports() {
        let yt = "\u{FEFF}Content,Video title,Video publish time,Duration,Views,Average percentage viewed (%)\nTotal,,,,\"12,345\",\nabc123,\"I CAN'T BELIEVE IT 😳\",\"Oct 1, 2026\",31,\"8,120\",71.5\ndef456,Triple elimination clutch,\"Oct 2, 2026\",28,950,40.2\n"
        let rows = AnalyticsImporter.parse(yt)
        XCTAssertEqual(rows.count, 2, "skips the total row")
        XCTAssertEqual(rows[0].views, 8120)
        XCTAssertEqual(rows[0].averagePercentViewed ?? 0, 71.5, accuracy: 1e-9)
        let tt = "Video title,Video views,Likes\nclutch moment #gaming,15000,900\n"
        XCTAssertEqual(AnalyticsImporter.parse(tt).first?.views, 15000)
        XCTAssertTrue(AnalyticsImporter.parse("a,b\n1,2").isEmpty)
    }

    func testMatchesRenamedTitles() {
        var records = [
            PerformanceRecord(titles: ["“I CAN'T BELIEVE IT!” 😳", "I CANT BELIEVE IT-TikTok"], format: .short, predictedScore: 80, factors: [:], duration: 30),
            PerformanceRecord(titles: ["Triple Elimination"], format: .short, predictedScore: 50, factors: [:], duration: 30),
            PerformanceRecord(titles: ["Something else entirely"], format: .short, predictedScore: 50, factors: [:], duration: 30),
        ]
        let rows = [AnalyticsRow(title: "I can't believe it 😳 #gaming", views: 8000), AnalyticsRow(title: "TRIPLE ELIMINATION clutch", views: 900)]
        XCTAssertEqual(AnalyticsImporter.match(rows, into: &records), 2)
        XCTAssertEqual(records[0].views, 8000)
        XCTAssertEqual(records[1].views, 900)
        XCTAssertNil(records[2].views)
    }

    /// On this channel, hooks drive views and polish doesn't.
    func history(count: Int) -> [PerformanceRecord] {
        (0..<count).map { i in
            let hook = Double(i % 10) / 10
            let polish = Double((i * 7) % 10) / 10
            let views = pow(10, 2 + 3 * hook) * (1 + 0.1 * Double(i % 3))
            let factors = ["Hook": hook, "Energy": 0.6, "Payoff": 0.6, "Pacing": 0.6, "Ending": 0.6, "Length": 1, "Polish": polish]
            return PerformanceRecord(titles: ["v\(i)"], format: .short, predictedScore: Int(hook * 100), factors: factors, duration: 30, views: views)
        }
    }

    func testCalibrationLearnsWhatDrivesViews() throws {
        XCTAssertNil(CoachCalibrator.fit(history(count: 3)).shortWeights, "too few to calibrate")
        let calibration = CoachCalibrator.fit(history(count: 30))
        let w = try XCTUnwrap(calibration.shortWeights)
        XCTAssertEqual(calibration.shortSamples, 30)
        XCTAssertGreaterThan(w["Hook"]!, EditCoach.defaultWeights(.short)["Hook"]!, "hook matters more here")
        XCTAssertLessThan(w["Polish"]!, EditCoach.defaultWeights(.short)["Polish"]!, "polish matters less here")
        XCTAssertEqual(w.values.reduce(0, +), 1, accuracy: 0.02)
        XCTAssertTrue(calibration.insight.contains("×"), calibration.insight)
        XCTAssertNil(calibration.longWeights)
    }

    func testCoachUsesTheCalibratedWeights() {
        let analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: 200, audio: Fixtures.audio(duration: 200, spikes: [115]),
                                     transcript: Fixtures.transcript(duration: 200))
        let timeline = Fixtures.simpleTimeline(clipDuration: 30)
        let plain = EditCoach.review(timeline, analysis: analysis)
        XCTAssertEqual(plain.prediction.calibratedOn, 0)
        let calibrated = EditCoach.review(timeline, analysis: analysis, calibration: CoachCalibrator.fit(history(count: 30)))
        XCTAssertEqual(calibrated.prediction.calibratedOn, 30)
        XCTAssertNotEqual(calibrated.prediction.score, plain.prediction.score)
    }
}
