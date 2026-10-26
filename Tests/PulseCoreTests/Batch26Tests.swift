import XCTest
@testable import PulseCore

final class Batch26Tests: XCTestCase {
    // MARK: #221 chroma key

    func testChromaKeyAlphaByHue() {
        let key = ChromaKey.green
        XCTAssertEqual(key.alpha(red: 0, green: 1, blue: 0), 0, "pure green is keyed")
        XCTAssertEqual(key.alpha(red: 1, green: 0, blue: 0), 1, "red stays")
        XCTAssertEqual(key.alpha(red: 0.5, green: 0.5, blue: 0.5), 1, "grey is never keyed")
        XCTAssertEqual(key.alpha(red: 0.02, green: 0.05, blue: 0.02), 1, "near-black shadows stay")
        // 147°: 27° from green, past the ±22.5° band and inside the 9° soft zone.
        let soft = key.alpha(red: 0, green: 1, blue: 0.45)
        XCTAssertGreaterThan(soft, 0)
        XCTAssertLessThan(soft, 1)
        XCTAssertEqual(ChromaKey.blue.alpha(red: 0.1, green: 0.2, blue: 1), 0)
        XCTAssertEqual(ChromaKey.blue.alpha(red: 0, green: 1, blue: 0), 1)
        let (h, s, v) = ChromaKey.hsv(0, 1, 0)
        XCTAssertEqual(h, 120, accuracy: 0.001); XCTAssertEqual(s, 1); XCTAssertEqual(v, 1)
    }

    func testLayerStyleNewFieldsDecodeAndInterpolate() throws {
        let old = try JSONDecoder().decode(LayerStyle.self, from: Data(#"{"mask":"circle","cornerRadius":0.5,"borderWidth":0,"borderColor":{"red":1,"green":1,"blue":1,"alpha":1},"shadowRadius":0,"shadowOpacity":0,"shadowOffsetY":0}"#.utf8))
        XCTAssertNil(old.feather)
        XCTAssertNil(old.chromaKey)
        XCTAssertEqual(old.featherAmount, 0)
        var a = LayerStyle(mask: .circle)
        a.feather = 0.1
        a.chromaKey = .green
        XCTAssertFalse(a.isPlain)
        let b = LayerStyle(mask: .circle)
        XCTAssertEqual(a.interpolated(to: b, 0.25).feather, 0.1)
        XCTAssertNil(a.interpolated(to: b, 0.75).feather)
        XCTAssertEqual(a.interpolated(to: b, 0.25).chromaKey, .green)
        var clamped = LayerStyle()
        clamped.feather = 2
        XCTAssertEqual(clamped.featherAmount, 0.25)
    }

    // MARK: #353 watermark

    func testWatermarkSpecFromBrandKit() throws {
        var kit = BrandKit()
        XCTAssertNil(kit.watermarkSpec)
        kit.logoPath = "/tmp/logo.png"
        kit.logoCorner = .topLeft
        kit.logoSize = 0.2
        kit.logoOpacity = 0.5
        let spec = try XCTUnwrap(kit.watermarkSpec)
        XCTAssertEqual(spec.corner, .topLeft)
        XCTAssertEqual(spec.size, 0.2)
        XCTAssertEqual(spec.opacity, 0.5)
        var settings = ExportSettings()
        XCTAssertNil(settings.watermark)
        settings.watermark = spec
        let back = try JSONDecoder().decode(ExportSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(back.watermark, spec)
        XCTAssertEqual(WatermarkSpec(path: "x", size: 5, opacity: 0).size, 0.5)
        XCTAssertEqual(WatermarkSpec(path: "x", size: 5, opacity: 0).opacity, 0.05)
    }

    // MARK: #311 grade matching

    private func frame(width: Int, height: Int, _ pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> [UInt8] {
        var out = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            let (r, g, b) = pixel(x, y)
            let i = (y * width + x) * 4
            out[i] = r; out[i + 1] = g; out[i + 2] = b
        } }
        return out
    }

    func testFrameStatsAndGradeMatch() throws {
        let dark = frame(width: 16, height: 8) { _, _ in (40, 40, 60) }
        let bright = frame(width: 16, height: 8) { _, _ in (200, 160, 120) }
        let d = try XCTUnwrap(FrameStats.compute(pixels: dark, width: 16, height: 8, bytesPerRow: 64, step: 1))
        let b = try XCTUnwrap(FrameStats.compute(pixels: bright, width: 16, height: 8, bytesPerRow: 64, step: 1))
        XCTAssertLessThan(d.luma, b.luma)
        XCTAssertLessThan(d.warmth, 0); XCTAssertGreaterThan(b.warmth, 0)
        let matched = GradeMatch.match(reference: b, referenceGrade: ColorAdjustments(), target: d, targetGrade: ColorAdjustments())
        XCTAssertGreaterThan(matched.exposure, 1, "the dark clip is pushed up toward the bright reference")
        XCTAssertGreaterThan(matched.temperature, 0, "and warmed up")
        XCTAssertLessThanOrEqual(matched.exposure, 2)
        // Same frame → no change beyond the reference's own grade.
        var refGrade = ColorAdjustments(); refGrade.exposure = 0.3
        let same = GradeMatch.match(reference: b, referenceGrade: refGrade, target: b, targetGrade: ColorAdjustments())
        XCTAssertEqual(same.exposure, 0.3, accuracy: 1e-9)
        XCTAssertEqual(same.saturation, 0, accuracy: 1e-9)
        // BGRA buffers read the same stats.
        let bgra = frame(width: 16, height: 8) { _, _ in (120, 160, 200) }
        let viaBGRA = try XCTUnwrap(FrameStats.compute(pixels: bgra, width: 16, height: 8, bytesPerRow: 64, blueFirst: true, step: 1))
        XCTAssertEqual(viaBGRA.warmth, b.warmth, accuracy: 1e-9)
        XCTAssertNil(FrameStats.compute(pixels: [], width: 4, height: 4, bytesPerRow: 16))
    }

    // MARK: #310 scopes

    func testScopesFromGradientFrame() throws {
        // Left half black, right half white: the waveform sits at the bottom on the left and at the top on the right.
        let pixels = frame(width: 160, height: 90) { x, _ in x < 80 ? (0, 0, 0) : (255, 255, 255) }
        let scopes = try XCTUnwrap(ScopeData.compute(pixels: pixels, width: 160, height: 90, bytesPerRow: 640, columns: 8, bins: 8, grid: 8))
        XCTAssertEqual(scopes.waveform.count, 8)
        XCTAssertEqual(scopes.waveform[0][0], 1, "left columns peak in the black bin")
        XCTAssertEqual(scopes.waveform[0][7], 0)
        XCTAssertEqual(scopes.waveform[7][7], 1, "right columns peak in the white bin")
        XCTAssertEqual(scopes.clippedShare, 0.5, accuracy: 0.02)
        XCTAssertEqual(scopes.crushedShare, 0.5, accuracy: 0.02)
        // Neutral frame: the vectorscope energy sits at the centre.
        let centre = scopes.vectorscope[4 * 8 + 4] + scopes.vectorscope[3 * 8 + 3] + scopes.vectorscope[3 * 8 + 4] + scopes.vectorscope[4 * 8 + 3]
        XCTAssertGreaterThan(centre, 0.9)
        XCTAssertNil(ScopeData.compute(pixels: [], width: 2, height: 2, bytesPerRow: 8))
    }
}
