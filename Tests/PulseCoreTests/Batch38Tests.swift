import XCTest
@testable import PulseCore

final class Batch38Tests: XCTestCase {
    // MARK: #20 — media folders

    func testFolderTreeFlattensTopDownAndRemovalLiftsChildren() throws {
        var doc = ProjectDocument(name: "T")
        let a = MediaFolder(name: "A", color: .red)
        let b = MediaFolder(name: "B", parentID: a.id)
        let c = MediaFolder(name: "C")
        let orphan = MediaFolder(name: "D", parentID: UUID())
        doc.folders = [c, orphan, b, a]
        var clip = MediaAsset(name: "clip", path: "/tmp/clip.mp4", kind: .video)
        clip.folderID = a.id
        doc.media = [clip]
        let tree = doc.folderTree
        XCTAssertEqual(tree.map(\.folder.name), ["C", "D", "A", "B"])
        XCTAssertEqual(tree.map(\.depth), [0, 0, 0, 1])
        XCTAssertEqual(tree.first { $0.folder.name == "A" }?.folder.color, .red)
        doc.removeFolder(id: a.id)
        XCTAssertEqual(doc.folders.count, 3)
        XCTAssertNil(doc.folders.first { $0.name == "B" }?.parentID, "B moved up to the root")
        XCTAssertNil(doc.media[0].folderID, "media in the deleted folder is back at the top level")
        let back = try JSONDecoder().decode(MediaFolder.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(back.color, .red)
        XCTAssertNil(try JSONDecoder().decode(MediaFolder.self, from: Data(#"{"id":"\#(UUID().uuidString)","name":"old"}"#.utf8)).color)
    }

    // MARK: #99 — the end screen shows the next video's thumbnail

    func testEndScreenPlacesTheNextVideoInTheRightHalf() throws {
        let asset = UUID(), thumb = UUID()
        var timeline = Timeline.empty(name: "VOD", canvas: .landscape1080)
        timeline.tracks[0].clips = [TimelineClip(name: "Main", content: .media(assetID: asset), start: 0, sourceDuration: 60)]
        EditPolish.addEndScreen(&timeline, handle: "pulse", nextVideo: thumb)
        let next = try XCTUnwrap(timeline.videoTracks.flatMap(\.clips).first { $0.name == "Next Video" })
        XCTAssertEqual(next.assetID, thumb)
        XCTAssertEqual(next.start, 60.8, accuracy: 1e-9)
        XCTAssertEqual(next.duration, 9, accuracy: 1e-9)
        XCTAssertGreaterThan(next.transform.positionX.value, 0.6, "sits in the right half, where YouTube's card goes")
        XCTAssertEqual(next.style.mask, .roundedRectangle)
        XCTAssertNotEqual(timeline.tracks.first { t in t.clips.contains { $0.id == next.id } }?.id, timeline.tracks[0].id, "above the slate")
        var plain = Timeline.empty(name: "VOD", canvas: .landscape1080)
        plain.tracks[0].clips = [TimelineClip(name: "Main", content: .media(assetID: asset), start: 0, sourceDuration: 60)]
        EditPolish.addEndScreen(&plain)
        XCTAssertNil(plain.videoTracks.flatMap(\.clips).first { $0.name == "Next Video" })
        var options = LongFormOptions()
        options.nextVideoAssetID = thumb
        let decoded = try JSONDecoder().decode(LongFormOptions.self, from: JSONEncoder().encode(options))
        XCTAssertEqual(decoded.nextVideoAssetID, thumb)
    }
}
