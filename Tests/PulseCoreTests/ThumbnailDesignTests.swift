import XCTest
@testable import PulseCore

/// A stand-in for Thumbnail Studio's own `ThumbLayer.Kind`, which uses Swift's synthesized enum
/// coding. If PULSE's hand-written encoding ever drifts from that, this decode fails.
private struct StudioImage: Codable { var path: String }
private struct StudioText: Codable { var text: String }
private struct StudioShape: Codable { var shape: String }
private enum StudioKind: Codable {
    case image(StudioImage)
    case text(StudioText)
    case shape(StudioShape)
}
private struct StudioLayer: Codable { var kind: StudioKind; var x: Double; var y: Double }
private struct StudioDocument: Codable { var width: Int; var height: Int; var layers: [StudioLayer] }

final class ThumbnailDesignTests: XCTestCase {
    func candidate(payoff: Seconds, potential: Int, title: String = "He rage quit — then came back") -> ClipCandidate {
        ClipCandidate(assetID: UUID(), range: TimeRange(start: payoff - 10, end: payoff + 5), payoffTime: payoff, targetDuration: 15,
                      potential: potential,
                      scores: ClipScores(hook: 0.6, emotion: 0.6, story: 0.5, entertainment: 0.6, audio: 0.5, visual: 0.4, reaction: 0.7, context: 0.7, ending: 0.6),
                      tags: [.funny], title: title, copy: .empty, transcriptSnippet: "")
    }

    func testDesignsDecodeWithSynthesizedCodingLikeTheStudio() throws {
        for layout in ThumbnailLayout.allCases {
            let doc = ThumbnailDesigner.design(layout, framePath: "/tmp/frame.jpg", sourceAspect: 16.0 / 9.0,
                                               face: NormRect(x: 0.6, y: 0.2, width: 0.15, height: 0.25),
                                               headline: "NO WAY", logoPath: "/tmp/logo.png")
            let data = try JSONEncoder().encode(doc)
            XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"_0\""))
            let decoded = try JSONDecoder().decode(StudioDocument.self, from: data)
            XCTAssertEqual(decoded.width, 1280)
            XCTAssertEqual(decoded.height, 720)
            guard case .image(let frame) = decoded.layers.first?.kind else { return XCTFail("frame must be the bottom layer") }
            XCTAssertEqual(frame.path, "/tmp/frame.jpg")
            XCTAssertTrue(decoded.layers.contains { if case .text(let t) = $0.kind { return t.text == "NO WAY" } else { return false } })
            // And PULSE reads its own output back.
            XCTAssertEqual(try JSONDecoder().decode(ThumbStudioDocument.self, from: data), doc)
        }
    }

    func testTextStaysClearOfTheDurationBadge() {
        let badge = ThumbnailDesigner.durationBadge
        for layout in ThumbnailLayout.allCases {
            let doc = ThumbnailDesigner.design(layout, framePath: "f", sourceAspect: 16.0 / 9.0, face: nil, headline: "THIS IS INSANE", logoPath: "l")
            for layer in doc.layers {
                var isText = false
                if case .text = layer.kind { isText = true }
                guard isText || layer.name == "Logo" else { continue }
                let right = layer.x + layer.widthFraction / 2
                let bottom = layer.y + layer.heightFraction / 2
                XCTAssertFalse(right > badge.minX && bottom > badge.minY, "\(layout) \(layer.name) overlaps the duration badge")
            }
        }
    }

    func testCoverCropKeepsTheCanvasAspect() {
        let full = ThumbnailDesigner.coverCrop(sourceAspect: 16.0 / 9.0)
        XCTAssertEqual(full, ThumbStudioRect(x: 0, y: 0, width: 1, height: 1))

        let fourThree = ThumbnailDesigner.coverCrop(sourceAspect: 4.0 / 3.0)
        XCTAssertEqual(fourThree.width, 1, accuracy: 1e-9)
        XCTAssertEqual(fourThree.height, 0.75, accuracy: 1e-9)
        XCTAssertEqual(fourThree.y, 0.125, accuracy: 1e-9)

        // Zoomed toward a corner: clamped inside the frame.
        let corner = ThumbnailDesigner.coverCrop(sourceAspect: 16.0 / 9.0, focus: Vec2(0.95, 0.05), zoom: 2)
        XCTAssertEqual(corner.width, 0.5, accuracy: 1e-9)
        XCTAssertEqual(corner.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(corner.y, 0, accuracy: 1e-9)

        // Vertical phone footage → a 16:9 slice across the middle.
        let vertical = ThumbnailDesigner.coverCrop(sourceAspect: 9.0 / 16.0)
        XCTAssertEqual(vertical.width, 1, accuracy: 1e-9)
        XCTAssertEqual(vertical.height, (9.0 / 16.0) / (16.0 / 9.0), accuracy: 1e-9)
        XCTAssertEqual(vertical.y, (1 - vertical.height) / 2, accuracy: 1e-9)
    }

    func testHeadlinesAreShortAndClean() {
        XCTAssertEqual(ThumbnailHeadline.make(from: "He rage quit — then came back 😭 #shorts"), "He rage quit")
        XCTAssertEqual(ThumbnailHeadline.make(from: "No way!"), "No way!")
        XCTAssertEqual(ThumbnailHeadline.make(from: "I can't believe this actually happened on stream"), "I can't believe this")
        XCTAssertEqual(ThumbnailHeadline.make(from: "😭😭😭"), "NO WAY")
        XCTAssertEqual(ThumbnailHeadline.make(from: "“DID SEE THAT?” 🔥"), "DID SEE THAT?")
    }

    func testPicksStrongestMomentsSpacedApartAndPrefersTheFace() {
        let faces = [FaceSample(time: 99, boxes: [NormRect(x: 0.4, y: 0.2, width: 0.3, height: 0.4)])]
        let visual = VisualFeatureSeries(hop: 1, motion: [Float](repeating: 0.02, count: 400), brightness: [Float](repeating: 0.5, count: 400),
                                         sceneCuts: [], faces: faces)
        var analysis = MediaAnalysis(assetID: UUID(), duration: 400)
        analysis.visual = visual
        let best = candidate(payoff: 100, potential: 90)
        let tooClose = candidate(payoff: 108, potential: 80)
        let other = candidate(payoff: 300, potential: 70, title: "Chat made me do it")
        let picks = ThumbnailPicker.pick(candidates: [other, tooClose, best], analysis: analysis, count: 4)
        XCTAssertEqual(picks.count, 2)
        XCTAssertEqual(picks[0].candidateID, best.id)
        XCTAssertEqual(picks[0].time, 99, "moves to the frame with the big face")
        XCTAssertNotNil(picks[0].face)
        XCTAssertEqual(picks[0].headline, "He rage quit")
        XCTAssertEqual(picks[1].candidateID, other.id)

        // Limited to an edit's source ranges.
        let inEdit = ThumbnailPicker.pick(candidates: [other, best], analysis: analysis, within: [TimeRange(start: 250, end: 320)])
        XCTAssertEqual(inEdit.map(\.candidateID), [other.id])
    }

    func testDesignNamesFitTheStudioGallery() {
        let name = ThumbnailDesigner.designName(project: "Friday Night Stream: Elden Ring", headline: "HE RAGE QUIT / AGAIN", layout: .faceZoom)
        XCTAssertLessThanOrEqual(name.count, 60)
        XCTAssertFalse(name.contains("/"))
        XCTAssertTrue(name.contains("Face Zoom") || name.count == 60)
        XCTAssertEqual(ThumbnailDesigner.hex(RGBAColor(red: 1, green: 0.5, blue: 0)), "FF8000")
    }
}
