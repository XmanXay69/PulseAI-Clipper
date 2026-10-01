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
///
/// Fingerprints are z-scored and reduced to their main principal components (where differences between
/// voices show up), then clustered with k-means. The speaker count is chosen by comparing each k's cluster
/// separation with what the same k-means finds in flat, structureless data of the same spread and size
/// (the idea behind the gap statistic). A split has to be clearly better than that to count, so one voice
/// with natural variation stays one speaker.
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

    /// Projects points onto their top `count` principal components, with each component's variance.
    public static func principalComponents(_ points: [[Float]], count: Int) -> (points: [[Float]], variances: [Float]) {
        guard let dims = points.first?.count, dims > 0, points.count > 1 else { return (points, []) }
        let n = Double(points.count)
        var mean = [Double](repeating: 0, count: dims)
        for p in points { for d in 0..<dims { mean[d] += Double(p[d]) } }
        for d in 0..<dims { mean[d] /= n }
        var covariance = [[Double]](repeating: [Double](repeating: 0, count: dims), count: dims)
        for p in points {
            for i in 0..<dims {
                let a = Double(p[i]) - mean[i]
                for j in i..<dims { covariance[i][j] += a * (Double(p[j]) - mean[j]) }
            }
        }
        for i in 0..<dims { for j in i..<dims { covariance[i][j] /= n; covariance[j][i] = covariance[i][j] } }
        let (values, vectors) = symmetricEigen(covariance)
        let components = Array(values.indices.sorted { values[$0] > values[$1] }.prefix(max(1, min(count, dims))))
        let projected: [[Float]] = points.map { p in
            components.map { c in
                var s = 0.0
                for d in 0..<dims { s += (Double(p[d]) - mean[d]) * vectors[d][c] }
                return Float(s)
            }
        }
        return (projected, components.map { Float(max(values[$0], 0)) })
    }

    /// Eigenvalues and eigenvectors of a small symmetric matrix (cyclic Jacobi rotations). Column `c` of
    /// `vectors` belongs to `values[c]`.
    static func symmetricEigen(_ matrix: [[Double]]) -> (values: [Double], vectors: [[Double]]) {
        let n = matrix.count
        var a = matrix
        var v = (0..<n).map { i in (0..<n).map { j in i == j ? 1.0 : 0.0 } }
        for _ in 0..<60 {
            var off = 0.0
            for i in 0..<n { for j in (i + 1)..<n { off += a[i][j] * a[i][j] } }
            if off < 1e-18 { break }
            for p in 0..<n {
                for q in (p + 1)..<n where abs(a[p][q]) > 1e-15 {
                    let theta = (a[q][q] - a[p][p]) / (2 * a[p][q])
                    let t = (theta >= 0 ? 1.0 : -1.0) / (abs(theta) + (theta * theta + 1).squareRoot())
                    let c = 1 / (t * t + 1).squareRoot(), s = t * c
                    for k in 0..<n {
                        let kp = a[k][p], kq = a[k][q]
                        a[k][p] = c * kp - s * kq
                        a[k][q] = s * kp + c * kq
                    }
                    for k in 0..<n {
                        let pk = a[p][k], qk = a[q][k]
                        a[p][k] = c * pk - s * qk
                        a[q][k] = s * pk + c * qk
                    }
                    for k in 0..<n {
                        let kp = v[k][p], kq = v[k][q]
                        v[k][p] = c * kp - s * kq
                        v[k][q] = s * kp + c * kq
                    }
                }
            }
        }
        return ((0..<n).map { a[$0][$0] }, v)
    }

    static func squaredDistance(_ a: [Float], _ b: [Float]) -> Float {
        var s: Float = 0
        for i in a.indices { let d = a[i] - b[i]; s += d * d }
        return s
    }

    /// k-means with deterministic k-means++ seeding (several restarts, best inertia wins).
    public static func kMeans(_ points: [[Float]], k: Int, iterations: Int = 40, restarts: Int = 6) -> (labels: [Int], inertia: Float) {
        guard k > 1, points.count > k, let dims = points.first?.count else { return (Array(repeating: 0, count: points.count), 0) }
        var best: (labels: [Int], inertia: Float) = ([], .infinity)
        var rng = SeededGenerator(seed: 0xD1A5)
        for _ in 0..<restarts {
            // k-means++ seeding.
            var centers = [points[Int.random(in: 0..<points.count, using: &rng)]]
            while centers.count < k {
                let d2 = points.map { p in centers.map { squaredDistance(p, $0) }.min()! }
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
            var labels = [Int](repeating: -1, count: points.count)
            for _ in 0..<iterations {
                var changed = false
                for (i, p) in points.enumerated() {
                    var nearest = 0
                    var nearestDistance = Float.infinity
                    for c in 0..<k {
                        let d = squaredDistance(p, centers[c])
                        if d < nearestDistance { nearestDistance = d; nearest = c }
                    }
                    if nearest != labels[i] { labels[i] = nearest; changed = true }
                }
                var sums = [[Float]](repeating: [Float](repeating: 0, count: dims), count: k)
                var counts = [Int](repeating: 0, count: k)
                for (i, p) in points.enumerated() {
                    counts[labels[i]] += 1
                    for d in 0..<dims { sums[labels[i]][d] += p[d] }
                }
                for c in 0..<k where counts[c] > 0 { centers[c] = sums[c].map { $0 / Float(counts[c]) } }
                if !changed { break }
            }
            let inertia = points.indices.reduce(Float(0)) { $0 + squaredDistance(points[$1], centers[labels[$1]]) }
            if inertia < best.inertia { best = (labels, inertia) }
        }
        return best.inertia.isFinite ? best : (Array(repeating: 0, count: points.count), 0)
    }

    /// How clearly the two closest clusters are apart: centroid distance over the pooled spread along the
    /// line joining them. Cutting one Gaussian blob in two scores about 2.7 and one flat blob about 3.5;
    /// distinct voices score well above that.
    public static func separation(_ points: [[Float]], labels: [Int], k: Int) -> Float {
        guard k > 1, let dims = points.first?.count else { return 0 }
        var members = [[Int]](repeating: [], count: k)
        for (i, l) in labels.enumerated() where l >= 0 && l < k { members[l].append(i) }
        let centers: [[Float]] = members.map { m in
            var c = [Float](repeating: 0, count: dims)
            for i in m { for d in 0..<dims { c[d] += points[i][d] } }
            return c.map { $0 / Float(max(m.count, 1)) }
        }
        var closest = Float.infinity
        for a in 0..<k {
            for b in (a + 1)..<k {
                let dof = members[a].count + members[b].count - 2
                guard dof > 0 else { continue }
                let axis = (0..<dims).map { centers[b][$0] - centers[a][$0] }
                let length = axis.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
                guard length > 0 else { return 0 }
                var spread: Float = 0
                for (group, center) in [(members[a], centers[a]), (members[b], centers[b])] {
                    for i in group {
                        var along: Float = 0
                        for d in 0..<dims { along += (points[i][d] - center[d]) * axis[d] }
                        along /= length
                        spread += along * along
                    }
                }
                closest = min(closest, length / max((spread / Float(dof)).squareRoot(), 1e-6))
            }
        }
        return closest.isFinite ? closest : 0
    }

    /// One candidate speaker count and how its clusters compare with structureless data.
    public struct Trial: Hashable, Sendable {
        public var speakers: Int
        public var separation: Float
        public var reference: Float
        public var threshold: Float
    }

    public struct Result: Sendable {
        public var labels: [Int]
        public var trials: [Trial]
        public var speakers: Int { Set(labels).count }
    }

    /// Speaker label per fingerprint. `speakerCount` nil = estimate (1…maxSpeakers).
    public static func cluster(_ vectors: [[Float]], speakerCount: Int? = nil, maxSpeakers: Int = 6) -> [Int] {
        estimate(vectors, speakerCount: speakerCount, maxSpeakers: maxSpeakers).labels
    }

    /// Labels plus the evidence for the chosen speaker count. `minimumGain` is how much better than
    /// structureless data a split must separate (0.15 = 15%, and at least two standard deviations).
    public static func estimate(_ vectors: [[Float]], speakerCount: Int? = nil, maxSpeakers: Int = 6, minimumGain: Float = 0.15) -> Result {
        let n = vectors.count
        let single = Result(labels: Array(repeating: 0, count: n), trials: [])
        guard n >= 2 else { return single }
        let (points, variances) = principalComponents(standardized(vectors), count: max(2, min(8, n / 8)))
        guard variances.reduce(0, +) > 1e-9 else { return single }
        if let k = speakerCount {
            return k <= 1 ? single : Result(labels: kMeans(points, k: min(k, n - 1)).labels, trials: [])
        }
        var result = single
        var bestRatio: Float = 0
        let references = n < 100 ? 10 : 4
        let referenceSize = min(n, 600)
        var rng = SeededGenerator(seed: 0x5EED)
        for k in stride(from: 2, through: min(maxSpeakers, n / 3), by: 1) {
            let labels = kMeans(points, k: k).labels
            // Tiny clusters are noise, not people.
            let sizes = (0..<k).map { c in labels.lazy.filter { $0 == c }.count }
            guard sizes.min()! >= max(2, n / 40) else { continue }
            let observed = separation(points, labels: labels, k: k)
            // The same procedure on flat data with the same spread per component.
            let null: [Float] = (0..<references).map { _ in
                let flat = (0..<referenceSize).map { _ in variances.map { Float.random(in: -1...1, using: &rng) * (3 * $0).squareRoot() } }
                return separation(flat, labels: kMeans(flat, k: k).labels, k: k)
            }
            let mean = null.reduce(0, +) / Float(null.count)
            let sd = (null.reduce(Float(0)) { $0 + ($1 - mean) * ($1 - mean) } / Float(null.count)).squareRoot()
            let threshold = max(mean * (1 + minimumGain), mean + 2 * sd)
            result.trials.append(Trial(speakers: k, separation: observed, reference: mean, threshold: threshold))
            let ratio = observed / max(mean, 1e-6)
            if observed > threshold, ratio > bestRatio {
                bestRatio = ratio
                result.labels = labels
            }
        }
        return result
    }
}

/// Clustering for neural speaker embeddings (unit vectors where cosine similarity means "same voice").
///
/// Builds an average-linkage tree (on an evenly spaced sample for long recordings), then picks the cut
/// whose speakers are most clearly separated (mean silhouette on cosine distance). Clusters too small to
/// be a person are treated as outliers while choosing, then join their nearest speaker. A split must
/// reach `minimumSilhouette` to count, so one voice stays one speaker; no fixed similarity threshold is
/// needed, which keeps it working across microphones and rooms.
public enum EmbeddingClustering {
    /// Speakers whose voices are this similar on average are always merged.
    public static let sameVoiceSimilarity: Float = 0.92

    public struct Result: Sendable {
        public var labels: [Int]
        /// Best silhouette per number of speakers tried (diagnostics).
        public var silhouettes: [Int: Float]
        public var speakers: Int { Set(labels).count }
    }

    static func dot(_ a: [Float], _ b: [Float]) -> Float {
        var s: Float = 0
        for i in 0..<min(a.count, b.count) { s += a[i] * b[i] }
        return s
    }

    static func unit(_ v: [Float]) -> [Float] {
        let n = dot(v, v).squareRoot()
        return n > 0 ? v.map { $0 / n } : v
    }

    static func centroid(_ indices: [Int], _ points: [[Float]]) -> [Float] {
        var v = [Float](repeating: 0, count: points.first?.count ?? 0)
        for i in indices { for d in v.indices { v[d] += points[i][d] } }
        return unit(v)
    }

    public static func cluster(_ embeddings: [[Float]], speakerCount: Int? = nil, maxSpeakers: Int = 8,
                               minimumSilhouette: Float = 0.15, sampleLimit: Int = 400) -> [Int] {
        estimate(embeddings, speakerCount: speakerCount, maxSpeakers: maxSpeakers, minimumSilhouette: minimumSilhouette, sampleLimit: sampleLimit).labels
    }

    public static func estimate(_ embeddings: [[Float]], speakerCount: Int? = nil, maxSpeakers: Int = 8,
                                minimumSilhouette: Float = 0.15, sampleLimit: Int = 400) -> Result {
        let n = embeddings.count
        guard n >= 2 else { return Result(labels: Array(repeating: 0, count: n), silhouettes: [:]) }
        let points = embeddings.map(unit)
        let stride = max(1, Int((Double(n) / Double(sampleLimit)).rounded(.up)))
        let sample = Array(Swift.stride(from: 0, to: n, by: stride))
        let m = sample.count
        var similarity = [[Float]](repeating: [Float](repeating: 1, count: m), count: m)
        for a in 0..<m { for b in (a + 1)..<m { let s = dot(points[sample[a]], points[sample[b]]); similarity[a][b] = s; similarity[b][a] = s } }

        // Average-linkage tree; remember the partitions with few clusters.
        var sums = similarity
        var members: [[Int]] = (0..<m).map { [$0] }
        var alive = Array(repeating: true, count: m)
        var count = m
        let maxCut = min(m, max(maxSpeakers + 4, speakerCount ?? 0))
        var cuts: [Int: [[Int]]] = [:]
        if count <= maxCut { cuts[count] = (0..<m).map { members[$0] } }
        while count > 1 {
            var best: (Int, Int)? = nil
            var bestScore = -Float.infinity
            for a in 0..<m where alive[a] {
                for b in (a + 1)..<m where alive[b] {
                    let score = sums[a][b] / Float(members[a].count * members[b].count)
                    if score > bestScore { bestScore = score; best = (a, b) }
                }
            }
            guard let pair = best else { break }
            let (a, b) = pair
            members[a] += members[b]
            alive[b] = false
            for c in 0..<m where alive[c] && c != a { sums[a][c] += sums[b][c]; sums[c][a] = sums[a][c] }
            count -= 1
            if count <= maxCut { cuts[count] = (0..<m).filter { alive[$0] }.map { members[$0] } }
        }

        let minimumSize = max(2, m / 20)
        var silhouettes: [Int: Float] = [:]
        var chosen: [[Int]] = [Array(0..<m)]
        if let speakerCount, speakerCount > 1 {
            let k = min(speakerCount, m)
            chosen = cuts[k] ?? chosen
        } else if speakerCount == nil {
            var bestScore = minimumSilhouette
            for cut in cuts.keys.sorted() where cut >= 2 {
                let groups = cuts[cut]!.filter { $0.count >= minimumSize }
                guard groups.count >= 2, groups.count <= maxSpeakers else { continue }
                let score = silhouette(groups, similarity)
                if score > (silhouettes[groups.count] ?? -1) { silhouettes[groups.count] = score }
                if score > bestScore + 0.01 { bestScore = score; chosen = groups }
            }
        }
        // Centroids of the chosen speakers; near-identical voices merge.
        var centroids = chosen.map { centroid($0.map { sample[$0] }, points) }
        if speakerCount == nil {
            var merged = true
            while merged && centroids.count > 1 {
                merged = false
                outer: for a in 0..<centroids.count {
                    for b in (a + 1)..<centroids.count where dot(centroids[a], centroids[b]) > sameVoiceSimilarity {
                        chosen[a] += chosen[b]
                        chosen.remove(at: b)
                        centroids = chosen.map { centroid($0.map { sample[$0] }, points) }
                        merged = true
                        break outer
                    }
                }
            }
        }
        // Everyone joins their nearest speaker; refine the voices twice.
        func assign() -> [Int] { points.map { p in centroids.indices.max { dot(p, centroids[$0]) < dot(p, centroids[$1]) } ?? 0 } }
        var labels = assign()
        for _ in 0..<2 {
            centroids = centroids.indices.map { c in
                let mine = labels.indices.filter { labels[$0] == c }
                return mine.isEmpty ? centroids[c] : centroid(mine, points)
            }
            labels = assign()
        }
        return Result(labels: labels, silhouettes: silhouettes)
    }

    /// Mean silhouette with cosine distance over the members of `groups` (indices into `similarity`).
    static func silhouette(_ groups: [[Int]], _ similarity: [[Float]]) -> Float {
        var total: Float = 0
        var counted = 0
        for (g, group) in groups.enumerated() where group.count > 1 {
            for i in group {
                var own: Float = 0
                for j in group where j != i { own += 1 - similarity[i][j] }
                let a = own / Float(group.count - 1)
                var b = Float.infinity
                for (h, other) in groups.enumerated() where h != g {
                    var d: Float = 0
                    for j in other { d += 1 - similarity[i][j] }
                    b = min(b, d / Float(other.count))
                }
                total += (b - a) / max(a, b, 1e-6)
                counted += 1
            }
        }
        return counted > 0 ? total / Float(counted) : 0
    }

    /// Similarity statistics for diagnostics: mean cosine within the same label and across labels.
    public static func separation(_ embeddings: [[Float]], labels: [Int]) -> (within: Float, between: Float) {
        let points = embeddings.map(unit)
        var w: Float = 0, wn = 0, b: Float = 0, bn = 0
        for i in points.indices {
            for j in (i + 1)..<points.count {
                let s = dot(points[i], points[j])
                if labels[i] == labels[j] { w += s; wn += 1 } else { b += s; bn += 1 }
            }
        }
        return (wn > 0 ? w / Float(wn) : 0, bn > 0 ? b / Float(bn) : 0)
    }
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
