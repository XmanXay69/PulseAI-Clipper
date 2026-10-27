import Foundation

/// A moment found while the recording is still running (#481): the voice jumps well above its own recent
/// level and stays there for a beat. Fed with the microphone meter a few times a second; no transcript,
/// no video — just enough to say "that was probably something" and seed the analysis with it.
public struct LiveMoment: Codable, Hashable, Sendable, Identifiable {
    public var time: Seconds
    /// 0…1: how far above the usual level the burst went.
    public var strength: Double
    public var id: Int { Int((time * 10).rounded()) }

    public init(time: Seconds, strength: Double) {
        self.time = time
        self.strength = strength
    }
}

public struct LiveMomentDetector: Sendable {
    /// dB above the rolling baseline that counts as a burst.
    public var threshold: Float = 9
    /// A burst has to hold this long before it counts (meter samples are a quarter second apart).
    public var hold: Seconds = 0.3
    /// Two moments can't be closer than this.
    public var refractory: Seconds = 20
    /// The quietest the baseline may sit, so a silent room doesn't make every word a moment.
    public var floorDB: Float = -45

    private var baseline: Float?
    private var burstStart: Seconds?
    private var burstPeak: Float = -60
    private var lastMoment: Seconds = -.infinity
    public private(set) var moments: [LiveMoment] = []

    public init() {}

    /// Feeds one meter reading (peak dBFS, −60…0) at recording time `time`. Returns a moment when one just
    /// completed. The baseline follows speech slowly (about 30 s) and ignores the bursts themselves.
    public mutating func feed(levelDB: Float, at time: Seconds) -> LiveMoment? {
        let level = max(-60, min(0, levelDB))
        guard let base = baseline else {
            baseline = max(level, floorDB)
            return nil
        }
        let above = level - max(base, floorDB)
        var found: LiveMoment?
        if above >= threshold {
            if burstStart == nil { burstStart = time; burstPeak = level }
            burstPeak = max(burstPeak, level)
            if let start = burstStart, time - start >= hold, time - lastMoment >= refractory {
                let strength = Double(min(1, (burstPeak - max(base, floorDB) - threshold) / 12 + 0.5))
                let moment = LiveMoment(time: start, strength: strength)
                moments.append(moment)
                lastMoment = start
                found = moment
            }
        } else {
            burstStart = nil
            // Only ordinary levels move the baseline; loud bursts never raise it.
            baseline = base * 0.98 + level * 0.02
        }
        return found
    }

    /// The moments as banner-like events for the analysis.
    public static func events(from moments: [LiveMoment]) -> [HUDEvent] {
        moments.map { HUDEvent(time: $0.time, kind: .live, text: "LIVE MOMENT", confidence: max(0.4, $0.strength)) }
    }
}
