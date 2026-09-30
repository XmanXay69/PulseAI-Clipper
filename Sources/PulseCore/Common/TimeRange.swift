import Foundation

/// Time in seconds. PULSE models time as `Double` seconds; the engine converts to
/// `CMTime` (timescale 600 or the media's native timescale) at the AVFoundation boundary.
public typealias Seconds = Double

/// Half-open time interval `[start, end)`.
public struct TimeRange: Codable, Hashable, Sendable, CustomStringConvertible {
    public static let epsilon: Seconds = 1e-6

    public var start: Seconds
    public var end: Seconds

    public init(start: Seconds, end: Seconds) {
        self.start = start
        self.end = Swift.max(start, end)
    }

    public init(start: Seconds, duration: Seconds) {
        self.init(start: start, end: start + Swift.max(0, duration))
    }

    public static let zero = TimeRange(start: 0, end: 0)

    public var duration: Seconds { end - start }
    public var isEmpty: Bool { duration <= TimeRange.epsilon }
    public var midpoint: Seconds { (start + end) / 2 }

    public func contains(_ time: Seconds) -> Bool {
        time >= start - TimeRange.epsilon && time < end - TimeRange.epsilon
    }

    public func contains(_ other: TimeRange) -> Bool {
        other.start >= start - TimeRange.epsilon && other.end <= end + TimeRange.epsilon
    }

    public func overlaps(_ other: TimeRange) -> Bool {
        other.start < end - TimeRange.epsilon && other.end > start + TimeRange.epsilon
    }

    public func intersection(_ other: TimeRange) -> TimeRange? {
        let s = Swift.max(start, other.start)
        let e = Swift.min(end, other.end)
        guard e - s > TimeRange.epsilon else { return nil }
        return TimeRange(start: s, end: e)
    }

    public func union(_ other: TimeRange) -> TimeRange {
        TimeRange(start: Swift.min(start, other.start), end: Swift.max(end, other.end))
    }

    /// Intersection-over-union, used for de-duplicating clip candidates.
    public func iou(_ other: TimeRange) -> Double {
        guard let i = intersection(other) else { return 0 }
        let u = union(other).duration
        return u > 0 ? i.duration / u : 0
    }

    public func clamped(to bounds: TimeRange) -> TimeRange {
        let s = Swift.min(Swift.max(start, bounds.start), bounds.end)
        let e = Swift.min(Swift.max(end, bounds.start), bounds.end)
        return TimeRange(start: s, end: e)
    }

    public func offset(by delta: Seconds) -> TimeRange {
        TimeRange(start: start + delta, end: end + delta)
    }

    public func expanded(by amount: Seconds) -> TimeRange {
        TimeRange(start: start - amount, end: end + amount)
    }

    public var description: String {
        "[\(Timecode.short(start)) → \(Timecode.short(end))]"
    }
}

extension Array where Element == TimeRange {
    /// Sorts and merges overlapping/adjacent ranges.
    public func merged(gap: Seconds = TimeRange.epsilon) -> [TimeRange] {
        let sorted = self.filter { !$0.isEmpty }.sorted { $0.start < $1.start }
        var result: [TimeRange] = []
        for range in sorted {
            if let last = result.last, range.start <= last.end + gap {
                result[result.count - 1] = TimeRange(start: last.start, end: Swift.max(last.end, range.end))
            } else {
                result.append(range)
            }
        }
        return result
    }

    /// Total covered duration after merging.
    public var totalDuration: Seconds {
        merged().reduce(0) { $0 + $1.duration }
    }

    /// Returns `bounds` minus all ranges in `self` (the complement within bounds).
    public func complement(within bounds: TimeRange) -> [TimeRange] {
        var result: [TimeRange] = []
        var cursor = bounds.start
        for range in merged() {
            guard let clipped = range.intersection(bounds) else { continue }
            if clipped.start > cursor + TimeRange.epsilon {
                result.append(TimeRange(start: cursor, end: clipped.start))
            }
            cursor = Swift.max(cursor, clipped.end)
        }
        if bounds.end > cursor + TimeRange.epsilon {
            result.append(TimeRange(start: cursor, end: bounds.end))
        }
        return result
    }
}

/// Formatting helpers for timecodes shown throughout the UI.
public enum Timecode {
    /// `HH:MM:SS:FF` when fps is given, else `HH:MM:SS.mmm`.
    public static func string(_ seconds: Seconds, fps: Double? = nil) -> String {
        let clamped = Swift.max(0, seconds.isFinite ? seconds : 0)
        let totalSeconds = Int(clamped)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if let fps, fps > 0 {
            let frames = Int(((clamped - Double(totalSeconds)) * fps).rounded(.down))
            return String(format: "%02d:%02d:%02d:%02d", h, m, s, Swift.min(frames, Int(fps.rounded(.up)) - 1))
        }
        let ms = Int(((clamped - Double(totalSeconds)) * 1000).rounded(.down))
        return String(format: "%02d:%02d:%02d.%03d", h, m, s, ms)
    }

    /// Compact form: `42:17` or `1:02:03`.
    public static func short(_ seconds: Seconds) -> String {
        let clamped = Swift.max(0, seconds.isFinite ? seconds : 0)
        let totalSeconds = Int(clamped.rounded(.down))
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    /// Human duration: `30s`, `1m 05s`, `2h 03m`.
    public static func duration(_ seconds: Seconds) -> String {
        let total = Int(Swift.max(0, seconds.isFinite ? seconds : 0).rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        if m > 0 { return String(format: "%dm %02ds", m, s) }
        return "\(s)s"
    }

    /// Parses `HH:MM:SS,mmm`, `HH:MM:SS.mmm`, `MM:SS.mmm` or plain seconds.
    public static func parse(_ text: String) -> Seconds? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = trimmed.split(separator: ":").map(String.init)
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        var total: Double = 0
        for part in parts {
            guard let value = Double(part) else { return nil }
            total = total * 60 + value
        }
        return total
    }
}

extension Double {
    /// Clamps a value into a closed range.
    public func clamped(_ lower: Double, _ upper: Double) -> Double {
        Swift.min(Swift.max(self, lower), upper)
    }
}

extension Float {
    public func clamped(_ lower: Float, _ upper: Float) -> Float {
        Swift.min(Swift.max(self, lower), upper)
    }
}

extension Int {
    public func clamped(_ lower: Int, _ upper: Int) -> Int {
        Swift.min(Swift.max(self, lower), upper)
    }
}
