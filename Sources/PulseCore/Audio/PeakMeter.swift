import Foundation

/// Level meters fed from the cached waveform peaks (#194, #281): cheap enough to run on every frame,
/// close enough to what the mix is doing to catch a hot clip or a dead track.
public enum PeakMeter {
    /// Peak (0…1) of `peaks` around `time`, over a window `window` wide.
    public static func level(peaks: [Float], at time: Seconds, perSecond: Double, window: Seconds = 0.05) -> Float {
        guard !peaks.isEmpty, perSecond > 0, time.isFinite else { return 0 }
        let first = Int(((time - window / 2) * perSecond).rounded(.down))
        let last = Int(((time + window / 2) * perSecond).rounded(.up))
        let lo = max(0, first), hi = min(peaks.count - 1, last)
        guard lo <= hi else { return 0 }
        var best: Float = 0
        for i in lo...hi where peaks[i] > best { best = peaks[i] }
        return best
    }

    /// 0…1 → dBFS, floored at −60.
    public static func dB(_ level: Float) -> Float {
        guard level > 0 else { return -60 }
        return max(-60, 20 * log10f(level))
    }

    /// Where a level sits on a meter from −60 dB (0) to 0 dB (1).
    public static func fraction(_ level: Float) -> Float {
        (dB(level) + 60) / 60
    }

    /// Peak-hold ballistics: the bar falls at a steady rate, the hold tick stays put for a moment, and
    /// clipping sticks until it's reset.
    public struct Ballistics: Hashable, Sendable {
        public var level: Float = 0
        public var hold: Float = 0
        public var clipped = false
        var holdUntil: Seconds = 0
        var lastTime: Seconds?

        public init() {}

        public mutating func update(level input: Float, at t: Seconds, holdTime: Seconds = 1.5, decayPerSecond: Float = 1.2) {
            let dt = Float(max(0, t - (lastTime ?? t)))
            lastTime = t
            level = max(input, level - decayPerSecond * dt)
            if input >= hold || t >= holdUntil {
                hold = input
                holdUntil = t + holdTime
            }
            if input >= 0.99 { clipped = true }
        }

        public mutating func reset() {
            level = 0
            hold = 0
            clipped = false
            holdUntil = 0
            lastTime = nil
        }
    }
}

/// Levels of a timeline's tracks at a point in time, from each clip's peaks and gains.
public enum MixMeter {
    /// The peak of `track` at timeline time `t`: the loudest clip under the playhead after its volume,
    /// gain and the track's own volume. Muted tracks and clips read 0.
    public static func trackLevel(_ track: Track, at t: Seconds, perSecond: Double, peaks: (UUID) -> [Float]?) -> Float {
        guard !track.isMuted, track.volume > 0 else { return 0 }
        var best: Float = 0
        for clip in track.clips where clip.isEnabled && !clip.audio.isMuted && clip.timelineRange.contains(t) {
            guard let assetID = clip.assetID, let series = peaks(assetID) else { continue }
            let local = t - clip.start
            let source = clip.sourceIn + local * clip.speed
            let raw = PeakMeter.level(peaks: series, at: source, perSecond: perSecond)
            let gain = Float(clip.audio.volume.value(at: local) * pow(10, clip.audio.gainDB / 20))
            best = max(best, raw * gain)
        }
        return best * Float(track.volume)
    }

    /// Every audible track's level, honouring solo; the master is their sum (what the mix bus sees).
    public static func levels(_ timeline: Timeline, at t: Seconds, perSecond: Double, peaks: (UUID) -> [Float]?) -> (tracks: [UUID: Float], master: Float) {
        let soloed = timeline.tracks.contains { $0.kind == .audio && $0.isSolo }
        var out: [UUID: Float] = [:]
        var sum: Float = 0
        for track in timeline.tracks where track.kind != .text {
            if soloed, track.kind == .audio, !track.isSolo { out[track.id] = 0; continue }
            let level = trackLevel(track, at: t, perSecond: perSecond, peaks: peaks)
            out[track.id] = level
            sum += level
        }
        return (out, sum)
    }
}
