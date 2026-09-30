import Foundation

/// Compact float series stored as little-endian Float32 base64 in JSON (an 8-hour VOD at
/// 10 Hz is ~288k samples; base64 keeps analysis files small and fast to load).
public struct FloatSeries: Codable, Hashable, Sendable {
    public var values: [Float]

    public init(_ values: [Float]) {
        self.values = values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let base64 = try? container.decode(String.self) {
            guard let data = Data(base64Encoded: base64) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid base64 float series")
            }
            let count = data.count / 4
            values = data.withUnsafeBytes { raw -> [Float] in
                (0..<count).map { i in
                    Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)))
                }
            }
        } else {
            values = try container.decode([Float].self)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let littleEndian = values.map { $0.bitPattern.littleEndian }
        let data = littleEndian.withUnsafeBytes { Data($0) }
        try container.encode(data.base64EncodedString())
    }

    public var count: Int { values.count }
    public subscript(i: Int) -> Float { values[i] }
}

/// Short-time audio features at a fixed hop, produced by the engine's streaming analyzer.
public struct AudioFeatureSeries: Codable, Hashable, Sendable {
    /// Seconds between samples.
    public var hop: Seconds
    /// RMS level in dBFS per hop (−100…0).
    public var rmsDB: FloatSeries
    /// Peak level in dBFS per hop.
    public var peakDB: FloatSeries
    /// Zero-crossing rate (0…1) — high for noisy/unvoiced sounds (laughs, screams, hiss).
    public var zeroCrossingRate: FloatSeries
    /// Spectral flux (onset strength) — spikes on sudden sounds, impacts, shouts.
    public var spectralFlux: FloatSeries

    public init(hop: Seconds, rmsDB: [Float], peakDB: [Float], zeroCrossingRate: [Float], spectralFlux: [Float]) {
        self.hop = hop
        self.rmsDB = FloatSeries(rmsDB)
        self.peakDB = FloatSeries(peakDB)
        self.zeroCrossingRate = FloatSeries(zeroCrossingRate)
        self.spectralFlux = FloatSeries(spectralFlux)
    }

    public var count: Int { rmsDB.count }
    public var duration: Seconds { Double(count) * hop }

    public func index(at time: Seconds) -> Int {
        Int((time / hop).rounded(.down)).clamped(0, max(count - 1, 0))
    }

    public func rms(at time: Seconds) -> Float {
        count > 0 ? rmsDB[index(at: time)] : -100
    }

    /// Mean RMS (dB) over a time range.
    public func meanRMS(in range: TimeRange) -> Float {
        guard count > 0 else { return -100 }
        let a = index(at: range.start)
        let b = max(a, index(at: range.end - hop / 2))
        var sum: Float = 0
        for i in a...b { sum += rmsDB[i] }
        return sum / Float(b - a + 1)
    }

    public func maxRMS(in range: TimeRange) -> Float {
        guard count > 0 else { return -100 }
        let a = index(at: range.start)
        let b = max(a, index(at: range.end - hop / 2))
        var m: Float = -100
        for i in a...b { m = max(m, rmsDB[i]) }
        return m
    }

    /// Downsamples a series to one value per `seconds` window using `reduce` (mean by default).
    public static func resample(_ values: [Float], hop: Seconds, to window: Seconds, count: Int, mode: ResampleMode = .mean) -> [Float] {
        guard !values.isEmpty, hop > 0 else { return [Float](repeating: 0, count: count) }
        var out = [Float](repeating: 0, count: count)
        let perWindow = max(1, Int((window / hop).rounded()))
        for w in 0..<count {
            let a = w * perWindow
            guard a < values.count else {
                out[w] = mode == .max ? (values.last ?? 0) : (out[max(w - 1, 0)])
                continue
            }
            let b = min(values.count, a + perWindow)
            switch mode {
            case .mean:
                var s: Float = 0
                for i in a..<b { s += values[i] }
                out[w] = s / Float(b - a)
            case .max:
                var m = -Float.greatestFiniteMagnitude
                for i in a..<b { m = max(m, values[i]) }
                out[w] = m
            }
        }
        return out
    }

    public enum ResampleMode {
        case mean
        case max
    }
}

/// Robust statistics helpers used by the engagement model.
public enum SeriesMath {
    public static func median(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    public static func percentile(_ values: [Float], _ p: Double) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let idx = Int((Double(sorted.count - 1) * p.clamped(0, 1)).rounded())
        return sorted[idx]
    }

    /// Median absolute deviation (scaled to σ for normal data).
    public static func mad(_ values: [Float]) -> Float {
        let m = median(values)
        return median(values.map { abs($0 - m) }) * 1.4826
    }

    /// Rolling median with a centered window of `radius` samples on each side.
    /// Uses a sorted sliding window: O(n · window) worst case but cache-friendly for our sizes.
    public static func rollingMedian(_ values: [Float], radius: Int) -> [Float] {
        guard !values.isEmpty else { return [] }
        let n = values.count
        var result = [Float](repeating: 0, count: n)
        var window: [Float] = []
        window.reserveCapacity(radius * 2 + 1)
        // Initialise with [0, radius].
        for i in 0...min(radius, n - 1) { insertSorted(&window, values[i]) }
        for i in 0..<n {
            result[i] = window[window.count / 2]
            // Slide: add i + radius + 1, remove i - radius.
            let addIndex = i + radius + 1
            if addIndex < n { insertSorted(&window, values[addIndex]) }
            let removeIndex = i - radius
            if removeIndex >= 0 { removeSorted(&window, values[removeIndex]) }
        }
        return result
    }

    static func insertSorted(_ a: inout [Float], _ v: Float) {
        var lo = 0
        var hi = a.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if a[mid] < v { lo = mid + 1 } else { hi = mid }
        }
        a.insert(v, at: lo)
    }

    static func removeSorted(_ a: inout [Float], _ v: Float) {
        var lo = 0
        var hi = a.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if a[mid] < v { lo = mid + 1 } else { hi = mid }
        }
        if lo < a.count, a[lo] == v { a.remove(at: lo) } else if let idx = a.firstIndex(of: v) { a.remove(at: idx) }
    }

    /// Gaussian smoothing with sigma in samples.
    public static func smooth(_ values: [Float], sigma: Double) -> [Float] {
        guard sigma > 0, values.count > 2 else { return values }
        let radius = max(1, Int((sigma * 3).rounded(.up)))
        var kernel = [Float](repeating: 0, count: radius * 2 + 1)
        var total: Float = 0
        for k in -radius...radius {
            let w = Float(exp(-Double(k * k) / (2 * sigma * sigma)))
            kernel[k + radius] = w
            total += w
        }
        for i in kernel.indices { kernel[i] /= total }
        var out = [Float](repeating: 0, count: values.count)
        for i in values.indices {
            var acc: Float = 0
            var wsum: Float = 0
            for k in -radius...radius {
                let j = i + k
                guard j >= 0, j < values.count else { continue }
                acc += values[j] * kernel[k + radius]
                wsum += kernel[k + radius]
            }
            out[i] = wsum > 0 ? acc / wsum : values[i]
        }
        return out
    }

    /// Local maxima separated by at least `minDistance` samples, above `threshold`, strongest first.
    public static func peaks(_ values: [Float], threshold: Float, minDistance: Int) -> [Int] {
        guard values.count >= 3 else { return values.indices.filter { values[$0] >= threshold } }
        var candidates: [Int] = []
        for i in values.indices {
            let v = values[i]
            guard v >= threshold else { continue }
            let left = i > 0 ? values[i - 1] : -.greatestFiniteMagnitude
            let right = i + 1 < values.count ? values[i + 1] : -.greatestFiniteMagnitude
            if v >= left && v > right || (v > left && v >= right) {
                candidates.append(i)
            }
        }
        candidates.sort { values[$0] > values[$1] }
        var chosen: [Int] = []
        for c in candidates where !chosen.contains(where: { abs($0 - c) < minDistance }) {
            chosen.append(c)
        }
        return chosen
    }

    public static func zScores(_ values: [Float]) -> [Float] {
        guard !values.isEmpty else { return [] }
        let m = median(values)
        let s = max(mad(values), 1e-3)
        return values.map { ($0 - m) / s }
    }

    public static func normalize(_ values: [Float]) -> [Float] {
        guard let lo = values.min(), let hi = values.max(), hi - lo > 1e-6 else {
            return [Float](repeating: 0, count: values.count)
        }
        return values.map { ($0 - lo) / (hi - lo) }
    }
}
