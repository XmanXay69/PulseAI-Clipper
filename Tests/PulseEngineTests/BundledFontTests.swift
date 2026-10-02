import AppKit
import XCTest
@testable import PulseCore
@testable import PulseEngine

final class BundledFontTests: XCTestCase {
    func testTikTokSansLoadsAndItsWeightsDiffer() throws {
        XCTAssertTrue(BundledFonts.isTikTokSansAvailable, "Resources/Fonts/TikTokSans.ttf should register")
        let regular = try XCTUnwrap(BundledFonts.tiktokSans(size: 80, weight: .regular))
        let black = try XCTUnwrap(BundledFonts.tiktokSans(size: 80, weight: .black))
        XCTAssertEqual(regular.familyName, "TikTok Sans")
        func width(_ font: NSFont) -> CGFloat {
            NSAttributedString(string: "CLUTCH MOMENT", attributes: [.font: font]).size().width
        }
        XCTAssertGreaterThan(width(black), width(regular) * 1.04, "black is wider than regular")
        // The renderer picks it for captions using the default preset.
        let font = TextRenderer.font(for: CaptionStyle.tiktok.text, pointSize: 60)
        XCTAssertEqual(font.familyName, "TikTok Sans")
        XCTAssertEqual(CaptionStyle.presets.first?.presetName, "TikTok")
        XCTAssertEqual(AISettings().captionPresetName, "TikTok")
    }
}
