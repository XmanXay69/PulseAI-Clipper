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

    /// Fingerprint-like vectors: 24 spectral values driven by a few shared factors plus noise, pitch
    /// repeated four times, pitch spread and voicing (the shape `SpeakerDiarization` produces).
    func voice(count: Int, pitch: Float = 0, timbre: [Float] = [], seed: UInt64) -> [[Float]] {
        var rng = SeededGenerator(seed: seed)
        func gauss() -> Float {
            let u = max(Float.random(in: 0..<1, using: &rng), 1e-7), v = Float.random(in: 0..<1, using: &rng)
            return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
        }
        var loadingRNG = SeededGenerator(seed: 42)
        let loadings = (0..<4).map { _ in (0..<24).map { _ in Float.random(in: -1...1, using: &loadingRNG) } }
        var result: [[Float]] = []
        for _ in 0..<count {
            let factors = [gauss(), gauss(), gauss(), gauss()]
            var v: [Float] = []
            for d in 0..<24 {
                var x = 0.8 * gauss()
                for f in 0..<4 { x += 0.6 * factors[f] * loadings[f][d] }
                v.append(x + (d < timbre.count ? timbre[d] : 0))
            }
            let p = pitch + 0.1 * gauss()
            result.append(v + [p, p, p, p, 0.05 * gauss(), 0.1 * gauss()])
        }
        return result
    }

    func testOneVoiceStaysOneSpeaker() {
        // Flat noise in a few dimensions: k-means always finds "clusters"; they must not count.
        let flat = SpeakerClustering.estimate(prints(centres: [[1, 2, 3, 4]], labels: Array(repeating: 0, count: 60), spread: 1))
        XCTAssertEqual(flat.speakers, 1, "\(flat.trials)")
        // One voice with natural variation, short and long recordings.
        for (n, seed) in [(20, 1), (60, 2), (300, 3)] as [(Int, UInt64)] {
            let result = SpeakerClustering.estimate(voice(count: n, seed: seed))
            XCTAssertEqual(result.speakers, 1, "\(n) segments: \(result.trials)")
        }
    }

    func testTwoRealisticVoices() {
        let timbre: [Float] = [1.2, -1.0, 0.8, -1.4, 1.1, -0.9, 1.3, -1.2, 0.9, -1.1, 1.0, -0.8]
        let a = voice(count: 50, seed: 11), b = voice(count: 50, pitch: 0.7, timbre: timbre, seed: 12)
        // Interleave turns so order doesn't give it away.
        var fingerprints: [[Float]] = [], truth: [Int] = []
        for i in 0..<50 { fingerprints += [a[i], b[i]]; truth += [0, 1] }
        let result = SpeakerClustering.estimate(fingerprints)
        XCTAssertEqual(result.speakers, 2, "\(result.trials)")
        let agree = zip(result.labels, truth).filter { $0 == $1 }.count
        XCTAssertGreaterThan(Double(max(agree, truth.count - agree)) / Double(truth.count), 0.95)
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

    /// Unit vectors scattered around per-speaker directions (like neural voice embeddings).
    func embeddings(speakers: Int, perSpeaker: Int, spread: Float, dims: Int = 64, seed: UInt64) -> (vectors: [[Float]], truth: [Int]) {
        var rng = SeededGenerator(seed: seed)
        let centres = (0..<speakers).map { _ in (0..<dims).map { _ -> Float in let u = Float.random(in: 0...1, using: &rng); return u * u * u } }
        var vectors: [[Float]] = [], truth: [Int] = []
        for i in 0..<(speakers * perSpeaker) {
            let s = i % speakers
            vectors.append(centres[s].map { max(0, $0 + Float.random(in: -spread...spread, using: &rng)) })
            truth.append(s)
        }
        return (vectors, truth)
    }

    func agreement(_ labels: [Int], _ truth: [Int]) -> Double {
        // Best one-to-one match via majority vote per cluster.
        var votes: [Int: [Int: Int]] = [:]
        for (l, t) in zip(labels, truth) { votes[l, default: [:]][t, default: 0] += 1 }
        return Double(votes.values.map { $0.values.max() ?? 0 }.reduce(0, +)) / Double(truth.count)
    }

    func testEmbeddingClusteringFindsSpeakersByVoiceSimilarity() {
        for speakers in [2, 3, 4] {
            let (vectors, truth) = embeddings(speakers: speakers, perSpeaker: 25, spread: 0.35, seed: UInt64(speakers))
            let sep = EmbeddingClustering.separation(vectors, labels: truth)
            let labels = EmbeddingClustering.cluster(vectors)
            XCTAssertEqual(Set(labels).count, speakers, "within \(sep.within) between \(sep.between)")
            XCTAssertGreaterThan(agreement(labels, truth), 0.95)
        }
        // One voice stays one speaker.
        let (single, _) = embeddings(speakers: 1, perSpeaker: 60, spread: 0.35, seed: 9)
        XCTAssertEqual(Set(EmbeddingClustering.cluster(single)).count, 1)
        // A fixed count is honoured, and long recordings are clustered via a sample.
        let (many, truth) = embeddings(speakers: 2, perSpeaker: 500, spread: 0.35, seed: 10)
        let fixed = EmbeddingClustering.cluster(many, speakerCount: 2, sampleLimit: 120)
        XCTAssertEqual(Set(fixed).count, 2)
        XCTAssertGreaterThan(agreement(fixed, truth), 0.95)
    }
}
