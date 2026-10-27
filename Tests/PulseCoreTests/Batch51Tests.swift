import XCTest
@testable import PulseCore

final class Batch51Tests: XCTestCase {
    // MARK: #494 — review from a phone

    func testRoutesNeedTheTokenAndParseActions() {
        let token = "abc123def4"
        let id = UUID()
        XCTAssertEqual(PhoneReview.route(path: "/r/abc123def4", token: token), .page)
        XCTAssertEqual(PhoneReview.route(path: "/r/abc123def4/", token: token), .page)
        XCTAssertEqual(PhoneReview.route(path: "/r/abc123def4/state", token: token), .state)
        XCTAssertEqual(PhoneReview.route(path: "/r/abc123def4/thumb/\(id.uuidString).jpg", token: token), .thumb(id))
        XCTAssertEqual(PhoneReview.route(path: "/r/abc123def4/act?id=\(id.uuidString)&do=approve", token: token), .act(id, .approve))
        XCTAssertEqual(PhoneReview.route(path: "/r/abc123def4/act?do=undo&id=\(id.uuidString)", token: token), .act(id, .undo))
        XCTAssertNil(PhoneReview.route(path: "/r/abc123def4/act?id=nope&do=approve", token: token))
        XCTAssertNil(PhoneReview.route(path: "/r/abc123def4/act?id=\(id.uuidString)&do=delete", token: token))
        XCTAssertNil(PhoneReview.route(path: "/r/wrongtoken/state", token: token), "the token is the key")
        XCTAssertNil(PhoneReview.route(path: "/r/abc123def4x/state", token: token))
        XCTAssertNil(PhoneReview.route(path: "/", token: token))
        XCTAssertNil(PhoneReview.route(path: "/r/abc123def4/thumb/x.jpg", token: token))
        XCTAssertEqual(PhoneReview.token().count, 10)
        XCTAssertNotEqual(PhoneReview.token(), PhoneReview.token())
        XCTAssertEqual(PhoneReview.path(token: token), "/r/abc123def4")
    }

    func testPageListsItemsEscapedAndStateEncodes() throws {
        let id = UUID()
        let items = [PhoneReview.Item(id: id, title: "Clutch <1v3>", subtitle: "0:28 · \"no way\"", potential: 87, status: .new),
                     PhoneReview.Item(id: UUID(), title: "Rage", subtitle: "0:20", potential: 60, status: .rejected)]
        let html = PhoneReview.html(items: items, projectName: "Ranked & Chill", token: "tok")
        XCTAssertTrue(html.contains("Clutch &lt;1v3&gt;"))
        XCTAssertTrue(html.contains("Ranked &amp; Chill"))
        XCTAssertTrue(html.contains("/r/tok/thumb/\(id.uuidString).jpg"))
        XCTAssertTrue(html.contains("act('\(id.uuidString)','approve')"))
        XCTAssertTrue(html.contains("class=\"card rejected\""))
        XCTAssertTrue(html.contains("viewport"), "phone-sized")
        let back = try JSONDecoder().decode([PhoneReview.Item].self, from: PhoneReview.stateJSON(items: items))
        XCTAssertEqual(back, items)
    }

    // MARK: #496 — sound packs with ratings

    func testRatingsSortTheLibraryAndPacksRoundTrip() throws {
        let sounds = Array(SoundLibrary.catalog.prefix(5))
        XCTAssertEqual(sounds.count, 5)
        let ratings = [sounds[1].id: 5, sounds[3].id: 1, sounds[4].id: 3]
        let sorted = SoundLibrary.sorted(sounds, ratings: ratings)
        XCTAssertEqual(sorted.map(\.id), [sounds[1].id, sounds[0].id, sounds[2].id, sounds[4].id, sounds[3].id])
        XCTAssertEqual(SoundLibrary.sorted(sounds, ratings: [:]).map(\.id), sounds.map(\.id), "no ratings: the order stays")

        var settings = AISettings()
        settings.preferredEffects = ["hit": "Impact", "whoosh": "Whoosh"]
        settings.soundRatings = [sounds[1].id: 5, "bogus": 9]
        let pack = SoundPackManifest.current(settings, name: "Night Pack", author: "@me")
        XCTAssertEqual(pack.ratings, [sounds[1].id: 5], "out-of-range stars are dropped")
        let data = try pack.data()
        let parsed = try XCTUnwrap(SoundPackManifest.parse(data))
        XCTAssertEqual(parsed, pack)
        XCTAssertNil(SoundPackManifest.parse(Data("nope".utf8)))

        var other = AISettings()
        other.soundRatings = [sounds[1].id: 2, sounds[2].id: 4]
        let taken = parsed.apply(to: &other)
        XCTAssertEqual(other.preferredEffects, pack.preferences)
        XCTAssertEqual(taken, 0, "an existing rating is kept")
        XCTAssertEqual(other.soundRatings[sounds[1].id], 2)
        XCTAssertEqual(parsed.apply(to: &other, replaceRatings: true), 1)
        XCTAssertEqual(other.soundRatings[sounds[1].id], 5)
        XCTAssertEqual(other.soundRatings[sounds[2].id], 4, "ratings the pack doesn't mention survive")
        let old = try JSONDecoder().decode(AISettings.self, from: Data("{}".utf8))
        XCTAssertTrue(old.soundRatings.isEmpty)
    }
}
