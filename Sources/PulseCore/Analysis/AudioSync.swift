import Foundation

/// Aligns separately recorded sources (gameplay.mp4 / webcam.mp4 / mic.wav) by cross-correlating
/// their loudness envelopes.
public enum AudioSync {
    public struct Result: Equatable, Sendable {
        /// Seconds to ADD to `other`'s timestamps to line it up with `reference`
        /// (i.e. `other` starts `offset` seconds after `reference`).
        public var offset: Seconds
        /// Peak normalized correlation (0…1). Below ~0.3 the match is unreliable.
        public var confidence: Double
    }

    /// - Parameters:
    ///   - reference, other: RMS envelopes in dB at the same `hop`.
    ///   - maxOffset: search window in seconds (± around zero).
    public static func estimateOffset(reference: [Float], other: [Float], hop: Seconds, maxOffset: Seconds = 60) -> Result? {
        guard reference.count > 20, other.count > 20, hop > 0 else { return nil }
        // Work on onset-like envelopes (positive level changes) which are robust to different gains/mics.
        let a = onsetEnvelope(reference)
        let b = onsetEnvelope(other)
        let maxLag = min(Int(maxOffset / hop), max(a.count, b.count))
        var bestLag = 0
        var best = -Double.greatestFiniteMagnitude
        for lag in -maxLag...maxLag {
            // Correlate a[i] with b[i - lag]  (other shifted by +lag).
            var sum = 0.0
            var sa = 0.0
            var sb = 0.0
            var n = 0
            let iStart = max(0, lag)
            let iEnd = min(a.count, b.count + lag)
            guard iEnd - iStart > 10 else { continue }
            var i = iStart
            while i < iEnd {
                let x = Double(a[i])
                let y = Double(b[i - lag])
                sum += x * y
                sa += x * x
                sb += y * y
                n += 1
                i += 1
            }
            let denom = (sa * sb).squareRoot()
            guard denom > 1e-9 else { continue }
            let score = sum / denom
            if score > best {
                best = score
                bestLag = lag
            }
        }
        guard best > -Double.greatestFiniteMagnitude else { return nil }
        return Result(offset: Double(bestLag) * hop, confidence: max(0, min(1, best)))
    }

    static func onsetEnvelope(_ db: [Float]) -> [Float] {
        guard db.count > 1 else { return db }
        var out = [Float](repeating: 0, count: db.count)
        for i in 1..<db.count {
            out[i] = max(0, db[i] - db[i - 1])
        }
        // Remove mean so silence doesn't dominate.
        let mean = out.reduce(0, +) / Float(out.count)
        return out.map { $0 - mean }
    }
}
