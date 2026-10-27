import XCTest
@testable import PulseCore

final class Batch45Tests: XCTestCase {
    // MARK: #46 — a facecam that moves during the stream

    /// A small face in one corner for a stretch, then another corner.
    private func faces(_ stretches: [(range: TimeRange, box: NormRect)], every step: Seconds = 2) -> [FaceSample] {
        var out: [FaceSample] = []
        for s in stretches {
            var t = s.range.start
            while t < s.range.end {
                out.append(FaceSample(time: t, boxes: [s.box]))
                t += step
            }
        }
        return out
    }

    private let topLeft = NormRect(x: 0.02, y: 0.03, width: 0.12, height: 0.16)
    private let bottomRight = NormRect(x: 0.84, y: 0.78, width: 0.12, height: 0.16)
    private let frame = Size2(1920, 1080)

    func testSegmentsFollowTheFacecamBetweenCorners() {
        let samples = faces([(TimeRange(start: 0, end: 600), topLeft), (TimeRange(start: 600, end: 1200), bottomRight)])
        let segments = WebcamEstimator.segments(faces: samples, frameSize: frame, duration: 1200)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].range, TimeRange(start: 0, end: 600))
        XCTAssertEqual(segments[1].range, TimeRange(start: 600, end: 1200))
        XCTAssertGreaterThan(segments[0].estimate.face.iou(topLeft), 0.8)
        XCTAssertTrue(segments[0].estimate.region.contains(topLeft.center))
        XCTAssertLessThan(segments[0].estimate.face.center.x, 0.3)
        XCTAssertGreaterThan(segments[1].estimate.face.center.x, 0.7)
        XCTAssertEqual(segments[0].estimate.profile, .gameplayWithFacecam)
    }

    func testOnePositionGivesNoSegmentsAndDetoursFold() {
        let still = faces([(TimeRange(start: 0, end: 1200), topLeft)])
        XCTAssertTrue(WebcamEstimator.segments(faces: still, frameSize: frame, duration: 1200).isEmpty)
        // A 60 s hop to the other corner and back folds into the stretch around it.
        let detour = faces([(TimeRange(start: 0, end: 600), topLeft), (TimeRange(start: 600, end: 660), bottomRight), (TimeRange(start: 660, end: 1200), topLeft)])
        XCTAssertTrue(WebcamEstimator.segments(faces: detour, frameSize: frame, duration: 1200).isEmpty)
        XCTAssertTrue(WebcamEstimator.segments(faces: [], frameSize: frame, duration: 100).isEmpty)
        // Windows with no face continue the previous stretch rather than splitting it.
        let gap = faces([(TimeRange(start: 0, end: 500), topLeft), (TimeRange(start: 700, end: 1200), bottomRight)])
        let segments = WebcamEstimator.segments(faces: gap, frameSize: frame, duration: 1200)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].range.end, segments[1].range.start)
    }

    func testAnalysisPicksTheEstimateOfTheMoment() throws {
        var analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: 1200)
        let a = WebcamEstimate(region: topLeft, face: topLeft, persistence: 0.9, profile: .gameplayWithFacecam)
        let b = WebcamEstimate(region: bottomRight, face: bottomRight, persistence: 0.9, profile: .gameplayWithFacecam)
        analysis.webcam = a
        XCTAssertFalse(analysis.facecamMoves)
        XCTAssertEqual(analysis.webcam(at: 900), a, "no segments: the overall estimate everywhere")
        analysis.webcamSegments = [WebcamSegment(range: TimeRange(start: 0, end: 600), estimate: a), WebcamSegment(range: TimeRange(start: 600, end: 1200), estimate: b)]
        XCTAssertTrue(analysis.facecamMoves)
        XCTAssertEqual(analysis.webcam(at: 100), a)
        XCTAssertEqual(analysis.webcam(at: 900), b)
        XCTAssertEqual(analysis.webcam(at: 5000), a, "outside every segment falls back")
        // Layout context at a moment uses that stretch's region; without a time, the overall one.
        XCTAssertEqual(LayoutContext(analysis: analysis, sourceSize: frame, at: 900).webcamRegion, bottomRight)
        XCTAssertEqual(LayoutContext(analysis: analysis, sourceSize: frame).webcamRegion, topLeft)
        // Older analyses without the field still decode.
        let back = try JSONDecoder().decode(MediaAnalysis.self, from: JSONEncoder().encode(analysis))
        XCTAssertEqual(back.webcamSegments?.count, 2)
        var old = analysis
        old.webcamSegments = nil
        let data = try JSONEncoder().encode(old)
        XCTAssertNil(try JSONDecoder().decode(MediaAnalysis.self, from: data).webcamSegments)
    }

    // MARK: #35 — first look

    func testPreliminaryFlagIsOptionalAndDecodesFromOldJSON() throws {
        var analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: 600, audio: Fixtures.audio(duration: 600, spikes: [100, 300]))
        analysis.version = -1
        let found = ClipGenerator(input: ClipGenerationInput(analysis: analysis), settings: ClipGenerationSettings(minimumPotential: 0)).generate()
        XCTAssertFalse(found.isEmpty, "audio alone finds the spikes")
        var first = found[0]
        XCTAssertNil(first.preliminary)
        first.preliminary = true
        let back = try JSONDecoder().decode(ClipCandidate.self, from: JSONEncoder().encode(first))
        XCTAssertEqual(back.preliminary, true)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) as! [String: Any]
        json["preliminary"] = nil
        let old = try JSONDecoder().decode(ClipCandidate.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.preliminary)
    }

    // MARK: #465 — exports carry their project in the Finder comment

    func testFinderCommentNamesProjectEditAndPath() throws {
        XCTAssertEqual(ExportSidecar.finderComment(projectName: "Ranked Night", timelineName: "Short 3", projectPath: "/Users/me/Ranked Night.pulse"),
                       "PULSE · Ranked Night › Short 3 · Project: /Users/me/Ranked Night.pulse")
        XCTAssertEqual(ExportSidecar.finderComment(projectName: "Ranked Night", timelineName: "Short 3", projectPath: nil), "PULSE · Ranked Night › Short 3")
        XCTAssertEqual(ExportSidecar.finderComment(projectName: "P", timelineName: "T", projectPath: ""), "PULSE · P › T")
        var job = ExportJob(projectID: UUID(), projectName: "P", timelineID: UUID(), timelineName: "T", settings: ExportSettings())
        XCTAssertNil(job.projectPath)
        job.projectPath = "/tmp/P.pulse"
        let back = try JSONDecoder().decode(ExportJob.self, from: JSONEncoder().encode(job))
        XCTAssertEqual(back.projectPath, "/tmp/P.pulse")
    }
}
