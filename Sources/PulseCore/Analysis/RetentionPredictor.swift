import Foundation

/// A guess at the audience retention curve before upload (#490): viewers leave slowly through lively stretches
/// and quickly through flat ones; a cut now and then buys a little attention back. 0…1 per `step` of the
/// signals, starting at 1.
public enum RetentionPredictor {
    public struct Curve: Hashable, Sendable {
        public var step: Seconds
        public var values: [Float]

        /// Share of viewers predicted to still be there at `time`.
        public func value(at time: Seconds) -> Float {
            guard step > 0, !values.isEmpty else { return 1 }
            let i = Int(time / step)
            return values[max(0, min(values.count - 1, i))]
        }

        /// The stretches where the curve falls fastest — where an edit would help most.
        public func steepestDrops(count: Int = 3, minimumSpacing: Seconds = 20) -> [Seconds] {
            guard values.count > 2, step > 0 else { return [] }
            let window = max(1, Int(10 / step))
            var drops: [(Seconds, Float)] = []
            var i = 0
            while i + window < values.count {
                drops.append((Double(i) * step, values[i] - values[i + window]))
                i += max(1, window / 2)
            }
            var out: [Seconds] = []
            for (t, _) in drops.sorted(by: { $0.1 > $1.1 }) where out.count < count {
                if !out.contains(where: { abs($0 - t) < minimumSpacing }) { out.append(t) }
            }
            return out.sorted()
        }
    }

    /// `excitement` 0…1 per step (the engagement model's combined signal); `cuts` are timeline cut times.
    public static func predict(excitement: [Float], step: Seconds, cuts: [Seconds] = [], duration: Seconds? = nil) -> Curve {
        guard step > 0, !excitement.isEmpty else { return Curve(step: max(step, 1), values: [1]) }
        let total = duration.map { Int(($0 / step).rounded(.up)) } ?? excitement.count
        var values = [Float](repeating: 1, count: max(1, total))
        var remaining: Float = 1
        // Baseline loss per second: about 0.7 % when nothing is happening, 0.05 % at full excitement (a lively
        // ten minutes keeps about half its viewers); the first 30 s lose faster (the hook decides who stays).
        let cutSteps = Set(cuts.map { Int($0 / step) })
        var flatRun: Seconds = 0
        for i in 0..<values.count {
            let e = i < excitement.count ? Double(max(0, min(1, excitement[i]))) : 0.2
            var lossPerSecond = 0.007 - 0.0065 * e
            let t = Double(i) * step
            if t < 30 { lossPerSecond *= 1.8 }
            // Dead stretches: viewers leave faster the longer nothing happens.
            if e < 0.25 { flatRun += step } else { flatRun = 0 }
            if flatRun > 15 { lossPerSecond *= 1.5 }
            if cutSteps.contains(i) { lossPerSecond *= 0.6 }
            remaining *= Float(1 - lossPerSecond * step)
            values[i] = max(0, remaining)
        }
        return Curve(step: step, values: values)
    }
}
