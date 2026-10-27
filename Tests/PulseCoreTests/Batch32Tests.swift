import XCTest
@testable import PulseCore

final class Batch32Tests: XCTestCase {
    func testAppearanceDefaultsToDark() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.appearance, .dark)
        XCTAssertEqual(AppAppearance.allCases.count, 3)
    }

    func testWordPopStaggersWords() {
        let first = TextAnimation.wordPop(index: 0, count: 4, progress: 0.35)
        let last = TextAnimation.wordPop(index: 3, count: 4, progress: 0.35)
        XCTAssertEqual(first.alpha, 1, accuracy: 1e-9, "the first word has landed")
        XCTAssertEqual(first.scale, 1, accuracy: 1e-9)
        XCTAssertEqual(last.alpha, 0, "the last word (starts at 0.525) hasn't started")
        let rising = TextAnimation.wordPop(index: 0, count: 4, progress: 0.15)
        XCTAssertEqual(rising.alpha, 0.8, accuracy: 1e-9, "half way through its own 30 % window")
        let done = TextAnimation.wordPop(index: 3, count: 4, progress: 1)
        XCTAssertEqual(done.scale, 1, accuracy: 1e-9)
        XCTAssertEqual(done.alpha, 1)
        let mid = TextAnimation.wordPop(index: 0, count: 4, progress: 0.1)
        XCTAssertGreaterThan(mid.scale, 0.6)
        XCTAssertEqual(TextAnimation(rawValue: "wordPop"), .wordPop)
        XCTAssertEqual(TextAnimation.wordPop.displayName, "Word Pop")
    }

    func testBrandKitPlatformVariants() throws {
        var kit = BrandKit()
        kit.logoCorner = .topRight
        kit.logoSize = 0.14
        XCTAssertEqual(kit.resolved(for: .tiktok).logoCorner, .topRight, "no variant: the kit as it is")
        kit.platformVariants[SafeAreaPlatform.tiktok.rawValue] = BrandKit.PlatformVariant(logoCorner: .bottomLeft, logoSize: 0.1, showLogo: false)
        let tiktok = kit.resolved(for: .tiktok)
        XCTAssertEqual(tiktok.logoCorner, .bottomLeft)
        XCTAssertEqual(tiktok.logoSize, 0.1)
        XCTAssertFalse(tiktok.logoOnShorts)
        XCTAssertEqual(tiktok.logoOpacity, kit.logoOpacity, "untouched fields follow the kit")
        XCTAssertEqual(kit.resolved(for: .youtubeShorts).logoCorner, .topRight)
        XCTAssertEqual(kit.resolved(for: nil).logoSize, 0.14)
        let back = try JSONDecoder().decode(BrandKit.self, from: JSONEncoder().encode(kit))
        XCTAssertEqual(back.platformVariants, kit.platformVariants)
        let old = try JSONDecoder().decode(BrandKit.self, from: Data("{}".utf8))
        XCTAssertTrue(old.platformVariants.isEmpty)
        XCTAssertTrue(BrandKit.PlatformVariant().isEmpty)
    }
}
