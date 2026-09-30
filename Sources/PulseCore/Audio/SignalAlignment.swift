import Foundation

/// Finds how far one signal lags another (e.g. a processed copy vs its source).
public enum SignalAlignment {
    /// Delay in samples of `delayed` relative to `reference`, searched over 0…maxLag, plus the normalized
    /// correlation at that delay (near 1 = same signal). Searches coarsely at 1/8 rate on the loudest
    /// stretch of `reference`, then refines sample-accurately.
    public static func delay(of delayed: [Float], relativeTo reference: [Float], maxLag: Int, window: Int = 96_000) -> (lag: Int, correlation: Float) {
        let usable = min(reference.count, delayed.count - maxLag)
        guard maxLag >= 0, usable > 64 else { return (0, 0) }
        let span = min(window, usable)
        // Loudest stretch of the reference.
        var start = 0
        var loudest: Float = -1
        let block = max(span / 4, 1)
        var b = 0
        while b + span <= usable {
            var e: Float = 0
            for i in stride(from: b, to: b + span, by: 16) { e += reference[i] * reference[i] }
            if e > loudest { loudest = e; start = b }
            b += block
        }
        func correlation(_ a: [Float], _ aStart: Int, _ d: [Float], _ dStart: Int, _ count: Int) -> Float {
            var ab: Float = 0, aa: Float = 0, dd: Float = 0
            a.withUnsafeBufferPointer { ap in
                d.withUnsafeBufferPointer { dp in
                    for i in 0..<count {
                        let x = ap[aStart + i], y = dp[dStart + i]
                        ab += x * y; aa += x * x; dd += y * y
                    }
                }
            }
            return aa > 0 && dd > 0 ? ab / (aa * dd).squareRoot() : 0
        }
        // Coarse: average 8 samples.
        let factor = 8
        func decimate(_ x: [Float], from: Int, count: Int) -> [Float] {
            (0..<(count / factor)).map { k in
                var s: Float = 0
                for j in 0..<factor { s += x[from + k * factor + j] }
                return s / Float(factor)
            }
        }
        let coarseRef = decimate(reference, from: start, count: span)
        let coarseDelayed = decimate(delayed, from: start, count: span + maxLag)
        var coarseLag = 0
        var best: Float = -2
        for lag in 0...(maxLag / factor) where lag + coarseRef.count <= coarseDelayed.count {
            let c = correlation(coarseRef, 0, coarseDelayed, lag, coarseRef.count)
            if c > best { best = c; coarseLag = lag }
        }
        // Fine: ±factor samples around the coarse lag.
        var lag = coarseLag * factor
        best = -2
        for candidate in max(0, coarseLag * factor - factor)...min(maxLag, coarseLag * factor + factor)
        where start + candidate + span <= delayed.count {
            let c = correlation(reference, start, delayed, start + candidate, span)
            if c > best { best = c; lag = candidate }
        }
        return (lag, max(best, 0))
    }
}
