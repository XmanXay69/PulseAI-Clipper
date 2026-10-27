import Foundation

extension MulticamEditor {
    /// The AI switch's tunables from one slider (#327): 0 = patient (long shots, only clear changes of
    /// speaker), 1 = eager (short shots, switches on small level differences).
    public struct SwitchTuning: Hashable, Sendable {
        public var minimumShot: Seconds
        public var crosstalkDB: Float

        public init(sensitivity: Double) {
            let s = sensitivity.clamped(0, 1)
            minimumShot = 4.0 - 2.75 * s
            crosstalkDB = Float(6 - 4 * s)
        }

        public static let `default` = SwitchTuning(sensitivity: 0.5)
    }

    /// Moves each switch onto the nearest beat within `tolerance` (#327), so cuts land on the music.
    /// A shot is never squeezed below `minimumShot` by the move, and the shots stay gapless.
    public static func snapped(_ cuts: [MulticamCut], toBeats beats: [Seconds], tolerance: Seconds = 0.35, minimumShot: Seconds = 0.5) -> [MulticamCut] {
        guard cuts.count >= 2, !beats.isEmpty else { return cuts }
        let grid = beats.sorted()
        var out = cuts
        for i in 0..<(out.count - 1) {
            let boundary = out[i].range.end
            guard let beat = nearest(to: boundary, in: grid), abs(beat - boundary) <= tolerance, beat != boundary else { continue }
            guard beat - out[i].range.start >= minimumShot, out[i + 1].range.end - beat >= minimumShot else { continue }
            out[i].range = TimeRange(start: out[i].range.start, end: beat)
            out[i + 1].range = TimeRange(start: beat, end: out[i + 1].range.end)
        }
        return out
    }

    static func nearest(to t: Seconds, in sorted: [Seconds]) -> Seconds? {
        guard !sorted.isEmpty else { return nil }
        var lo = 0, hi = sorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid] < t { lo = mid + 1 } else { hi = mid }
        }
        var best = lo < sorted.count ? sorted[lo] : sorted[sorted.count - 1]
        if lo > 0, abs(sorted[lo - 1] - t) < abs(best - t) { best = sorted[lo - 1] }
        return best
    }
}
