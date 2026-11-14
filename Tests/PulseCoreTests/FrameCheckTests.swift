import XCTest
@testable import PulseCore

/// #1021: the frame the viewer really renders, judged in CI.
final class FrameCheckTests: XCTestCase {
    /// A 9:16 frame like the sample short: a gradient sky, blocks, a facecam box and a caption line.
    private func picture(width: Int = 180, height: Int = 320, facecam: Bool = true, caption: Bool = true, swapRedBlue: Bool = false,
                         shift: Int = 0) -> [UInt8] {
        var out = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let sy = (y + shift + height) % height
                var r = 40 + sy * 60 / height, g = 30 + sy * 20 / height, b = 80 + sy * 50 / height
                if sy > height * 55 / 100, sy < height * 60 / 100, (x / 22) % 2 == 0 { r = 60; g = 150; b = 90 }
                if facecam, sy > height * 64 / 100, x > width * 6 / 100, x < width * 94 / 100 { r = 48; g = 50; b = 62 }
                if facecam, sy > height * 70 / 100, sy < height * 86 / 100, x > width * 38 / 100, x < width * 62 / 100 { r = 238; g = 200; b = 165 }
                if caption, sy > height * 57 / 100, sy < height * 61 / 100, x > width * 28 / 100, x < width * 72 / 100, (x / 3) % 2 == 0 { r = 255; g = 255; b = 255 }
                let i = (y * width + x) * 4
                out[i] = UInt8(swapRedBlue ? b : r)
                out[i + 1] = UInt8(g)
                out[i + 2] = UInt8(swapRedBlue ? r : b)
            }
        }
        return out
    }

    private func stats(_ pixels: [UInt8], width: Int = 180, height: Int = 320) throws -> RenderedFrame {
        try XCTUnwrap(FrameCheck.stats(rgba: pixels, width: width, height: height))
    }

    func testABlackOrFlatFrameFailsAndARealPictureDoesNot() throws {
        let real = try stats(picture())
        XCTAssertGreaterThan(real.detail, 0.05)
        XCTAssertEqual(real.signature.count, 16 * 16 * 3)
        XCTAssertEqual(FrameCheck.judge(name: "editor", stats: real).verdict, .ok)
        XCTAssertTrue(FrameCheck.judge(name: "editor", stats: real).line.hasPrefix("UI-FRAME editor 180x320 "))

        var black = [UInt8](repeating: 0, count: 180 * 320 * 4)
        for i in stride(from: 3, to: black.count, by: 4) { black[i] = 255 }
        let nothing = FrameCheck.judge(name: "editor", stats: try stats(black))
        XCTAssertEqual(nothing.verdict, .failed)
        XCTAssertTrue(nothing.findings.joined().contains("black"))
        XCTAssertTrue(nothing.line.hasPrefix("UI-FRAME-FAIL editor "))
        XCTAssertEqual(try stats(black).dark, 1)

        var grey = [UInt8](repeating: 128, count: 180 * 320 * 4)
        grey[0] = 129
        let flat = FrameCheck.judge(name: "editor", stats: try stats(grey))
        XCTAssertEqual(flat.verdict, .failed)
        XCTAssertTrue(flat.findings.joined().contains("flat"))

        // A buffer that isn't the size it claims is not judged at all.
        XCTAssertNil(FrameCheck.stats(rgba: [0, 0, 0, 255], width: 180, height: 320))
        XCTAssertNil(FrameCheck.stats(rgba: [], width: 4, height: 4))
    }

    func testTheWrongShapeFails() throws {
        let real = try stats(picture())
        XCTAssertEqual(FrameCheck.judge(name: "editor", stats: real, expectedAspect: 9.0 / 16).verdict, .ok)
        let wide = FrameCheck.judge(name: "editor", stats: real, expectedAspect: 16.0 / 9)
        XCTAssertEqual(wide.verdict, .failed)
        XCTAssertTrue(wide.findings.joined().contains("wide for its height"))
        // A pixel of rounding in the render size is not the wrong shape.
        let near = try stats(picture(width: 181), width: 181)
        XCTAssertEqual(FrameCheck.judge(name: "editor", stats: near, expectedAspect: 9.0 / 16).verdict, .ok)
    }

    func testAChangeFromTheReferenceIsGradedByHowBigItIs() throws {
        let kept = try stats(picture())
        let reference = FrameCheck.Reference(frames: ["editor": FrameCheck.hex(kept.signature)])

        // The same frame again: the same.
        let same = FrameCheck.judge(name: "editor", stats: try stats(picture()), reference: reference)
        XCTAssertEqual(same.verdict, .ok)
        XCTAssertEqual(same.mean, 0)
        XCTAssertEqual(same.findings, ["same as the reference"])

        // The caption gone: a small part of the frame, so "changed", and found by the worst cell, not the mean.
        let uncaptioned = FrameCheck.judge(name: "editor", stats: try stats(picture(caption: false)), reference: reference)
        XCTAssertEqual(uncaptioned.verdict, .changed)
        XCTAssertLessThan(try XCTUnwrap(uncaptioned.mean), FrameCheck.differentMean)
        XCTAssertGreaterThan(try XCTUnwrap(uncaptioned.worst), FrameCheck.sameWorst)
        XCTAssertTrue(uncaptioned.line.hasPrefix("UI-FRAME-CHANGED editor "))

        // The facecam gone, the colours swapped, or the picture moved: not the same picture.
        for broken in [picture(facecam: false), picture(swapRedBlue: true), picture(shift: 60)] {
            let result = FrameCheck.judge(name: "editor", stats: try stats(broken), reference: reference)
            XCTAssertEqual(result.verdict, .failed, result.line)
            XCTAssertTrue(result.findings.joined().contains("not the picture in the reference"))
        }

        // A frame with no reference kept is judged on its own.
        let unknown = FrameCheck.judge(name: "other", stats: kept, reference: reference)
        XCTAssertEqual(unknown.verdict, .ok)
        XCTAssertNil(unknown.mean)
        XCTAssertTrue(unknown.line.contains("no reference kept"))
    }

    func testTheReferenceFileReadsBackAndABrokenOneIsRefused() throws {
        let kept = try stats(picture())
        let reference = FrameCheck.Reference(frames: ["b-frame": FrameCheck.hex(kept.signature), "a-frame": "00ff7f"])
        let text = reference.json
        XCTAssertLessThan(try XCTUnwrap(text.range(of: "a-frame")).lowerBound, try XCTUnwrap(text.range(of: "b-frame")).lowerBound, "names in order")
        let again = try XCTUnwrap(FrameCheck.Reference(json: Data(text.utf8)))
        XCTAssertEqual(again, reference)
        XCTAssertEqual(FrameCheck.signature(hex: "00ff7F"), [0, 255, 127])
        XCTAssertNil(FrameCheck.signature(hex: "0g"))
        XCTAssertNil(FrameCheck.signature(hex: "abc"))
        XCTAssertNil(FrameCheck.Reference(json: Data("not json".utf8)))
        // A reference of another size counts as a different picture, not a crash.
        let odd = FrameCheck.judge(name: "a-frame", stats: kept, reference: reference)
        XCTAssertEqual(odd.verdict, .failed)
        XCTAssertEqual(FrameCheck.distance([1, 2, 3], [1, 2]).mean, 1)
    }
}
