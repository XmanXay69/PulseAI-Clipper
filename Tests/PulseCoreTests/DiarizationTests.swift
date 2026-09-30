import XCTest
@testable import PulseCore

final class DiarizationTests: XCTestCase {
    /// Two-speaker conversation: turns alternate every `turn` seconds, 3 words per second.
    func conversation(turns: Int, turn: Seconds = 6) -> Transcript {
        var words: [TranscriptWord] = []
        for t in 0..<turns {
            let start = Double(t) * turn
            var time = start
            while time < start + turn - 0.5 {
                words.append(TranscriptWord(text: "word", start: time, end: time + 0.25))
                time += 0.33
            }
        }
        return Transcript(words: words, source: .demo)
    }

    /// Synthetic voiceprints around per-speaker centres.
    func prints(centres: [[Float]], labels: [Int], spread: Float = 0.35, seed: UInt64 = 1) -> [[Float]] {
        var rng = SeededGenerator(seed: seed)
        return labels.map { l in centres[l].map { $0 + Float.random(in: -spread...spread, using: &rng) } }
    }

    func testSegmentsBreakAtPausesAndCapLength() {
        let t = conversation(turns: 4)
        let segments = SpeechSegmenter.segments(from: t, maxLength: 3)
        XCTAssertTrue(segments.allSatisfy { $0.range.duration <= 3.4 })
        // Every word belongs to exactly one segment, in order.
        var next = 0
        for s in segments {
            XCTAssertEqual(s.firstWord, next)
            next = s.lastWord + 1
        }
        XCTAssertEqual(next, t.words.count)
        // Turn changes (the 0.5 s gap) always start a new segment.
        for boundary in [6.0, 12.0, 18.0] {
            XCTAssertTrue(segments.contains { abs($0.range.start - boundary) < 0.01 })
        }
    }

    func testClusteringFindsTwoAndThreeSpeakersAutomatically() {
        let centres: [[Float]] = [[0, 0, 0, 0, 0, 0], [3, -2, 1, 2, -1, 3], [-3, 2, -2, 1, 3, -2]]
        for k in [2, 3] {
            let truth = (0..<90).map { $0 % k }
            let labels = SpeakerClustering.cluster(prints(centres: centres, labels: truth, seed: UInt64(k)))
            XCTAssertEqual(Set(labels).count, k)
            // Same partition up to renaming.
            var mapping: [Int: Int] = [:]
            var agree = 0
            for (l, t) in zip(labels, truth) {
                if mapping[l] == nil { mapping[l] = t }
                if mapping[l] == t { agree += 1 }
            }
            XCTAssertGreaterThan(Double(agree) / Double(truth.count), 0.95)
        }
    }

    func testOneVoiceStaysOneSpeaker() {
        let labels = SpeakerClustering.cluster(prints(centres: [[1, 2, 3, 4]], labels: Array(repeating: 0, count: 60), spread: 1))
        XCTAssertEqual(Set(labels).count, 1)
    }

    func testFixedSpeakerCount() {
        let centres: [[Float]] = [[0, 0, 0], [4, 4, 4]]
        let labels = SpeakerClustering.cluster(prints(centres: centres, labels: (0..<40).map { $0 % 2 }), speakerCount: 2)
        XCTAssertEqual(Set(labels).count, 2)
        XCTAssertEqual(Set(SpeakerClustering.cluster(prints(centres: centres, labels: (0..<40).map { $0 % 2 }), speakerCount: 1)).count, 1)
    }

    func testApplyLabelsWordsRenumbersAndSmooths() {
        var t = conversation(turns: 3, turn: 9)
        let segments = SpeechSegmenter.segments(from: t, maxLength: 3)
        // Truth: turn 0 → label 7, turn 1 → label 3, turn 2 → label 7; the middle segment of turn 0 is
        // mislabelled and short, so smoothing should absorb it.
        var labels = segments.map { Int($0.range.start / 9) % 2 == 0 ? 7 : 3 }
        let turnZero = segments.indices.filter { segments[$0].range.start < 8.5 }
        XCTAssertGreaterThanOrEqual(turnZero.count, 3)
        let blip = turnZero[1]
        labels[blip] = 3
        var adjusted = segments
        adjusted[blip].range = TimeRange(start: segments[blip].range.start, duration: 0.5)
        Diarizer.apply(labels: labels, segments: adjusted, to: &t, names: [3: "Guest"])
        XCTAssertEqual(t.words.first?.speaker, 0, "first voice becomes Speaker 1")
        XCTAssertEqual(t.speakerIDs, [0, 1])
        XCTAssertEqual(t.speakerName(1), "Guest")
        XCTAssertEqual(t.speakerName(0), "Speaker 1")
        XCTAssertTrue(t.words.filter { $0.start < 8.5 }.allSatisfy { $0.speaker == 0 }, "the blip was smoothed away")
        XCTAssertTrue(t.words.filter { $0.start > 9.2 && $0.start < 17 }.allSatisfy { $0.speaker == 1 })
        // Sentences break at speaker changes.
        XCTAssertTrue(t.sentences().allSatisfy { s in t.words[s.firstWord...s.lastWord].allSatisfy { $0.speaker == s.speaker } })

        t.mergeSpeaker(1, into: 0)
        XCTAssertEqual(t.speakerIDs, [0])
    }

    func testMicrophoneLabelsPickTheLoudestMic() {
        let t = conversation(turns: 4)
        let segments = SpeechSegmenter.segments(from: t)
        let hop = 0.1
        var micA = [Float](repeating: -50, count: 250), micB = [Float](repeating: -50, count: 250)
        for i in 0..<250 {
            let turn = Int(Double(i) * hop / 6)
            if turn % 2 == 0 { micA[i] = -18; micB[i] = -32 } else { micA[i] = -31; micB[i] = -17 }
        }
        let labels = Diarizer.labelsFromMicrophones(segments, levels: [micA, micB], hop: hop)
        for (segment, label) in zip(segments, labels) {
            XCTAssertEqual(label, Int(segment.range.start / 6) % 2)
        }
    }

    func testSingleVoiceClearsLabels() {
        var t = conversation(turns: 2)
        let segments = SpeechSegmenter.segments(from: t)
        Diarizer.apply(labels: Array(repeating: 5, count: segments.count), segments: segments, to: &t)
        XCTAssertTrue(t.words.allSatisfy { $0.speaker == nil })
        XCTAssertTrue(t.speakers.isEmpty)
    }
}
