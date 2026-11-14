import XCTest
@testable import PulseCore

/// #501: what the face on camera does is a reaction signal beside the sound.
final class FaceExpressionTests: XCTestCase {
    private typealias Point = FaceExpressionMath.Point

    /// An oval outline centred at (cx, cy), `width` across and `height` tall.
    private func oval(_ cx: Double, _ cy: Double, width: Double, height: Double) -> [Point] {
        (0..<8).map { i in
            let a = Double(i) / 8 * 2 * .pi
            return Point(cx + cos(a) * width / 2, cy + sin(a) * height / 2)
        }
    }

    private func face(mouthGap: Double, mouthWidth: Double = 0.34, eyeHeight: Double = 0.03, browLift: Double = 0.08) -> FaceExpressionMath.Landmarks {
        FaceExpressionMath.Landmarks(outerLips: oval(0.5, 0.3, width: mouthWidth, height: mouthGap + 0.06),
                                     innerLips: oval(0.5, 0.3, width: mouthWidth * 0.8, height: mouthGap),
                                     leftEye: oval(0.33, 0.62, width: 0.14, height: eyeHeight),
                                     rightEye: oval(0.67, 0.62, width: 0.14, height: eyeHeight),
                                     leftBrow: oval(0.33, 0.62 + browLift, width: 0.18, height: 0.02),
                                     rightBrow: oval(0.67, 0.62 + browLift, width: 0.18, height: 0.02))
    }

    func testTheMeasuresFollowTheFace() throws {
        let resting = try XCTUnwrap(FaceExpressionMath.measures(face(mouthGap: 0.01)))
        let gasp = try XCTUnwrap(FaceExpressionMath.measures(face(mouthGap: 0.16, eyeHeight: 0.05, browLift: 0.12)))
        let grin = try XCTUnwrap(FaceExpressionMath.measures(face(mouthGap: 0.04, mouthWidth: 0.46)))
        XCTAssertGreaterThan(gasp.mouthOpen, resting.mouthOpen * 5)
        XCTAssertGreaterThan(gasp.eyeOpen, resting.eyeOpen)
        XCTAssertGreaterThan(gasp.browRaise, resting.browRaise)
        XCTAssertGreaterThan(grin.mouthWidth, resting.mouthWidth)
        // A face with no mouth outline, or no eyes, isn't measured.
        XCTAssertNil(FaceExpressionMath.measures(FaceExpressionMath.Landmarks(outerLips: [], innerLips: [], leftEye: oval(0.3, 0.6, width: 0.1, height: 0.03), rightEye: [])))
        XCTAssertNil(FaceExpressionMath.measures(FaceExpressionMath.Landmarks(outerLips: oval(0.5, 0.3, width: 0.3, height: 0.1), innerLips: [], leftEye: [], rightEye: [])))
    }

    /// A recording of `count` seconds at rest with the given faces at the given seconds.
    private func series(count: Int, reactions: [Int: FaceExpressionMath.Landmarks], missing: Set<Int> = []) throws -> ExpressionSeries {
        var open: [Float] = [], width: [Float] = [], eyes: [Float] = [], brows: [Float] = []
        for i in 0..<count {
            if missing.contains(i) {
                open.append(ExpressionSeries.absent); width.append(ExpressionSeries.absent)
                eyes.append(ExpressionSeries.absent); brows.append(ExpressionSeries.absent)
                continue
            }
            // A resting face that moves a little, as faces do.
            let wobble = Double((i * 7) % 5) * 0.002
            let m = try XCTUnwrap(FaceExpressionMath.measures(reactions[i] ?? face(mouthGap: 0.01 + wobble)))
            open.append(Float(m.mouthOpen)); width.append(Float(m.mouthWidth)); eyes.append(Float(m.eyeOpen)); brows.append(Float(m.browRaise))
        }
        return ExpressionSeries(hop: 1, mouthOpen: open, mouthWidth: width, eyeOpen: eyes, browRaise: brows)
    }

    func testAReactionStandsOutFromThisPersonsRestingFace() throws {
        let gasp = face(mouthGap: 0.16, eyeHeight: 0.05, browLift: 0.12)
        let recorded = try series(count: 120, reactions: [40: gasp, 41: gasp, 90: face(mouthGap: 0.05, mouthWidth: 0.46)], missing: [10, 11, 12])
        let intensity = FaceExpressionMath.intensity(recorded)
        XCTAssertEqual(intensity.count, 120)
        XCTAssertGreaterThan(intensity[40], 0.8, "a jaw-drop with wide eyes is a full reaction")
        XCTAssertGreaterThan(intensity[90], 0.2, "a grin counts, less")
        XCTAssertLessThan(intensity[90], intensity[40])
        XCTAssertEqual(intensity[20], 0, accuracy: 0.05, "the resting face is nothing")
        XCTAssertEqual(intensity[11], 0, "no face, no reaction")
        XCTAssertEqual(recorded.coverage, 117.0 / 120, accuracy: 0.001)

        // Someone whose mouth is always that open isn't reacting all stream long.
        var always: [Int: FaceExpressionMath.Landmarks] = [:]
        for i in 0..<120 { always[i] = gasp }
        XCTAssertEqual(FaceExpressionMath.intensity(try series(count: 120, reactions: always)).max() ?? 1, 0, accuracy: 0.05)
        // Too few faces to know what rest looks like: nothing is claimed.
        let sparse = try series(count: 20, reactions: [5: gasp], missing: Set(0..<20).subtracting([5, 6, 7]))
        XCTAssertEqual(FaceExpressionMath.intensity(sparse).max(), 0)
        XCTAssertTrue(FaceExpressionMath.signal(nil, duration: 60, step: 0.5).isEmpty)
    }

    func testASilentReactionLiftsItsMomentAndIsNamedInTheReason() throws {
        let duration: Seconds = 120
        let gasp = face(mouthGap: 0.16, eyeHeight: 0.05, browLift: 0.12)
        var reactions: [Int: FaceExpressionMath.Landmarks] = [:]
        for i in 60...63 { reactions[i] = gasp }
        let seen = try series(count: 120, reactions: reactions)
        // The sound is flat throughout: nothing was said or shouted at 60 s.
        let audio = Fixtures.audio(duration: duration)
        let without = EngagementModel.compute(duration: duration, audio: audio, transcript: nil, visual: nil)
        let with = EngagementModel.compute(duration: duration, audio: audio, transcript: nil, visual: nil, expressions: seen)
        XCTAssertTrue(without.expression.isEmpty)
        XCTAssertEqual(with.expression.count, with.count)
        let at = with.index(at: 61.5)
        XCTAssertGreaterThan(with.excitement[at], without.excitement[at] + 0.05, "the face lifts the moment the sound missed")
        XCTAssertEqual(with.excitement[with.index(at: 20)], without.excitement[without.index(at: 20)], accuracy: 0.01, "and leaves the rest alone")
        // The signal reaches the model through an analysis, and survives a save.
        var analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: duration, audio: audio, transcript: nil, profile: .gameplayWithFacecam)
        analysis.expressions = seen
        let saved = try JSONDecoder().decode(MediaAnalysis.self, from: JSONEncoder().encode(analysis))
        XCTAssertEqual(saved.expressions, seen)
        XCTAssertEqual(EngagementModel.compute(analysis: saved).expression.count, with.count)
        // The reason a moment was picked says so.
        let candidate = ClipCandidate(assetID: Fixtures.assetID, range: TimeRange(start: 50, end: 75), payoffTime: 61.5, targetDuration: 25, potential: 60,
                                      scores: ClipScores(), tags: [.reaction], title: "", copy: .empty, transcriptSnippet: "")
        let reason = MomentExplanation.explain(candidate: candidate, signals: with, banners: [])
        XCTAssertTrue(reason.signals.contains { $0.name == "Face" }, "\(reason.signals.map(\.name))")
        XCTAssertFalse(MomentExplanation.explain(candidate: candidate, signals: without, banners: []).signals.contains { $0.name == "Face" })
    }
}
