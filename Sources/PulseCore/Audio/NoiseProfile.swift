import Foundation

/// The steady noise of a recording, learned from a stretch you marked as silence (#263): 64 bands of mean
/// magnitude that the classic noise reduction subtracts instead of guessing from the quietest frames.
public struct NoiseProfile: Codable, Hashable, Sendable {
    public static let bandCount = 64
    /// Bins of the denoiser's 1024-point frames.
    public static let binCount = 512

    /// Mean magnitude per band, low to high frequency.
    public var bands: [Float]
    /// Where in the source it was learned (source time).
    public var learnedFrom: TimeRange?
    /// How much audio it was learned from.
    public var seconds: Seconds

    public init(bands: [Float], learnedFrom: TimeRange? = nil, seconds: Seconds = 0) {
        self.bands = bands
        self.learnedFrom = learnedFrom
        self.seconds = seconds
    }

    /// Folds the denoiser's bins into bands (the mean of each run of bins).
    public init(bins: [Float], learnedFrom: TimeRange? = nil, seconds: Seconds = 0) {
        let count = Self.bandCount
        var bands = [Float](repeating: 0, count: count)
        if !bins.isEmpty {
            for b in 0..<count {
                let lo = b * bins.count / count
                let hi = max(lo + 1, (b + 1) * bins.count / count)
                var sum: Float = 0
                for k in lo..<min(hi, bins.count) { sum += bins[k] }
                bands[b] = sum / Float(min(hi, bins.count) - lo)
            }
        }
        self.init(bands: bands, learnedFrom: learnedFrom, seconds: seconds)
    }

    public var isEmpty: Bool { bands.allSatisfy { $0 <= 0 } }

    /// The bands spread back over the denoiser's bins, linearly interpolated between band centres.
    public func expanded(to binCount: Int = NoiseProfile.binCount) -> [Float] {
        guard !bands.isEmpty, binCount > 0 else { return [] }
        let count = bands.count
        var out = [Float](repeating: 0, count: binCount)
        for k in 0..<binCount {
            let position = (Double(k) + 0.5) / Double(binCount) * Double(count) - 0.5
            let i = Int(position.rounded(.down)).clamped(0, count - 1)
            let j = min(i + 1, count - 1)
            let t = Float((position - Double(i)).clamped(0, 1))
            out[k] = bands[i] * (1 - t) + bands[j] * t
        }
        return out
    }

    /// Stable text for cache keys.
    public var fingerprint: String {
        StableHash.fnv1a(bands.map { String(format: "%.5f", $0) }.joined(separator: ","))
    }
}
