import XCTest
@testable import PulseCore

final class Batch29Tests: XCTestCase {
    func testKeyComboParsingAndDisplay() {
        XCTAssertEqual(KeyCombo.parse("⌥⇧⌘K"), KeyCombo("k", shift: true, option: true))
        XCTAssertEqual(KeyCombo.parse("cmd+shift+k"), KeyCombo("k", shift: true))
        XCTAssertEqual(KeyCombo.parse("ctrl-alt-delete"), KeyCombo("delete", command: false, option: true, control: true))
        XCTAssertEqual(KeyCombo.parse("⇧F"), KeyCombo("f", command: false, shift: true))
        XCTAssertEqual(KeyCombo.parse("  ⌘=  "), KeyCombo("="))
        XCTAssertNil(KeyCombo.parse(""))
        XCTAssertNil(KeyCombo.parse("cmd+"))
        XCTAssertNil(KeyCombo.parse("bogus+k"))
        XCTAssertEqual(KeyCombo("k", shift: true, option: true, control: true).display, "⌃⌥⇧⌘K")
        XCTAssertEqual(KeyCombo("delete", command: false, shift: true).display, "⇧⌫")
        XCTAssertEqual(KeyCombo.parse(KeyCombo("space", option: true).display), KeyCombo("space", option: true))
    }

    func testShortcutMapDefaultsCustomAndConflicts() throws {
        var map = ShortcutMap()
        XCTAssertEqual(map.combo(for: .splitAtPlayhead), KeyCombo("k"))
        XCTAssertTrue(map.allConflicts.isEmpty, "the defaults never collide: \(map.allConflicts)")
        map.set(KeyCombo("d"), for: .splitAtPlayhead)
        XCTAssertTrue(map.isCustom(.splitAtPlayhead))
        XCTAssertEqual(map.conflicts(for: KeyCombo("d"), excluding: .splitAtPlayhead), ["Duplicate"])
        XCTAssertEqual(map.allConflicts.count, 2, "both sides of the collision are reported")
        XCTAssertEqual(map.conflicts(for: KeyCombo("s"), excluding: .takeSnapshot), ["Save"], "reserved Mac shortcuts count")
        map.set(KeyCombo("k"), for: .splitAtPlayhead)
        XCTAssertFalse(map.isCustom(.splitAtPlayhead), "setting the default clears the custom entry")
        map.set(nil, for: .duplicate)
        XCTAssertEqual(map.combo(for: .duplicate), KeyCombo("d"))
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(settings.shortcuts.custom.isEmpty)
        XCTAssertTrue(settings.recentFonts.isEmpty)
    }

    func testRecentFonts() {
        var settings = AppSettings()
        for name in ["Inter", "Montserrat", "Inter", "A", "B", "C", "D", "E"] { settings.noteRecentFont(name) }
        XCTAssertEqual(settings.recentFonts.count, 6)
        XCTAssertEqual(settings.recentFonts.first, "E")
        XCTAssertFalse(settings.recentFonts.contains("Montserrat"), "the oldest drops off")
        settings.noteRecentFont("")
        XCTAssertEqual(settings.recentFonts.count, 6)
    }
}
