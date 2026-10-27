import XCTest
@testable import PulseCore

final class Batch39Tests: XCTestCase {
    // MARK: #11 — OBS multi-track recordings

    func testOBSLanesFollowTheUsualTrackOrder() throws {
        let lanes = OBSTracks.lanes(count: 4)
        XCTAssertEqual(lanes.map(\.name), ["Mix", "Mic", "Game", "Music"])
        XCTAssertEqual(lanes.map(\.role), [.main, .microphone, .gameplay, .music])
        XCTAssertEqual(lanes.map(\.startsMuted), [true, false, false, false], "the full mix starts muted so nothing plays twice")
        XCTAssertEqual(lanes.map(\.index), [0, 1, 2, 3])
        XCTAssertEqual(OBSTracks.lanes(count: 1).count, 1)
        XCTAssertFalse(OBSTracks.lanes(count: 1)[0].startsMuted)
        XCTAssertEqual(OBSTracks.lanes(count: 8).last?.name, "Track 8")
        var audio = AudioSettings()
        XCTAssertNil(audio.sourceTrack)
        audio.sourceTrack = 2
        let back = try JSONDecoder().decode(AudioSettings.self, from: JSONEncoder().encode(audio))
        XCTAssertEqual(back.sourceTrack, 2)
        XCTAssertNil(try JSONDecoder().decode(AudioSettings.self, from: Data("{}".utf8)).sourceTrack)
    }

    // MARK: #81 — a sticker that follows the face

    func testPinnedEmojiFollowsTheFaceAboveTheHead() throws {
        let asset = UUID()
        let clip = TimelineClip(name: "Cam", content: .media(assetID: asset), start: 10, sourceIn: 30, sourceDuration: 6)
        // The face drifts from the left third to the right third over the clip.
        var faces: [FaceSample] = []
        var t: Seconds = 29
        while t <= 37 {
            let x = 0.2 + (t - 30) / 6 * 0.4
            faces.append(FaceSample(time: t, boxes: [NormRect(x: x, y: 0.3, width: 0.15, height: 0.25)]))
            t += 0.25
        }
        let sticker = try XCTUnwrap(FaceFollower.pinned("😂", to: clip, faces: faces))
        XCTAssertEqual(sticker.start, 10, accuracy: 1e-9)
        XCTAssertEqual(sticker.duration, 6, accuracy: 1e-9)
        guard case .text(let element) = sticker.content else { return XCTFail("not a text clip") }
        XCTAssertEqual(element.text, "😂")
        XCTAssertTrue(sticker.transform.positionX.isAnimated)
        XCTAssertTrue(sticker.aiGenerated)
        let startX = sticker.transform.positionX.value(at: 0)
        let endX = sticker.transform.positionX.value(at: 5.9)
        XCTAssertLessThan(startX, endX, "moves with the face")
        XCTAssertEqual(startX, 0.2 + 0.075, accuracy: 0.03)
        let y = sticker.transform.positionY.value(at: 3)
        XCTAssertLessThan(y, 0.3, "sits above the top of the head")
        XCTAssertGreaterThan(y, 0.1)
        // Through a punch-in crop the canvas position moves accordingly.
        var zoomed = clip
        zoomed.transform.zoom = AnimatedDouble(2)
        let p = FaceFollower.canvasPoint(face: NormRect(x: 0.4, y: 0.3, width: 0.2, height: 0.3), clip: zoomed, local: 1)
        XCTAssertEqual(p.x, 0.5, accuracy: 1e-9, "a centred face stays centred under a centred zoom")
        XCTAssertEqual(p.y, (0.3 - 0.25) / 0.5, accuracy: 1e-9)
        XCTAssertNil(FaceFollower.pinned("😂", to: clip, faces: []))
        XCTAssertNil(FaceFollower.pinned("😂", to: clip, faces: [FaceSample(time: 100, boxes: [NormRect(x: 0.1, y: 0.1, width: 0.1, height: 0.1)])]), "faces outside the clip don't count")
    }
}
