import XCTest
@testable import PulseCore

final class Batch27Tests: XCTestCase {
    func testCaptionStyleNewFieldsDefaultForOldStyles() throws {
        let old = try JSONDecoder().decode(CaptionStyle.self, from: Data(#"{"presetName":"Old"}"#.utf8))
        XCTAssertEqual(old.speakerLabelStyle, .text)
        XCTAssertEqual(old.backgroundStyle, .solid)
        var style = CaptionStyle.tiktok
        style.speakerLabelStyle = .chip
        style.backgroundStyle = .frosted
        let back = try JSONDecoder().decode(CaptionStyle.self, from: JSONEncoder().encode(style))
        XCTAssertEqual(back.speakerLabelStyle, .chip)
        XCTAssertEqual(back.backgroundStyle, .frosted)
    }

    func testAutoWhiteBalanceCountsAsAnAdjustment() throws {
        var c = ColorAdjustments()
        XCTAssertTrue(c.isIdentity)
        c.autoWhiteBalance = true
        XCTAssertTrue(c.hasAdjustments)
        let decoded = try JSONDecoder().decode(ColorAdjustments.self, from: Data("{}".utf8))
        XCTAssertFalse(decoded.autoWhiteBalance)
    }

    func testEffectVariationsResample() {
        let ramp: [[Float]] = [(0..<1000).map { Float($0) / 999 }]
        let up = SoundEffectSynth.vary(ramp, semitones: 12)
        XCTAssertEqual(up[0].count, 500, "an octave up plays twice as fast")
        XCTAssertEqual(up[0][250], 0.5, accuracy: 0.01)
        let down = SoundEffectSynth.vary(ramp, semitones: -12)
        XCTAssertEqual(down[0].count, 2000)
        XCTAssertEqual(down[0][1000], 0.5, accuracy: 0.01)
        XCTAssertEqual(SoundEffectSynth.vary(ramp, semitones: 0)[0].count, 1000)
        XCTAssertTrue(SoundEffectSynth.vary([], semitones: 3).isEmpty)
        let whoosh = SoundLibrary.effects[0]
        let plain = SoundLibrary.render(whoosh)
        let varied = SoundLibrary.render(whoosh, semitones: 5)
        XCTAssertLessThan(varied[0].count, plain[0].count)
        XCTAssertEqual(SoundLibrary.variantName(whoosh, semitones: -2), "Whoosh −2")
        XCTAssertEqual(SoundLibrary.variantName(whoosh, semitones: 5), "Whoosh +5")
        XCTAssertEqual(SoundLibrary.variantName(whoosh, semitones: 0), "Whoosh")
        XCTAssertEqual(SoundLibrary.variations.count, 4)
    }
}
