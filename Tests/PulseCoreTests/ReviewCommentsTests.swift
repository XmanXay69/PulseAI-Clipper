import XCTest
@testable import PulseCore

/// #1181: a page to watch an export and comment on it, and the comments back on the timeline as markers.
final class ReviewCommentsTests: XCTestCase {
    func testPlainTextWithTimecodesIsReadHoweverItWasTyped() {
        let notes = ReviewComments.parse("""
        PULSE review — “Clutch short” (0:58)
        Reviewer: Sam

        0:05 The hook line is on screen too long
        - 0:12.5 - music is too loud here
        [0:21] cut this pause.
        3. 00:31: zoom lands late
           it should hit on the word "now"
        0:40-0:46 this whole bit drags
        @0:50 love this
        00:00:52:15 one frame of black
        42 things are wrong with this line, but it has no timecode
        """, frameRate: 30)
        XCTAssertEqual(notes.reviewer, "Sam")
        XCTAssertEqual(notes.timelineName, "Clutch short")
        XCTAssertEqual(notes.duration, 58)
        XCTAssertEqual(notes.comments.map(\.time), [5, 12.5, 21, 31, 40, 50, 52.5])
        XCTAssertEqual(notes.comments[0].text, "The hook line is on screen too long")
        XCTAssertEqual(notes.comments[1].text, "music is too loud here")
        XCTAssertEqual(notes.comments[2].text, "cut this pause.")
        // A line with no timecode carries on the comment above it.
        XCTAssertEqual(notes.comments[3].text, "zoom lands late it should hit on the word \"now\"")
        XCTAssertEqual(notes.comments[4].duration, 6, accuracy: 0.001)
        XCTAssertEqual(notes.comments[4].text, "this whole bit drags")
        XCTAssertEqual(notes.comments[5].text, "love this")
        XCTAssertTrue(notes.comments[6].text.hasPrefix("one frame of black"))
        XCTAssertTrue(notes.comments.allSatisfy { $0.author == "Sam" })
    }

    func testWhatIsNotATimecodeIsNotReadAsOne() {
        XCTAssertNil(ReviewComments.clock("42", frameRate: 30))
        XCTAssertNil(ReviewComments.clock("1:75", frameRate: 30), "75 seconds is not a time")
        XCTAssertNil(ReviewComments.clock("1:61:00", frameRate: 30))
        XCTAssertNil(ReviewComments.clock("0:00:01:45", frameRate: 30), "frame 45 of 30")
        XCTAssertNil(ReviewComments.clock("a:10", frameRate: 30))
        XCTAssertNil(ReviewComments.clock("1::10", frameRate: 30))
        XCTAssertEqual(ReviewComments.clock("1:02:03", frameRate: 30), 3723)
        XCTAssertEqual(ReviewComments.clock("2:03.5", frameRate: 30), 123.5)
        XCTAssertNil(ReviewComments.leadingTimecode("Overall: great, 3 things to fix", frameRate: 30))
        XCTAssertNil(ReviewComments.leadingTimecode("1. Shorten the intro", frameRate: 30))
        XCTAssertTrue(ReviewComments.parse("Nothing here has a time.\nJust thoughts.").comments.isEmpty)
        // The stamp the page writes reads back as the same time.
        for time in [0, 5, 12.5, 59.9, 60, 3599.4, 3723] {
            XCTAssertEqual(ReviewComments.clock(ReviewComments.stamp(time), frameRate: 30) ?? -1, time, accuracy: 0.001, ReviewComments.stamp(time))
        }
    }

    func testThePagesOwnFileComesBackWithWhoAndWhichEdit() throws {
        let id = UUID()
        let file = """
        {"pulseReview":1,"timeline":"\(id.uuidString)","name":"Clutch short","duration":58.2,"reviewer":"Sam",
         "comments":[{"t":31.25,"text":"zoom lands late","who":"Sam"},{"t":5,"text":"  hook too long\\nsecond line "},{"t":9,"text":"   "}]}
        """
        let notes = ReviewComments.parse(file)
        XCTAssertEqual(notes.timelineID, id)
        XCTAssertEqual(notes.duration, 58.2)
        XCTAssertEqual(notes.comments.map(\.time), [5, 31.25], "in order, the empty one dropped")
        XCTAssertEqual(notes.comments[0].author, "Sam", "the reviewer's name when a comment has none")
        XCTAssertEqual(notes.comments[0].text, "hook too long\nsecond line")
        // The text the page copies says the same thing.
        let again = ReviewComments.parse(ReviewComments.text(notes))
        XCTAssertEqual(again.comments.map(\.time), [5, 31.3], "text keeps a tenth of a second, plenty for a marker")
        XCTAssertEqual(again.comments[0].text, "hook too long second line")
        XCTAssertEqual(again.reviewer, "Sam")
        XCTAssertEqual(again.timelineName, "Clutch short")
    }

    func testCommentsBecomeMarkersOnceAndSayWhenTheEditHasChanged() throws {
        var timeline = Fixtures.simpleTimeline(clipDuration: 30)
        timeline.markers = [Marker(time: 10, name: "Chapter", color: .blue)]
        var notes = ReviewNotes(comments: [
            ReviewComment(time: 4, text: "Too slow to start", author: "Sam"),
            ReviewComment(time: 12, duration: 5, text: String(repeating: "This stretch really drags. ", count: 6), author: "Sam"),
            ReviewComment(time: 45, text: "Outro is missing"),
        ], reviewer: "Sam", timelineID: timeline.id, timelineName: timeline.name, duration: timeline.duration)

        let report = ReviewComments.apply(notes, to: &timeline)
        XCTAssertEqual(report.added, 3)
        XCTAssertEqual(report.pastEnd, 1)
        XCTAssertNil(report.warning)
        XCTAssertEqual(timeline.markers.map(\.time), [4, 10, 12, 30], "in time order, among your own, the late one at the end")
        let first = try XCTUnwrap(timeline.markers.first)
        XCTAssertEqual(first.name, "Sam: Too slow to start")
        XCTAssertEqual(first.color, .orange)
        XCTAssertFalse(first.aiGenerated)
        let long = timeline.markers[2]
        XCTAssertLessThanOrEqual(long.name.count, 61)
        XCTAssertTrue(long.name.hasSuffix("…"))
        XCTAssertEqual(long.duration, 5)
        XCTAssertTrue(long.note.hasPrefix("This stretch really drags."), "the whole comment is in the note")
        XCTAssertTrue(timeline.markers[3].note.contains("past the end"))
        XCTAssertEqual(timeline.markers[1].name, "Chapter", "your own markers are untouched")

        // The same comments again add nothing.
        let second = ReviewComments.apply(notes, to: &timeline)
        XCTAssertEqual(second.added, 0)
        XCTAssertEqual(second.repeated, 3)
        XCTAssertEqual(timeline.markers.count, 4)

        // Written when the edit was a different length, or on another edit: placed, and said.
        var other = Fixtures.simpleTimeline(clipDuration: 30)
        notes.duration = 41
        notes.timelineID = other.id
        XCTAssertTrue(try XCTUnwrap(ReviewComments.apply(notes, to: &other).warning).contains("0:41"))
        notes.timelineID = UUID()
        var third = Fixtures.simpleTimeline(clipDuration: 30)
        let stranger = ReviewComments.apply(notes, to: &third)
        XCTAssertTrue(try XCTUnwrap(stranger.warning).contains("not this one"))
        XCTAssertTrue(stranger.summary.contains("3 comments are on the timeline"), stranger.summary)
        XCTAssertEqual(ReviewComments.apply(ReviewNotes(), to: &third).summary, "No comments with a timecode were found.")
    }

    func testThePageCarriesTheEditAndCannotBeBrokenByItsName() {
        var timeline = Fixtures.simpleTimeline(clipDuration: 30)
        timeline.name = "Best </script><b>clip</b> \"ever\""
        timeline.markers = [Marker(time: 10, name: "Part two", color: .blue), Marker(time: 12, name: "Mine", color: .red)]
        let page = ReviewComments.page(timeline: timeline, projectName: "Stream & Friends", videoFileName: "Best clip #1.mp4", reviewer: "Sam")
        XCTAssertTrue(page.hasPrefix("<!doctype html>"))
        XCTAssertTrue(page.contains("src=\"Best%20clip%20%231.mp4\""), "the video next to the page, by name")
        XCTAssertTrue(page.contains(timeline.id.uuidString))
        XCTAssertTrue(page.contains("Part two"))
        XCTAssertFalse(page.contains("\"Mine\""), "only chapters are jump points")
        XCTAssertTrue(page.contains("Stream &amp; Friends"))
        XCTAssertTrue(page.contains("for Sam"))
        // The name is text everywhere: no tag from it reaches the page, and it can't close the script.
        XCTAssertFalse(page.contains("<b>clip</b>"))
        XCTAssertEqual(page.components(separatedBy: "</script>").count - 1, 1)
        XCTAssertFalse(page.contains("http://"), "nothing is loaded from anywhere")
        XCTAssertFalse(page.contains("https://"))
        XCTAssertEqual(ReviewComments.pageName(forVideo: "Best clip #1.mp4"), "Best clip #1 review.html")
    }
}
