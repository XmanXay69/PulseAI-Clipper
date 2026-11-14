import Foundation

/// What the face on camera was doing across a recording (#501): how open the mouth was, how wide, how open
/// the eyes, how high the brows, sampled every second or two. A silent jaw-drop, a held breath or a grin are
/// reactions the microphone misses.
///
/// The numbers are shapes, not feelings: ratios of distances between face landmarks, measured on this Mac.
/// Nothing is identified and no picture is kept.
public struct ExpressionSeries: Codable, Hashable, Sendable {
    /// Seconds between samples.
    public var hop: Seconds
    /// Gap between the lips over the mouth's width; `ExpressionSeries.absent` where no face was found.
    public var mouthOpen: FloatSeries
    /// The mouth's width over the face's.
    public var mouthWidth: FloatSeries
    /// The eyes' height over their width.
    public var eyeOpen: FloatSeries
    /// How far the brows sit above the eyes, over the face's height.
    public var browRaise: FloatSeries

    /// Stored where a sample had no face.
    public static let absent: Float = -1

    public init(hop: Seconds, mouthOpen: [Float], mouthWidth: [Float], eyeOpen: [Float], browRaise: [Float]) {
        self.hop = hop
        self.mouthOpen = FloatSeries(mouthOpen)
        self.mouthWidth = FloatSeries(mouthWidth)
        self.eyeOpen = FloatSeries(eyeOpen)
        self.browRaise = FloatSeries(browRaise)
    }

    public var count: Int { mouthOpen.count }

    /// Share of samples that found a face.
    public var coverage: Double {
        guard count > 0 else { return 0 }
        return Double(mouthOpen.values.filter { $0 >= 0 }.count) / Double(count)
    }
}

/// Turns face landmarks into the four measures, and the measures into a reaction signal.
public enum FaceExpressionMath {
    public struct Point: Hashable, Sendable {
        public var x: Double
        public var y: Double

        public init(_ x: Double, _ y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// Landmark outlines in the face box's own coordinates (0…1 across, 0…1 up), as Vision gives them.
    public struct Landmarks: Sendable {
        public var outerLips: [Point]
        public var innerLips: [Point]
        public var leftEye: [Point]
        public var rightEye: [Point]
        public var leftBrow: [Point]
        public var rightBrow: [Point]

        public init(outerLips: [Point], innerLips: [Point], leftEye: [Point], rightEye: [Point], leftBrow: [Point] = [], rightBrow: [Point] = []) {
            self.outerLips = outerLips
            self.innerLips = innerLips
            self.leftEye = leftEye
            self.rightEye = rightEye
            self.leftBrow = leftBrow
            self.rightBrow = rightBrow
        }
    }

    public struct Measures: Hashable, Sendable {
        public var mouthOpen: Double
        public var mouthWidth: Double
        public var eyeOpen: Double
        public var browRaise: Double
    }

    static func extent(_ points: [Point]) -> (width: Double, height: Double, centreY: Double)? {
        guard points.count >= 3, let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }
        return (maxX - minX, maxY - minY, (minY + maxY) / 2)
    }

    /// The four measures for one face; nil when the mouth or both eyes weren't outlined.
    public static func measures(_ landmarks: Landmarks) -> Measures? {
        guard let outer = extent(landmarks.outerLips), outer.width > 0.01 else { return nil }
        let inner = extent(landmarks.innerLips)
        let eyes = [landmarks.leftEye, landmarks.rightEye].compactMap(extent).filter { $0.width > 0.005 }
        guard !eyes.isEmpty else { return nil }
        let eyeOpen = eyes.map { $0.height / $0.width }.reduce(0, +) / Double(eyes.count)
        let eyeY = eyes.map(\.centreY).reduce(0, +) / Double(eyes.count)
        let brows = [landmarks.leftBrow, landmarks.rightBrow].compactMap(extent)
        let browRaise = brows.isEmpty ? 0 : max(0, brows.map(\.centreY).reduce(0, +) / Double(brows.count) - eyeY)
        return Measures(mouthOpen: (inner?.height ?? 0) / outer.width, mouthWidth: outer.width, eyeOpen: eyeOpen, browRaise: browRaise)
    }

    /// How far each sample's face is from this person's resting face, 0…1. An open mouth counts most, then a
    /// wide one (a grin), then wide eyes and raised brows. Measured against the recording's own median, so a
    /// naturally wide smile or small eyes don't read as a reaction all stream long.
    public static func intensity(_ series: ExpressionSeries) -> [Float] {
        let n = series.count
        guard n > 0 else { return [] }
        let present = (0..<n).filter { series.mouthOpen[$0] >= 0 }
        guard present.count >= 5 else { return [Float](repeating: 0, count: n) }
        func rest(_ values: FloatSeries) -> (median: Float, spread: Float) {
            let sorted = present.map { values[$0] }.sorted()
            let median = sorted[sorted.count / 2]
            let deviations = sorted.map { abs($0 - median) }.sorted()
            // A robust spread, floored so a face that never moves doesn't turn noise into reactions.
            return (median, max(deviations[deviations.count / 2] * 1.4826, median * 0.05, 0.003))
        }
        let open = rest(series.mouthOpen), width = rest(series.mouthWidth), eyes = rest(series.eyeOpen), brows = rest(series.browRaise)
        // How far past this face's own rest (and its ordinary wobble) a measure is, against the change a full
        // reaction makes: a mouth open by a quarter of its width, a mouth a quarter wider, eyes or brows half as
        // open or as high again.
        func past(_ value: Float, _ rest: (median: Float, spread: Float), full: Float) -> Float {
            min(1, max(0, (value - rest.median - 2 * rest.spread) / max(full, 0.001)))
        }
        var out = [Float](repeating: 0, count: n)
        for i in present {
            let score = 0.5 * past(series.mouthOpen[i], open, full: 0.25) + 0.25 * past(series.mouthWidth[i], width, full: width.median * 0.25)
                + 0.15 * past(series.eyeOpen[i], eyes, full: eyes.median * 0.5) + 0.1 * past(series.browRaise[i], brows, full: max(brows.median, 0.02) * 0.5)
            // A dropped jaw with wide eyes and raised brows, or a wide open laugh, is a full reaction.
            out[i] = min(1, score / 0.75)
        }
        return out
    }

    /// The reaction signal on the engagement model's grid: `step` seconds a sample, `duration` long.
    public static func signal(_ series: ExpressionSeries?, duration: Seconds, step: Seconds) -> [Float] {
        guard let series, series.hop > 0, step > 0, series.count > 0 else { return [] }
        let values = intensity(series)
        let n = max(1, Int((duration / step).rounded(.up)))
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let index = Int((Double(i) * step / series.hop).rounded(.down))
            if index >= 0, index < values.count { out[i] = values[index] }
        }
        return out
    }
}
