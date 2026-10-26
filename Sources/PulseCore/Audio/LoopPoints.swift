import Foundation

/// Where a music bed can loop without a seam (#294): a start and an end whose surrounding loudness
/// envelopes match, so a 90-second track tiles under a 20-minute edit instead of restarting with a bump.
public enum LoopPoints {
    public struct Loop: Hashable, Sendable {
        /// Source time the loop jumps back to.
        public var start: Seconds
        /// Source time the loop jumps from.
        public var end: Seconds
        /// 1 = the two points sound identical around the seam, 0 = nothing in common.
        public var score: Double

        public var length: Seconds { end - start }

        public init(start: Seconds, end: Seconds, score: Double) {
            self.start = start
            self.end = end
            self.score = score
        }
    }

    /// Finds the best loop in a peak envelope (`peaks` sampled `perSecond` times a second, as the waveform
    /// cache stores them). `minLength` keeps the loop long enough not to sound like a stutter; `window` is
    /// how much music either side of each point is compared. Nil when the track is shorter than the
    /// minimum loop or has no two matching stretches worth using (score under 0.6).
    public static func find(peaks: [Float], perSecond: Double, minLength: Seconds = 8, window: Seconds = 1) -> Loop? {
        guard perSecond > 0, !peaks.isEmpty else { return nil }
        // Compare at most ~10 samples a second: plenty for a seam, and keeps the search quadratic-cheap.
        let factor = max(1, Int((perSecond / 10).rounded()))
        let env: [Float] = factor == 1 ? peaks : stride(from: 0, to: peaks.count, by: factor).map { i in
            let slice = peaks[i..<min(i + factor, peaks.count)]
            return slice.reduce(0, +) / Float(slice.count)
        }
        let rate = perSecond / Double(factor)
        let w = max(2, Int((window * rate).rounded()))
        let minSamples = max(w, Int((minLength * rate).rounded()))
        let n = env.count
        guard n >= minSamples + 2 * w else { return nil }
        let step = max(1, w / 4)
        var best: (i: Int, j: Int, score: Double, rank: Double)?
        var i = w
        while i <= n - minSamples - w {
            let startLevel = level(env, around: i, w)
            if startLevel >= 0.04 {
                var j = i + minSamples
                while j <= n - w {
                    let endLevel = level(env, around: j, w)
                    if endLevel >= 0.04 {
                        var diff: Float = 0
                        for k in -w..<w { diff += abs(env[i + k] - env[j + k]) }
                        let score = max(0, 1 - Double(diff / Float(2 * w)) / 0.25)
                        // Among equally clean seams, prefer the longer loop (fewer repeats).
                        let rank = score + 0.05 * Double(j - i) / Double(n)
                        if best == nil || rank > best!.rank { best = (i, j, score, rank) }
                    }
                    j += step
                }
            }
            i += step
        }
        guard let best, best.score >= 0.6 else { return nil }
        return Loop(start: Double(best.i) / rate, end: Double(best.j) / rate, score: best.score)
    }

    private static func level(_ env: [Float], around i: Int, _ w: Int) -> Float {
        let slice = env[(i - w)..<(i + w)]
        return slice.reduce(0, +) / Float(slice.count)
    }

    /// Source ranges that play the track for `duration` seconds using the loop: the head once, then the
    /// loop body as often as needed, the last piece trimmed to fit. Without a loop the track simply
    /// restarts from zero.
    public static func segments(loop: Loop?, trackDuration: Seconds, duration: Seconds) -> [TimeRange] {
        guard trackDuration > 0.1, duration > 0 else { return [] }
        var out: [TimeRange] = []
        var remaining = duration
        var piece = loop.map { TimeRange(start: 0, end: $0.end) } ?? TimeRange(start: 0, end: trackDuration)
        let body = loop.map { TimeRange(start: $0.start, end: $0.end) } ?? TimeRange(start: 0, end: trackDuration)
        guard piece.duration > 0.1, body.duration > 0.1 else { return [] }
        while remaining > 0.001 {
            let length = min(piece.duration, remaining)
            out.append(TimeRange(start: piece.start, duration: length))
            remaining -= length
            piece = body
            if out.count > 10_000 { break }
        }
        return out
    }
}
