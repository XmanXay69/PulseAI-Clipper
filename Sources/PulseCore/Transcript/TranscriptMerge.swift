import Foundation

extension Transcript {
    /// The words inside `range` replaced by `fresh` (already in source time): a re-transcribed stretch (#42).
    /// Words straddling the edge are kept when most of them lies outside.
    public func replacingWords(in range: TimeRange, with fresh: [TranscriptWord]) -> Transcript {
        var copy = self
        let kept = words.filter { w in
            let inside = TimeRange(start: max(w.start, range.start), end: min(w.end, range.end))
            return inside.end <= inside.start || inside.duration < w.range.duration * 0.5
        }
        copy.words = (kept + fresh.filter { range.contains($0.start) }).sorted { $0.start < $1.start }
        copy.createdAt = Date()
        return copy
    }
}
