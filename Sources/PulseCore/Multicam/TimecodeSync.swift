import Foundation

/// Sync by the timecode the cameras wrote (#325): when every recording carries a start timecode, the
/// offsets are exact and no audio has to be listened to.
public enum TimecodeSync {
    public struct Result: Hashable, Sendable {
        /// Session offset per recording (the earliest starts at 0).
        public var offsets: [UUID: Seconds]
        /// 1 when timecode decided it; audio sync reports its own.
        public var confidence: Double
        public var method: String
    }

    /// Offsets from start timecodes, or nil unless every recording has one and they agree on a day
    /// (a camera rolled over midnight when the spread passes 20 hours).
    public static func offsets(startTimecodes: [UUID: Seconds]) -> Result? {
        guard startTimecodes.count >= 2 else { return nil }
        let values = startTimecodes.values
        guard let earliest = values.min(), let latest = values.max(), latest - earliest < 20 * 3600 else { return nil }
        var out: [UUID: Seconds] = [:]
        for (id, tc) in startTimecodes { out[id] = tc - earliest }
        return Result(offsets: out, confidence: 1, method: "timecode")
    }

    /// "Timecode" / "Audio · 82 %" for the activity line.
    public static func describe(_ result: Result) -> String {
        result.method == "timecode" ? "Timecode" : String(format: "Audio · %.0f %%", result.confidence * 100)
    }
}
