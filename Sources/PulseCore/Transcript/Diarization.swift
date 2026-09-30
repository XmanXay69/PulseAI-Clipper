import Foundation

/// A stretch of continuous speech (a few seconds) that gets one speaker label.
public struct SpeechSegment: Hashable, Sendable {
    public var range: TimeRange
    public var firstWord: Int
    public var lastWord: Int

    public init(range: TimeRange, firstWord: Int, lastWord: Int) {
        self.range = range
        self.firstWord = firstWord
        self.lastWord = lastWord
    }
}

public enum SpeechSegmenter {
    /// Groups words into segments that break at pauses and never exceed `maxLength`, so a speaker
    /// change inside a long sentence is still caught.
    public static func segments(from transcript: Transcript, maxLength: Seconds = 3, pause: Seconds = 0.35) -> [SpeechSegment] {
        let words = transcript.words
        guard !words.isEmpty else { return [] }
        var result: [SpeechSegment] = []
        var first = 0
        for i in words.indices {
            let isLast = i == words.count - 1
            let tooLong = words[i].end - words[first].start >= maxLength
            let gap = isLast ? .infinity : words[i + 1].start - words[i].end
            if isLast || gap >= pause || tooLong {
                result.append(SpeechSegment(range: TimeRange(start: words[first].start, end: max(words[i].end, words[first].start + 0.05)),
                                            firstWord: first, lastWord: i))
                first = i + 1
            }
        }
        return result
    }
}

/// Groups voice fingerprints into speakers.
public enum SpeakerClustering {
    /// Z-scores each dimension so pitch and spectral shape weigh alike.
    public static func standardized(_ vectors: [[Float]]) -> [[Float]] {
        guard let dims = vectors.first?.count, dims > 0, vectors.count > 1 else { return vectors }
        var mean = [Float](repeating: 0, count: dims), sd = [Float](repeating: 0, count: dims)
        for v in vectors { for d in 0..<dims { mean[d] += v[d] } }
        for d in 0..<dims { mean[d] /= Float(vectors.count) }
        for v in vectors { for d in 0..<dims { sd[d] += (v[d] - mean[d]) * (v[d] - mean[d]) } }
        for d in 0..<dims { sd[d] = max((sd[d] / Float(vectors.count)).squareRoot(), 1e-6) }
        return vectors.map { v in (0..<dims).map { (v[$0] - mean[$0]) / sd[$0] } }
    }

    static func distance(_ a: [Float], _ b: [Float]) -> Float {
        var s: Float = 0
        for i in a.indices { let d = a[i] - b[i]; s += d * d }
        return s.squareRoot()
    }

    /// k-means with deterministic k-means++ seeding (several restarts, best inertia wins).
    public static func kMeans(_ points: [[Float]], k: Int, iterations: Int = 40, restarts: Int = 6) -> (labels: [Int], inertia: Float) {
        guard k > 1, points.count > k else { return (Array(repeating: 0, count: points.count), 0) }
        var best: (labels: [Int], inertia: Float) = ([], .infinity)
        var rng = SeededGenerator(seed: 0xD1A5)
        for _ in 0..<restarts {
            // k-means++ seeding.
            var centers = [points[Int.random(in: 0..<points.count, using: &rng)]]
            while centers.count < k {
                let d2 = points.map { p in centers.map { distance(p, $0) }.min()!.squared }
                let total = d2.reduce(0, +)
                guard total > 0 else { break }
                var pick = Float.random(in: 0..<total, using: &rng)
                var index = 0
                for (i, w) in d2.enumerated() {
                    pick -= w
                    if pick <= 0 { index = i; break }
                }
                centers.append(points[index])
            }
            guard centers.count == k else { continue }
            var labels = [Int](repeating: 0, count: points.count)
            for _ in 0..<iterations {
                var changed = false
                for (i, p) in points.enumerated() {
                    let nearest = centers.indices.min { distance(p, centers[$0]) < distance(p, centers[$1]) }!
                    if nearest != labels[i] { labels[i] = nearest; changed = true }
                }
                let dims = points[0].count
                for c in 0..<k {
                    let members = points.indices.filter { labels[$0] == c }
                    guard !members.isEmpty else { continue }
                    var center = [Float](repeating: 0, count: dims)
                    for m in members { for d in 0..<dims { center[d] += points[m][d] } }
                    centers[c] = center.map { $0 / Float(members.count) }
                }
                if !changed { break }
            }
            let inertia = points.indices.reduce(Float(0)) { $0 + distance(points[$1], centers[labels[$1]]).squared }
            if inertia < best.inertia { best = (labels, inertia) }
        }
        return best.inertia.isFinite ? best : (Array(repeating: 0, count: points.count), 0)
    }

    /// Mean silhouette (−1…1): how well each point sits in its cluster vs the nearest other one.
    public static func silhouette(_ points: [[Float]], labels: [Int]) -> Float {
        let clusters = Set(labels)
        guard clusters.count > 1 else { return 0 }
        var total: Float = 0
        for (i, p) in points.enumerated() {
            var sums: [Int: (Float, Int)] = [:]
            for (j, q) in points.enumerated() where j != i {
                let d = distance(p, q)
                let e = sums[labels[j]] ?? (0, 0)
                sums[labels[j]] = (e.0 + d, e.1 + 1)
            }
            guard let own = sums[labels[i]], own.1 > 0 else { continue }
            let a = own.0 / Float(own.1)
            let b = sums.filter { $0.key != labels[i] && $0.value.1 > 0 }.map { $0.value.0 / Float($0.value.1) }.min() ?? a
            total += (b - a) / max(a, b, 1e-6)
        }
        return total / Float(points.count)
    }

    /// Speaker label per fingerprint. `speakerCount` nil = estimate (1…maxSpeakers) by silhouette;
    /// a single voice is assumed when no split is clearly better.
    public static func cluster(_ vectors: [[Float]], speakerCount: Int? = nil, maxSpeakers: Int = 6, minimumSilhouette: Float = 0.18) -> [Int] {
        guard vectors.count >= 2 else { return Array(repeating: 0, count: vectors.count) }
        let points = standardized(vectors)
        if let k = speakerCount {
            return k <= 1 ? Array(repeating: 0, count: points.count) : kMeans(points, k: min(k, points.count - 1)).labels
        }
        var bestLabels = Array(repeating: 0, count: points.count)
        var bestScore = minimumSilhouette
        // Silhouette is O(n²); estimate the count on a sample for long recordings.
        let sampleStride = max(1, points.count / 400)
        let sampleIndices = Array(stride(from: 0, to: points.count, by: sampleStride))
        for k in 2...max(2, min(maxSpeakers, points.count - 1)) {
            let labels = kMeans(points, k: k).labels
            // Tiny clusters are noise, not people.
            let sizes = (0..<k).map { c in labels.filter { $0 == c }.count }
            guard sizes.min()! >= max(2, points.count / 40) else { continue }
            let score = silhouette(sampleIndices.map { points[$0] }, labels: sampleIndices.map { labels[$0] })
            if score > bestScore + 0.02 {
                bestScore = score
                bestLabels = labels
            }
        }
        return bestLabels
    }
}

private extension Float {
    var squared: Float { self * self }
}

/// Puts speaker labels onto transcript words.
public enum Diarizer {
    /// Labels each segment by whichever microphone is loudest (one mic per person — the most reliable
    /// method). `levels[i]` is mic `i`'s loudness (dB) in transcript time at `hop`. Near-ties keep
    /// the previous speaker.
    public static func labelsFromMicrophones(_ segments: [SpeechSegment], levels: [[Float]], hop: Seconds, tieDB: Float = 2) -> [Int] {
        var previous = 0
        return segments.map { segment in
            let lo = max(0, Int(segment.range.start / hop)), hi = Int(segment.range.end / hop)
            let means: [Float] = levels.map { series in
                guard lo < series.count, hi > lo else { return -120 }
                let slice = series[lo..<min(hi, series.count)]
                return slice.isEmpty ? -120 : slice.reduce(0, +) / Float(slice.count)
            }
            guard let best = means.indices.max(by: { means[$0] < means[$1] }) else { return previous }
            let second = means.enumerated().filter { $0.offset != best }.map(\.element).max() ?? -120
            if means[best] - second >= tieDB { previous = best }
            return previous
        }
    }

    /// Writes labels onto words and speaker names onto the transcript. Labels are renumbered by first
    /// appearance, and short one-off segments between two segments of the same speaker are absorbed.
    public static func apply(labels raw: [Int], segments: [SpeechSegment], to transcript: inout Transcript,
                             names: [Int: String] = [:], minimumTurn: Seconds = 1.0) {
        guard segments.count == raw.count, !segments.isEmpty else { return }
        var labels = raw
        if labels.count >= 3 {
            for i in 1..<(labels.count - 1) where labels[i - 1] == labels[i + 1] && labels[i] != labels[i - 1]
                && segments[i].range.duration < minimumTurn {
                labels[i] = labels[i - 1]
            }
        }
        // Renumber by first appearance so "Speaker 1" talks first.
        var mapping: [Int: Int] = [:]
        for l in labels where mapping[l] == nil { mapping[l] = mapping.count }
        var originalFor: [Int: Int] = [:]
        for (original, new) in mapping { originalFor[new] = original }
        for (segment, label) in zip(segments, labels) {
            let id = mapping[label]!
            for w in segment.firstWord...segment.lastWord where w < transcript.words.count {
                transcript.words[w].speaker = id
            }
        }
        // Words that fell outside every segment take their neighbour's speaker.
        var last: Int?
        for i in transcript.words.indices {
            if let s = transcript.words[i].speaker { last = s } else { transcript.words[i].speaker = last }
        }
        let count = mapping.count
        transcript.speakers = (0..<count).map { id in
            let kept = transcript.speakers.first { $0.id == id }?.name
            let named = originalFor[id].flatMap { names[$0] }
            return Speaker(id: id, name: named ?? kept ?? "Speaker \(id + 1)")
        }
        if count <= 1 {
            // One voice: no labels (keeps the transcript view clean).
            for i in transcript.words.indices { transcript.words[i].speaker = nil }
            transcript.speakers = []
        }
    }
}

extension Transcript {
    /// Reassigns every word of speaker `from` to speaker `into`.
    public mutating func mergeSpeaker(_ from: Int, into: Int) {
        guard from != into else { return }
        for i in words.indices where words[i].speaker == from { words[i].speaker = into }
        speakers.removeAll { $0.id == from }
    }
}
