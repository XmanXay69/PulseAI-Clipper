import XCTest
@testable import PulseCore

final class OnlineMusicTests: XCTestCase {
    func testParsesSearchResults() throws {
        let html = """
        <script>var ytInitialData = {"contents":{"twoColumnSearchResultsRenderer":{"primaryContents":{"sectionListRenderer":{"contents":[
          {"itemSectionRenderer":{"contents":[
            {"videoRenderer":{"videoId":"abc123","title":{"runs":[{"text":"Chill Lofi Background Music (No Copyright) {calm}"}]},
              "ownerText":{"runs":[{"text":"Free Beats"}]},"lengthText":{"simpleText":"3:05"}}},
            {"videoRenderer":{"videoId":"def456","title":{"runs":[{"text":"EPIC Trap Mix 2026"}]},
              "ownerText":{"runs":[{"text":"Loud"}]},"lengthText":{"simpleText":"1:02:03"}}}
          ]}}]}}}}};</script>
        """
        let results = YouTubeSearchParser.results(fromHTML: html)
        XCTAssertEqual(results.map(\.videoID), ["abc123", "def456"])
        XCTAssertEqual(results[0].title, "Chill Lofi Background Music (No Copyright) {calm}")
        XCTAssertEqual(results[0].channel, "Free Beats")
        XCTAssertEqual(results[0].duration, 185)
        XCTAssertEqual(results[1].duration, 3723)
        XCTAssertTrue(YouTubeSearchParser.searchURL(query: "lofi music").absoluteString.hasSuffix("&sp=EgIwAQ%3D%3D"))
    }

    func testPicksCalmShortInstrumentals() {
        let calm = VideoSearchResult(videoID: "a", title: "Calm Lofi Background Music No Copyright", channel: "x", duration: 200)
        let loud = VideoSearchResult(videoID: "b", title: "EPIC Bass Boosted Trap", channel: "x", duration: 200)
        let tooLong = VideoSearchResult(videoID: "c", title: "Chill lofi 1 hour", channel: "x", duration: 3600)
        let vocal = VideoSearchResult(videoID: "d", title: "Song (Official Music Video)", channel: "VEVO", duration: 210)
        let plain = VideoSearchResult(videoID: "e", title: "Ambient instrumental", channel: "x", duration: 150)
        XCTAssertEqual(MusicPicker.rank([loud, tooLong, plain, vocal, calm], count: 5).map(\.videoID), ["a", "e"])
        XCTAssertEqual(MusicPicker.queries(for: [.gaming, .hype]).mood, "chill gaming")
        XCTAssertTrue(MusicPicker.queries(for: []).queries.allSatisfy { !$0.contains("epic") })
    }

    func testCreditsListEachTrackOnce() {
        let t = OnlineTrack(videoID: "abc", title: "Sunday", channel: "Free Beats", duration: 180, mood: "lofi")
        let block = MusicPicker.creditBlock([t, t])
        XCTAssertEqual(block, "Music\n♪ Sunday — Free Beats · https://www.youtube.com/watch?v=abc (Creative Commons)")
    }

    func testMusicTilesAcrossLongChapters() {
        var timeline = Timeline(name: "t", canvas: .landscape1080, tracks: [Track(kind: .video, name: "V1"), Track(kind: .audio, name: "A2 Music")])
        let bed = MediaAsset(name: "Sunday", path: "/tmp/s.m4a", kind: .audio, role: .music,
                             metadata: MediaMetadata(duration: 100, hasVideo: false, hasAudio: true, audioTrackCount: 1))
        LongFormEditor.addMusic([bed], chapters: [TimeRange(start: 5, end: 255)], to: &timeline)
        let clips = timeline.tracks[1].clips
        XCTAssertEqual(clips.count, 3, "100 s track repeats to fill 250 s")
        XCTAssertEqual(clips.last?.timelineRange.end ?? 0, 255, accuracy: 0.01)
        XCTAssertTrue(clips.allSatisfy { $0.audio.normalize && $0.audio.duckUnderDialogue && $0.audio.volume.value < 0.1 })
    }
}
