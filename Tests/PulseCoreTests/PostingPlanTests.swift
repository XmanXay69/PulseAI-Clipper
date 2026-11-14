import XCTest
@testable import PulseCore

/// #906: a week of posts across platforms from the clips at hand.
final class PostingPlanTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Monday 2 November 2026, mid-afternoon.
    private var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 15, minute: 40))! }

    private let recording = UUID()

    private func short(_ title: String, _ potential: Int, at start: Seconds, built: Bool = true) -> PostingItem {
        PostingItem(title: title, potential: potential, source: TimeRange(start: start, end: start + 30), assetID: recording, isBuilt: built)
    }

    private func dayIndex(_ date: Date) -> Int { calendar.dateComponents([.day], from: calendar.startOfDay(for: monday), to: calendar.startOfDay(for: date)).day! }

    func testAWeekLeadsWithTheStrongestShortAndPutsEachOnEveryPlatform() throws {
        let items = [short("C", 60, at: 300), short("A", 90, at: 100), short("B", 75, at: 200)]
        var options = PostingPlanner.Options(start: monday)
        options.platforms = [.tiktok, .youtubeShorts, .instagramReels]
        let plan = PostingPlanner.plan(items: items, options: options, calendar: calendar)
        XCTAssertEqual(plan.slots.count, 9, "three shorts on three platforms")
        // The strongest goes first; three shorts are spread over the week, not posted on three days running.
        let firstDay = plan.slots.filter { dayIndex($0.date) == 0 }
        XCTAssertEqual(Set(firstDay.map(\.title)), ["A"])
        XCTAssertEqual(Set(firstDay.map(\.platform)), [.tiktok, .youtubeShorts, .instagramReels])
        XCTAssertEqual(Set(plan.slots.map { dayIndex($0.date) }), [0, 2, 4])
        XCTAssertEqual(plan.slots.filter { $0.title == "B" }.map { dayIndex($0.date) }.first, 2)
        // Each platform at its own time of day, in order through the day.
        let times = firstDay.sorted { $0.date < $1.date }.map { "\(calendar.component(.hour, from: $0.date)):\(calendar.component(.minute, from: $0.date)) \($0.platform.rawValue)" }
        XCTAssertEqual(times, ["12:30 instagramReels", "17:0 youtubeShorts", "19:30 tiktok"])
        XCTAssertTrue(plan.leftovers.isEmpty)
        XCTAssertEqual(plan.summary(calendar: calendar), "9 posts of 3 shorts over 3 days")
    }

    func testTheBestShortIsTheLongVideosTrailerAndLaterShortsPointBackAtIt() throws {
        let long = PostingItem(title: "Full video", isLong: true, potential: 80, assetID: recording)
        let items = [long, short("A", 90, at: 100), short("B", 75, at: 200), short("C", 60, at: 300)]
        var options = PostingPlanner.Options(start: monday)
        options.platforms = [.tiktok, .youtube]
        options.longVideoDay = 3
        let plan = PostingPlanner.plan(items: items, options: options, calendar: calendar)
        let video = try XCTUnwrap(plan.slots.first { $0.platform == .youtube })
        XCTAssertEqual(dayIndex(video.date), 3)
        XCTAssertEqual(calendar.component(.hour, from: video.date), 16)
        let trailer = try XCTUnwrap(plan.slots.first { $0.title == "A" })
        XCTAssertEqual(dayIndex(trailer.date), 2, "the day before the video")
        XCTAssertTrue(trailer.note.contains("trailer"), trailer.note)
        // A short of the same recording that goes out after the video links back to it; one before it doesn't.
        for slot in plan.slots where slot.platform == .tiktok && slot.title != "A" {
            XCTAssertEqual(slot.note.contains("link the full video"), dayIndex(slot.date) >= 3, "\(slot.title) on day \(dayIndex(slot.date)): \(slot.note)")
        }
        // No two shorts share a day when there is room, and a second long video waits.
        XCTAssertEqual(Set(plan.slots.filter { $0.platform == .tiktok }.map { dayIndex($0.date) }).count, 3)
        let two = PostingPlanner.plan(items: items + [PostingItem(title: "Another video", isLong: true, potential: 50)], options: options, calendar: calendar)
        XCTAssertTrue(two.leftovers.contains { $0.title == "Another video" })
        XCTAssertEqual(two.slots.filter { $0.platform == .youtube }.count, 1)
    }

    func testTheSameMomentIsPostedOnceAndAFullWeekSaysWhatWaits() {
        var options = PostingPlanner.Options(start: monday, days: 3)
        options.platforms = [.tiktok]
        // Two clips of the same thirty seconds: the stronger goes out, the other says why it doesn't.
        let twins = PostingPlanner.plan(items: [short("Wide", 80, at: 100), short("Tight", 70, at: 105), short("Other", 60, at: 400)], options: options, calendar: calendar)
        XCTAssertEqual(Set(twins.slots.map(\.title)), ["Wide", "Other"])
        XCTAssertTrue(twins.leftovers.contains { $0.title == "Tight" && $0.reason.contains("Wide") })
        // Five shorts, three days, one a day: two wait for next week. Two a day takes them all.
        let five = (0..<5).map { short("S\($0)", 90 - $0, at: Double($0) * 200) }
        let tight = PostingPlanner.plan(items: five, options: options, calendar: calendar)
        XCTAssertEqual(tight.slots.count, 3)
        XCTAssertEqual(tight.leftovers.count, 2)
        XCTAssertTrue(tight.leftovers.allSatisfy { $0.reason.contains("next week") })
        options.shortsPerDay = 2
        let roomy = PostingPlanner.plan(items: five, options: options, calendar: calendar)
        XCTAssertEqual(roomy.slots.count, 5)
        XCTAssertLessThanOrEqual(Dictionary(grouping: roomy.slots, by: { dayIndex($0.date) }).values.map(\.count).max() ?? 9, 2)
        // A clip card that isn't a short yet is planned and marked.
        let card = PostingPlanner.plan(items: [short("Card", 80, at: 0, built: false)], options: options, calendar: calendar)
        XCTAssertEqual(card.slots.first?.needsBuilding, true)
        // Nothing to post, or no platform ticked: an empty plan that says so.
        XCTAssertEqual(PostingPlanner.plan(items: [], options: options, calendar: calendar).summary(calendar: calendar), "Nothing to post yet")
        options.platforms = []
        let nowhere = PostingPlanner.plan(items: five, options: options, calendar: calendar)
        XCTAssertTrue(nowhere.slots.isEmpty)
        XCTAssertEqual(nowhere.leftovers.count, 5)
    }

    func testYourOwnTimesAreKeptAndThePlanExportsAsTextAndACalendarFile() throws {
        var options = PostingPlanner.Options(start: monday, days: 2)
        options.platforms = [.tiktok]
        options.times = [.tiktok: 21 * 60 + 15]
        let plan = PostingPlanner.plan(items: [short("Clutch, again; really", 80, at: 0), short("Fail", 70, at: 300)], options: options, calendar: calendar)
        XCTAssertEqual(plan.slots.map { calendar.component(.hour, from: $0.date) * 60 + calendar.component(.minute, from: $0.date) }, [21 * 60 + 15, 21 * 60 + 15])

        let text = plan.text(calendar: calendar, locale: Locale(identifier: "en_GB"))
        XCTAssertTrue(text.contains("Monday 2 Nov"), text)
        XCTAssertTrue(text.contains("21:15  TikTok: Clutch, again; really"), text)
        XCTAssertTrue(text.contains("Tuesday 3 Nov"), text)

        let file = plan.calendarFile(calendar: calendar)
        XCTAssertTrue(file.hasPrefix("BEGIN:VCALENDAR\r\n"))
        XCTAssertTrue(file.hasSuffix("END:VCALENDAR\r\n"))
        XCTAssertEqual(file.components(separatedBy: "BEGIN:VEVENT").count - 1, 2)
        XCTAssertTrue(file.contains("DTSTART:20261102T211500"), file)
        XCTAssertTrue(file.contains("DTEND:20261102T213000"))
        // Commas and semicolons in a title are escaped, as the format requires.
        XCTAssertTrue(file.contains("SUMMARY:Post “Clutch\\, again\\; really” to TikTok"), file)
        XCTAssertEqual(plan.days(calendar: calendar).count, 2)
    }
}
