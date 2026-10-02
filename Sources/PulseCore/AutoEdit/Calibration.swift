import Foundation

/// What PULSE predicted for an edit when it was exported — matched later against real analytics.
public struct PerformanceRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var exportedAt: Date
    /// Names the video might have been uploaded under (timeline name, suggested titles, file name).
    public var titles: [String]
    public var format: EditFormat
    public var predictedScore: Int
    public var factors: [String: Double]
    public var duration: Seconds
    /// Filled in from an analytics import.
    public var views: Double?
    public var averagePercentViewed: Double?

    public init(id: UUID = UUID(), exportedAt: Date = Date(), titles: [String], format: EditFormat, predictedScore: Int,
                factors: [String: Double], duration: Seconds, views: Double? = nil, averagePercentViewed: Double? = nil) {
        self.id = id
        self.exportedAt = exportedAt
        self.titles = titles
        self.format = format
        self.predictedScore = predictedScore
        self.factors = factors
        self.duration = duration
        self.views = views
        self.averagePercentViewed = averagePercentViewed
    }

    public init(review: EditReview, titles: [String], duration: Seconds) {
        self.init(titles: titles.filter { !$0.isEmpty }, format: review.prediction.format, predictedScore: review.prediction.score,
                  factors: Dictionary(uniqueKeysWithValues: review.prediction.factors.map { ($0.name, $0.value) }), duration: duration)
    }
}

/// One row of a YouTube Studio / TikTok analytics export.
public struct AnalyticsRow: Hashable, Sendable {
    public var title: String
    public var views: Double
    public var averagePercentViewed: Double?
}

public enum AnalyticsImporter {
    /// Reads a CSV with a title column and a views column (YouTube Studio "Table data.csv", TikTok exports,
    /// or anything similar). Skips total rows.
    public static func parse(_ text: String) -> [AnalyticsRow] {
        var lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else { return [] }
        let header = ChatReplayParser.splitCSV(lines.removeFirst().replacingOccurrences(of: "\u{FEFF}", with: "")).map { $0.lowercased() }
        guard let ti = header.firstIndex(where: { $0.contains("title") }) ?? header.firstIndex(where: { $0 == "content" || $0 == "video" }),
              let vi = header.firstIndex(where: { $0 == "views" || $0 == "video views" || $0.hasSuffix(" views") || $0 == "plays" }) else { return [] }
        let pi = header.firstIndex(where: { $0.contains("average percentage viewed") || $0.contains("avg. percentage") || $0.contains("completion") })
        return lines.compactMap { line in
            let cols = ChatReplayParser.splitCSV(line)
            guard cols.count > max(ti, vi) else { return nil }
            let title = cols[ti]
            guard !title.isEmpty, title.lowercased() != "total", let views = number(cols[vi]) else { return nil }
            return AnalyticsRow(title: title, views: views, averagePercentViewed: pi.flatMap { $0 < cols.count ? number(cols[$0]) : nil })
        }
    }

    static func number(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
    }

    /// Word-overlap similarity of two titles (0…1), ignoring case, emoji and punctuation.
    public static func similarity(_ a: String, _ b: String) -> Double {
        func words(_ s: String) -> Set<String> {
            Set(s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 1 })
        }
        let wa = words(a), wb = words(b)
        guard !wa.isEmpty, !wb.isEmpty else { return 0 }
        return Double(wa.intersection(wb).count) / Double(wa.union(wb).count)
    }

    /// Fills in views on the records whose titles match an analytics row. Returns how many matched.
    @discardableResult
    public static func match(_ rows: [AnalyticsRow], into records: inout [PerformanceRecord], threshold: Double = 0.5) -> Int {
        var matched = 0
        var used = Set<Int>()
        for i in records.indices {
            var best: (index: Int, score: Double)?
            for (ri, row) in rows.enumerated() where !used.contains(ri) {
                let score = records[i].titles.map { similarity($0, row.title) }.max() ?? 0
                if score >= threshold, score > (best?.score ?? 0) { best = (ri, score) }
            }
            if let best {
                used.insert(best.index)
                records[i].views = rows[best.index].views
                records[i].averagePercentViewed = rows[best.index].averagePercentViewed
                matched += 1
            }
        }
        return matched
    }
}

/// Coach weights fitted to your own results: which factors actually tracked with your views.
public struct CoachCalibration: Codable, Hashable, Sendable {
    public var shortWeights: [String: Double]?
    public var longWeights: [String: Double]?
    public var shortSamples: Int
    public var longSamples: Int
    /// e.g. "Edits scoring 70+ got 2.4× the views of the rest".
    public var insight: String

    public init(shortWeights: [String: Double]? = nil, longWeights: [String: Double]? = nil, shortSamples: Int = 0, longSamples: Int = 0, insight: String = "") {
        self.shortWeights = shortWeights
        self.longWeights = longWeights
        self.shortSamples = shortSamples
        self.longSamples = longSamples
        self.insight = insight
    }

    public func weights(for format: EditFormat) -> (weights: [String: Double], samples: Int)? {
        switch format {
        case .short: return shortWeights.map { ($0, shortSamples) }
        case .longForm: return longWeights.map { ($0, longSamples) }
        }
    }

    public var samples: Int { shortSamples + longSamples }
}

public enum CoachCalibrator {
    static let factorNames = ["Hook", "Energy", "Payoff", "Pacing", "Ending", "Length", "Polish"]
    /// Needs at least this many matched videos of a format before it changes anything.
    public static let minimumSamples = 5

    /// Fits weights per format from records with views (ridge regression on log-views, relative to your median).
    public static func fit(_ records: [PerformanceRecord]) -> CoachCalibration {
        var calibration = CoachCalibration()
        for format in [EditFormat.short, .longForm] {
            let rows = records.filter { $0.format == format && ($0.views ?? 0) > 0 }
            guard rows.count >= minimumSamples else { continue }
            let y = rows.map { log10(($0.views ?? 0) + 1) }
            let mean = y.reduce(0, +) / Double(y.count)
            let X = rows.map { r in factorNames.map { (r.factors[$0] ?? 0.5) - 0.5 } }
            let coefficients = ridge(X, y.map { $0 - mean }, lambda: 1.5)
            // Positive influences become weights (a factor that didn't help gets a small floor).
            let defaults = EditCoach.defaultWeights(format)
            var weights: [String: Double] = [:]
            for (i, name) in factorNames.enumerated() {
                let learned = max(0.02, coefficients[i])
                weights[name] = learned
            }
            let total = weights.values.reduce(0, +)
            for name in factorNames { weights[name] = (weights[name] ?? 0) / max(total, 1e-9) }
            // Blend with PULSE's defaults by how much evidence there is.
            let trust = min(1, Double(rows.count) / 20) * 0.8
            for name in factorNames { weights[name] = (defaults[name] ?? 0) * (1 - trust) + (weights[name] ?? 0) * trust }
            if format == .short {
                calibration.shortWeights = weights
                calibration.shortSamples = rows.count
            } else {
                calibration.longWeights = weights
                calibration.longSamples = rows.count
            }
        }
        calibration.insight = insight(records)
        return calibration
    }

    /// How predictions lined up with reality, in plain words.
    static func insight(_ records: [PerformanceRecord]) -> String {
        let rated = records.filter { ($0.views ?? 0) > 0 }
        guard rated.count >= 3 else { return rated.isEmpty ? "" : "Matched \(rated.count) video\(rated.count == 1 ? "" : "s") — a few more and PULSE can calibrate." }
        let high = rated.filter { $0.predictedScore >= 70 }.compactMap(\.views).sorted()
        let low = rated.filter { $0.predictedScore < 70 }.compactMap(\.views).sorted()
        func median(_ v: [Double]) -> Double { v.isEmpty ? 0 : v[v.count / 2] }
        guard !high.isEmpty, !low.isEmpty, median(low) > 0 else { return "Matched \(rated.count) videos." }
        let ratio = median(high) / median(low)
        return ratio >= 1.15
            ? String(format: "Edits PULSE scored 70+ got %.1f× the views of the rest (%d videos).", ratio, rated.count)
            : String(format: "Scores and views didn't line up yet (%d videos) — PULSE is re-weighting toward what worked for you.", rated.count)
    }

    /// Solves (XᵀX + λI) w = Xᵀy.
    static func ridge(_ X: [[Double]], _ y: [Double], lambda: Double) -> [Double] {
        let n = X.first?.count ?? 0
        var A = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        var b = [Double](repeating: 0, count: n)
        for (row, target) in zip(X, y) {
            for i in 0..<n {
                b[i] += row[i] * target
                for j in 0..<n { A[i][j] += row[i] * row[j] }
            }
        }
        for i in 0..<n { A[i][i] += lambda * 0.01 }
        // Gaussian elimination with partial pivoting.
        for col in 0..<n {
            let pivot = (col..<n).max { abs(A[$0][col]) < abs(A[$1][col]) } ?? col
            A.swapAt(col, pivot)
            b.swapAt(col, pivot)
            let p = A[col][col]
            guard abs(p) > 1e-12 else { continue }
            for r in 0..<n where r != col {
                let f = A[r][col] / p
                guard f != 0 else { continue }
                for c in col..<n { A[r][c] -= f * A[col][c] }
                b[r] -= f * b[col]
            }
        }
        return (0..<n).map { abs(A[$0][$0]) > 1e-12 ? b[$0] / A[$0][$0] : 0 }
    }
}
