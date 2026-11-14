import XCTest
@testable import PulseCore

/// #721: a caption page that goes by faster than about twenty characters a second is split into smaller ones.
final class CaptionReadingSpeedTests: XCTestCase {
    /// `texts` spoken back to back, each word `each` seconds long, starting at `start`.
    private func words(_ texts: [String], each: Seconds, start: Seconds = 0) -> [TimedCaptionWord] {
        texts.enumerated().map { i, text in
            TimedCaptionWord(id: UUID(), text: text, start: start + Double(i) * each, end: start + Double(i + 1) * each - 0.02,
                             isEmphasized: false, speaker: nil)
        }
    }

    private func style(limit: Double) -> CaptionStyle {
        var style = CaptionStyle.clean
        style.maxWordsPerPage = 8
        style.maxCharsPerLine = 34
        style.maxLines = 2
        style.readingSpeedLimit = limit
        return style
    }

    func testUnhurriedSpeechKeepsItsPages() {
        // Six five-letter words over three seconds: about 12 characters a second.
        let spoken = words(["these", "words", "arrive", "at", "an", "easy", "pace", "today"], each: 0.5)
        let plain = CaptionLayoutEngine.pages(spoken, style: style(limit: 0))
        let limited = CaptionLayoutEngine.pages(spoken, style: style(limit: 20))
        XCTAssertEqual(plain.map(\.text), limited.map(\.text))
        XCTAssertEqual(limited.count, 1)
    }

    func testAPageThatGoesByTooFastIsSplitAtAPhraseBoundary() {
        // Eight words in 1.2 s with a following page right behind: about 35 characters a second.
        let burst = words(["honestly,", "nobody", "expected", "that", "ending", "to", "actually", "work"], each: 0.15)
            + words(["and", "then", "it", "did."], each: 0.4, start: 1.25)
        let plain = CaptionLayoutEngine.pages(burst, style: style(limit: 0))
        let limited = CaptionLayoutEngine.pages(burst, style: style(limit: 20))
        XCTAssertEqual(plain.first?.words.count, 8, "without the limit the burst is one page")
        XCTAssertGreaterThan(limited.count, plain.count)
        // No word is lost or reordered, and every page still starts when its first word is spoken.
        XCTAssertEqual(limited.flatMap(\.words).map(\.text), burst.map(\.text))
        for page in limited { XCTAssertEqual(page.range.start, page.words[0].start, accuracy: 0.001) }
        XCTAssertTrue(zip(limited, limited.dropFirst()).allSatisfy { $0.range.end <= $1.range.start + 0.001 })
        // The comma is where the first split lands.
        XCTAssertTrue(limited.contains { $0.words.last?.text == "honestly," } || limited[0].words.count <= 4)
        // The small pages left are ones a glance takes in: a few words or under the fast limit.
        for (i, page) in limited.enumerated() where page.words.count > 2 {
            let characters = page.text.replacingOccurrences(of: "\n", with: " ").count
            let next = i + 1 < limited.count ? limited[i + 1].range.start : .infinity
            let speed = CaptionLayoutEngine.readingSpeed(page.words, nextStart: next)
            XCTAssertTrue(characters <= CaptionLayoutEngine.glanceableCharacters || speed <= 20.5, "\(page.text) at \(speed)")
        }
        // The slower page after the burst is left whole.
        XCTAssertEqual(limited.last?.text.replacingOccurrences(of: "\n", with: " "), "and then it did.")
    }

    func testOneWordAtATimeAndHandBreaksAreUntouched() {
        var karaoke = style(limit: 20)
        karaoke.displayMode = .wordByWord
        let burst = words(["one", "two", "three", "four"], each: 0.08)
        XCTAssertEqual(CaptionLayoutEngine.pages(burst, style: karaoke).count, 4)

        // A break set by hand still ends its page; splitting only ever adds breaks.
        var handBroken = words(["a", "break", "set", "by", "hand", "stays"], each: 0.5)
        handBroken[1].breakAfter = true
        let pages = CaptionLayoutEngine.pages(handBroken, style: style(limit: 20))
        XCTAssertEqual(pages[0].words.map(\.text), ["a", "break"])
    }

    func testNewCaptionsUseTheStandardAndSavedOnesKeepTheirPages() throws {
        XCTAssertEqual(CaptionStyle.tiktok.readingSpeedLimit, 20)
        XCTAssertEqual(CaptionStyle.standardReadingSpeed, 20)
        var style = CaptionStyle.clean
        style.readingSpeedLimit = 17
        let saved = try JSONDecoder().decode(CaptionStyle.self, from: JSONEncoder().encode(style))
        XCTAssertEqual(saved.readingSpeedLimit, 17)
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(style)) as? [String: Any])
        json["readingSpeedLimit"] = nil
        let older = try JSONDecoder().decode(CaptionStyle.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(older.readingSpeedLimit, 0, "a project saved before this version isn't re-paged")
    }
}
