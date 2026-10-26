import XCTest
@testable import PulseCore

/// Roadmap batch 4: folder imports (#2), clip-it markers (#318), layouts by content (#57).
final class Batch4Tests: XCTestCase {
    func testFoldersExpandToTheirMediaInNameOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-folders-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["stream 10.mp4", "stream 2.mkv", "notes.txt", ".hidden.mp4", "chat.srt", "cover.png"] {
            try Data("x".utf8).write(to: root.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appendingPathComponent("sub/deep.mp4"))
        let loose = root.appendingPathComponent("stream 2.mkv")

        let expanded = ImportPlan.expandingFolders([loose, root, root.appendingPathComponent("missing")])
        XCTAssertEqual(expanded.map(\.lastPathComponent), ["stream 2.mkv", "chat.srt", "cover.png", "stream 2.mkv", "stream 10.mp4"],
                       "loose files pass through first; the folder's files follow in natural name order; one level only")
        XCTAssertTrue(ImportPlan.expandingFolders([]).isEmpty)
    }

    func testMarkedMomentsSurviveOldProjectsAndScoreLikeAWin() throws {
        let asset = Fixtures.mediaAsset()
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(asset)) as! [String: Any]
        json.removeValue(forKey: "markedMoments")
        let decoded = try JSONDecoder().decode(MediaAsset.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(decoded.markedMoments.isEmpty)
        var marked = asset
        marked.markedMoments = [12.5, 300]
        let round = try JSONDecoder().decode(MediaAsset.self, from: JSONEncoder().encode(marked))
        XCTAssertEqual(round.markedMoments, [12.5, 300])

        let event = HUDEvent(time: 300, kind: .marked, text: "CLIP IT")
        XCTAssertEqual(event.kind.weight, HUDEvent.Kind.win.weight)
        XCTAssertEqual(event.kind.tag, .hype)
        let signal = HUDCues.signal(events: [event], duration: 600, step: 0.5)
        XCTAssertGreaterThan(signal[signal.indices.max { signal[$0] < signal[$1] }!], 0.9)
        XCTAssertNil(HUDCues.event(forText: "CLIP IT", at: 1), "not a phrase the screen reader matches")
    }

    func testPreferredLayoutFollowsTheContent() {
        XCTAssertEqual(StreamSetup.Content.shooter.preferredLayout, .facecamCorner)
        XCTAssertEqual(StreamSetup.Content.battleRoyale.preferredLayout, .facecamCorner)
        XCTAssertEqual(StreamSetup.Content.justChatting.preferredLayout, .facecamDominant)
        XCTAssertEqual(StreamSetup.Content.podcast.preferredLayout, .fullFrame)
        XCTAssertEqual(StreamSetup.Content.variety.preferredLayout, .splitScreen)
        for content in StreamSetup.Content.allCases {
            XCTAssertNotEqual(content.preferredLayout, .dynamic, "a fixed base layout; Dynamic stays a choice")
        }
    }
}
