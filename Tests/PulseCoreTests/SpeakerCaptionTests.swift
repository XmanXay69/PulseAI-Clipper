import XCTest
@testable import PulseCore

final class SpeakerCaptionTests: XCTestCase {
    let asset = UUID()

    /// Host (speaker 0) and guest (speaker 1) alternate every 3 words.
    func conversation() -> Transcript {
        var words: [TranscriptWord] = []
        for i in 0..<18 {
            let t = Double(i) * 0.4
            words.append(TranscriptWord(text: "word\(i)", start: t, end: t + 0.3, speaker: (i / 3) % 2))
        }
        return Transcript(words: words, speakers: [Speaker(id: 0, name: "Host"), Speaker(id: 1, name: "Guest")], source: .demo)
    }

    func testColorBySpeakerStylesEachVoiceAndPagesNeverMix() {
        var track = CaptionTrack.make(from: conversation(), range: TimeRange(start: 0, end: 10), assetID: asset, style: .bold, emphasize: false)
        XCTAssertEqual(track.speakerName(1), "Guest")
        XCTAssertEqual(track.captionSpeakers, [0, 1])
        track.colorBySpeaker()
        XCTAssertTrue(track.isColoredBySpeaker)
        XCTAssertEqual(track.style(forSpeaker: 0), track.style, "the first speaker keeps the style's own look")
        XCTAssertEqual(track.style(forSpeaker: 1).text.color, CaptionTrack.speakerPalette[0].text)
        XCTAssertNotEqual(track.style(forSpeaker: 1).highlightColor, track.style(forSpeaker: 1).text.color)
        let timedWords = track.words.map { TimedCaptionWord(id: $0.id, text: $0.text, start: $0.start, end: $0.end, isEmphasized: false, speaker: $0.speaker) }
        for page in CaptionLayoutEngine.pages(timedWords, style: track.style) {
            XCTAssertEqual(Set(page.words.map(\.speaker)).count, 1)
            XCTAssertNotNil(page.speaker)
        }
        // Positions survive clearing the colors.
        track.speakerStyles[1]?.positionY = 0.3
        track.clearSpeakerColors()
        XCTAssertFalse(track.isColoredBySpeaker)
        XCTAssertEqual(track.style(forSpeaker: 1).positionY, 0.3)
        XCTAssertEqual(track.style(forSpeaker: 1).text.color, track.style.text.color)
    }

    func testOneVoiceIsLeftAlone() {
        var transcript = conversation()
        for i in transcript.words.indices { transcript.words[i].speaker = 0 }
        var track = CaptionTrack.make(from: transcript, range: TimeRange(start: 0, end: 10), assetID: asset, style: .bold, emphasize: false)
        track.colorBySpeaker()
        XCTAssertTrue(track.speakerStyles.isEmpty)
    }

    func testSyncFollowsReDiarizedTranscriptAndRoundTrips() throws {
        var track = CaptionTrack.make(from: conversation(), range: TimeRange(start: 0, end: 10), assetID: asset, style: .bold, emphasize: false)
        track.colorBySpeaker()
        var swapped = conversation()
        for i in swapped.words.indices { swapped.words[i].speaker = 1 - (swapped.words[i].speaker ?? 0) }
        swapped.speakers = [Speaker(id: 0, name: "Alex"), Speaker(id: 1, name: "Sam")]
        track.syncSpeakers(from: swapped)
        XCTAssertEqual(track.words.first?.speaker, 1)
        XCTAssertEqual(track.speakerName(0), "Alex")
        let decoded = try JSONDecoder().decode(CaptionTrack.self, from: JSONEncoder().encode(track))
        XCTAssertEqual(decoded, track)
    }
}
