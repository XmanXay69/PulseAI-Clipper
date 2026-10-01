import XCTest
@testable import PulseCore

final class LayoutMorphTests: XCTestCase {
    let asset = UUID()
    let context = LayoutContext(sourceSize: Size2(1920, 1080), webcamRegion: NormRect(x: 0.72, y: 0.68, width: 0.26, height: 0.3),
                                faceCenter: Vec2(0.85, 0.8), profile: .gameplayWithFacecam)

    /// A 10 s vertical short: gameplay on V1, the facecam (same file) on V2, laid out split-screen.
    func makeTimeline() -> Timeline {
        let group = UUID()
        var gameplay = Track(kind: .video, name: "V1")
        gameplay.clips = [TimelineClip(name: "Gameplay", content: .media(assetID: asset), start: 0, sourceDuration: 10, linkGroup: group, role: .main)]
        var cam = Track(kind: .video, name: "V2 Facecam")
        cam.clips = [TimelineClip(name: "Facecam", content: .media(assetID: asset), start: 0, sourceDuration: 10, linkGroup: group, role: .webcam)]
        var timeline = Timeline(name: "Short", canvas: .vertical1080, tracks: [gameplay, cam])
        LayoutEngine.apply(.splitScreen, to: &timeline, context: context)
        return timeline
    }

    func gameplay(_ t: Timeline) -> TimelineClip { t.tracks[0].clips[0] }
    func facecam(_ t: Timeline) -> TimelineClip { t.tracks[1].clips[0] }

    func target(_ role: MediaRole, _ preset: LayoutPreset) -> LayoutTarget {
        LayoutEngine.target(role: role, preset: preset, context: context, canvas: .vertical1080)!
    }

    func between(_ x: Double, _ a: Double, _ b: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(x, min(a, b) + 1e-6, file: file, line: line)
        XCTAssertLessThan(x, max(a, b) - 1e-6, file: file, line: line)
    }

    func testMorphAnimatesBetweenLayoutsWithoutSplittingClips() {
        var timeline = makeTimeline()
        LayoutMorpher.addChange(.facecamCorner, at: 4, duration: 1, to: &timeline, context: context)
        XCTAssertEqual(timeline.tracks.map(\.clips.count), [1, 1], "no clips were split")
        let split = target(.main, .splitScreen), corner = target(.main, .facecamCorner)
        let g = gameplay(timeline)
        XCTAssertEqual(g.transform.positionY.value(at: 3.9), split.positionY, accuracy: 1e-9)
        XCTAssertEqual(g.transform.positionY.value(at: 5.1), corner.positionY, accuracy: 1e-9)
        between(g.transform.positionY.value(at: 4.5), split.positionY, corner.positionY)
        between(g.transform.crop(at: 4.5).width, split.crop.width, corner.crop.width)
        XCTAssertEqual(g.transform.crop(at: 9), corner.crop)

        // The facecam's frame rounds and grows a border during the morph.
        let cam = facecam(timeline)
        let cornerStyle = target(.webcam, .facecamCorner).style
        XCTAssertEqual(cam.style(at: 3.9), .plain)
        XCTAssertEqual(cam.style(at: 5.1), cornerStyle)
        let mid = cam.style(at: 4.5)
        between(mid.borderWidth, 0, cornerStyle.borderWidth)
        between(mid.cornerRadius, 0, cornerStyle.roundness)
        XCTAssertEqual(LayoutMorpher.preset(at: 6, in: timeline), .facecamCorner)
        XCTAssertEqual(LayoutMorpher.preset(at: 2, in: timeline), .splitScreen)
    }

    func testFacecamFadesOutForFullFrameAndBoxRoundsIntoCircle() {
        var timeline = makeTimeline()
        LayoutMorpher.addChange(.facecamCorner, at: 2, duration: 0.5, to: &timeline, context: context)
        LayoutMorpher.addChange(.circleFacecam, at: 4, duration: 1, to: &timeline, context: context)
        LayoutMorpher.addChange(.fullFrame, at: 7, duration: 0.5, to: &timeline, context: context)
        let cam = facecam(timeline)
        XCTAssertTrue(cam.isEnabled)
        XCTAssertEqual(cam.transform.opacity.value(at: 6.9), 1, accuracy: 1e-9)
        XCTAssertEqual(cam.transform.opacity.value(at: 7.6), 0, accuracy: 1e-9)
        between(cam.transform.opacity.value(at: 7.25), 0, 1)
        // Corner box → circle passes through ever-rounder corners.
        let mid = cam.style(at: 4.5)
        XCTAssertEqual(mid.mask, .rectangle)
        between(mid.cornerRadius, target(.webcam, .facecamCorner).style.roundness, 0.5)
        XCTAssertEqual(cam.style(at: 5.2).mask, .circle)
        // Gameplay ends full screen.
        XCTAssertEqual(gameplay(timeline).transform.positionY.value(at: 9), target(.main, .fullFrame).positionY, accuracy: 1e-9)
    }

    func testSplittingMidMorphKeepsTheExactAnimation() throws {
        var timeline = makeTimeline()
        LayoutMorpher.addChange(.facecamDominant, at: 3, duration: 2, to: &timeline, context: context)
        let before = gameplay(timeline)
        let times = [3.2, 3.7, 4.4, 4.9]
        let expected = times.map { before.transform.positionY.value(at: $0) }
        let expectedStyle = facecam(timeline).style(at: 4.4)
        try timeline.split(at: 4.1)
        let pieces = timeline.tracks[0].clips
        XCTAssertEqual(pieces.count, 2)
        for (t, value) in zip(times, expected) {
            let clip = pieces.first { $0.timelineRange.contains(t) }!
            XCTAssertEqual(clip.transform.positionY.value(at: clip.localTime(atTimeline: t)), value, accuracy: 1e-9, "at \(t)")
        }
        let camPiece = timeline.tracks[1].clips.first { $0.timelineRange.contains(4.4) }!
        XCTAssertEqual(camPiece.style(at: camPiece.localTime(atTimeline: 4.4)), expectedStyle)
    }

    func testScheduleFollowsEditsAndGlobalLayoutResets() {
        var timeline = makeTimeline()
        LayoutMorpher.addChange(.facecamCorner, at: 6, duration: 0.5, to: &timeline, context: context)
        timeline.rippleDelete(range: TimeRange(start: 1, end: 3))
        XCTAssertEqual(timeline.layoutChanges.first?.time ?? 0, 4, accuracy: 1e-9)
        // Replacing a change at the same time instead of stacking.
        LayoutMorpher.addChange(.circleFacecam, at: 4.01, duration: 0.5, to: &timeline, context: context)
        XCTAssertEqual(timeline.layoutChanges.count, 1)
        XCTAssertEqual(timeline.layoutChanges.first?.preset, .circleFacecam)
        // A whole-timeline layout clears the schedule and the animation.
        LayoutEngine.apply(.facecamCorner, to: &timeline, context: context)
        XCTAssertTrue(timeline.layoutChanges.isEmpty)
        XCTAssertFalse(timeline.allClips.contains { $0.transform.hasKeyframes || !$0.styleKeyframes.isEmpty })
    }

    func testStyleInterpolationEndpointsAndShapes() {
        let box = LayerStyle(mask: .roundedRectangle, cornerRadius: 0.1, borderWidth: 6, shadowOpacity: 0.4)
        var circle = box
        circle.mask = .circle
        XCTAssertEqual(LayerStyle.plain.interpolated(to: box, 0), .plain)
        XCTAssertEqual(LayerStyle.plain.interpolated(to: box, 1), box)
        let half = box.interpolated(to: circle, 0.5)
        XCTAssertEqual(half.cornerRadius, 0.3, accuracy: 1e-9)
        XCTAssertEqual(half.borderWidth, 6, accuracy: 1e-9)
        let keyframes = [StyleKeyframe(time: 1, style: .plain), StyleKeyframe(time: 2, style: box)]
        XCTAssertEqual(keyframes.style(at: 0), .plain)
        XCTAssertEqual(keyframes.style(at: 3), box)
        XCTAssertEqual(keyframes.style(at: 1.5)?.borderWidth ?? 0, 3, accuracy: 1e-9, "ease-in-out is halfway at the midpoint")
    }
}
