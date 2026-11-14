import XCTest
@testable import PulseCore

/// #1061: three clips from a long recording's first ten minutes while the rest is still being analyzed.
final class HeadStartTests: XCTestCase {
    private func head(spikes: [Seconds]) -> MediaAnalysis {
        MediaAnalysis(assetID: UUID(), duration: HeadStart.length, audio: Fixtures.audio(duration: HeadStart.length, spikes: spikes),
                      transcript: Fixtures.transcript(duration: HeadStart.length), profile: .gameplay)
    }

    func testOnlyLongRecordingsGetAHeadStart() {
        XCTAssertFalse(HeadStart.isWorthIt(duration: 75), "the sample is analyzed whole in seconds")
        XCTAssertFalse(HeadStart.isWorthIt(duration: 19 * 60))
        XCTAssertTrue(HeadStart.isWorthIt(duration: 20 * 60))
        XCTAssertTrue(HeadStart.isWorthIt(duration: 3 * 3600))
        XCTAssertEqual(HeadStart.length, 600)
    }

    func testTheBestThreeMomentsOfTheHeadBecomeClipsOfTheRecording() {
        let recording = UUID()
        let settings = ClipGenerationSettings(targetDuration: 30, aggressiveness: 0.8, minimumPotential: 0)
        let clips = HeadStart.clips(from: head(spikes: [60, 180, 300, 420, 540]), assetID: recording, settings: settings)
        XCTAssertFalse(clips.isEmpty)
        XCTAssertLessThanOrEqual(clips.count, 3)
        for clip in clips {
            XCTAssertEqual(clip.assetID, recording, "a clip of the recording, not of the copy of its start")
            XCTAssertEqual(clip.preliminary, true, "the full pass may replace it")
            XCTAssertGreaterThanOrEqual(clip.range.start, 0)
            XCTAssertLessThanOrEqual(clip.range.end, HeadStart.length + 0.5, "nothing runs past the ten minutes that were read")
            XCTAssertEqual(clip.status, .new)
        }
        // Best first, and no two of the same moment.
        XCTAssertEqual(clips.map(\.potential), clips.map(\.potential).sorted(by: >))
        for (i, a) in clips.enumerated() { for b in clips.dropFirst(i + 1) { XCTAssertLessThanOrEqual(a.range.iou(b.range), 0.3) } }
        // Asking for one gives one; a head with nothing in it gives none and doesn't crash.
        XCTAssertEqual(HeadStart.clips(from: head(spikes: [60, 300]), assetID: recording, settings: settings, count: 1).count, 1)
        let silent = MediaAnalysis(assetID: UUID(), duration: HeadStart.length, audio: nil, transcript: nil, profile: .unknown)
        XCTAssertTrue(HeadStart.clips(from: silent, assetID: recording, settings: settings).count <= 3)
    }

    func testAHeadStartClipReplacesTheSoundOnlyFirstLookOfTheSameMoment() {
        let recording = UUID()
        func clip(_ start: Seconds, preliminary: Bool, favorite: Bool = false, status: CandidateStatus = .new) -> ClipCandidate {
            var c = ClipCandidate(assetID: recording, range: TimeRange(start: start, end: start + 30), payoffTime: start + 15, targetDuration: 30, potential: 60,
                                  scores: ClipScores(), tags: [], title: "", copy: .empty, transcriptSnippet: "", status: status, isFavorite: favorite)
            c.preliminary = preliminary ? true : nil
            return c
        }
        let fresh = [clip(100, preliminary: true)]
        let sameMoment = clip(105, preliminary: true), elsewhere = clip(400, preliminary: true)
        let favorited = clip(102, preliminary: true, favorite: true), opened = clip(98, preliminary: true, status: .opened)
        let finished = clip(101, preliminary: false)
        let gone = HeadStart.superseded(by: fresh, among: [sameMoment, elsewhere, favorited, opened, finished])
        XCTAssertEqual(gone, [sameMoment.id], "only an untouched first-look clip of the same moment gives way")
    }
}
