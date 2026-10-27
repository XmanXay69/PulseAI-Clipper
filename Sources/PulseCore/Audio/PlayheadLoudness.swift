import Foundation

/// Momentary / short-term / integrated loudness of the mix at the playhead (#262), read off the
/// recordings' analysed RMS through every clip's gain, so it costs nothing while playing. It's a close
/// stand-in for LUFS on speech (no K-weighting), good to about a dB.
public enum PlayheadLoudness {
    public static let momentaryWindow: Seconds = 0.4
    public static let shortTermWindow: Seconds = 3

    public enum Verdict: Equatable, Sendable { case quiet, onTarget, hot }

    /// The mix level at timeline time `t` in dB (power sum of every audible clip), or nil when nothing
    /// audible under the playhead has an analysis.
    public static func level(_ timeline: Timeline, at t: Seconds, features: (UUID) -> AudioFeatureSeries?) -> Double? {
        let soloed = timeline.tracks.contains { $0.kind == .audio && $0.isSolo }
        var power = 0.0
        var any = false
        for track in timeline.tracks where track.kind != .text && !track.isMuted && track.volume > 0 {
            if soloed, track.kind == .audio, !track.isSolo { continue }
            for clip in track.clips where clip.isEnabled && !clip.audio.isMuted && clip.timelineRange.contains(t) {
                guard let assetID = clip.assetID, let series = features(assetID), series.hop > 0, series.rmsDB.count > 0 else { continue }
                let local = t - clip.start
                let source = clip.sourceIn + local * clip.speed
                let index = Int(source / series.hop)
                guard index >= 0, index < series.rmsDB.count else { continue }
                let gain = clip.audio.gainDB + 20 * log10(max(clip.audio.volume.value(at: local) * track.volume, 1e-6))
                let db = Double(series.rmsDB[index]) + gain
                power += pow(10, db / 10)
                any = true
            }
        }
        guard any else { return nil }
        return 10 * log10(max(power, 1e-12))
    }

    /// Mean power over the `window` ending at `t`.
    public static func windowed(_ timeline: Timeline, at t: Seconds, window: Seconds, step: Seconds = 0.05, features: (UUID) -> AudioFeatureSeries?) -> Double? {
        var sum = 0.0
        var n = 0
        var s = max(0, t - window)
        while s <= t {
            if let db = level(timeline, at: s, features: features) { sum += pow(10, db / 10); n += 1 }
            s += step
        }
        guard n > 0 else { return nil }
        return 10 * log10(max(sum / Double(n), 1e-12))
    }

    public static func momentary(_ timeline: Timeline, at t: Seconds, features: (UUID) -> AudioFeatureSeries?) -> Double? {
        windowed(timeline, at: t, window: momentaryWindow, features: features)
    }

    public static func shortTerm(_ timeline: Timeline, at t: Seconds, features: (UUID) -> AudioFeatureSeries?) -> Double? {
        windowed(timeline, at: t, window: shortTermWindow, step: 0.1, features: features)
    }

    /// Integrated loudness of the whole timeline with the standard gates: blocks below −70 dB are
    /// ignored, then blocks more than 10 dB under the mean of the rest.
    public static func integrated(_ timeline: Timeline, features: (UUID) -> AudioFeatureSeries?) -> Double? {
        let duration = timeline.duration
        guard duration > 0 else { return nil }
        var blocks: [Double] = []
        var t = momentaryWindow
        while t <= duration {
            if let m = windowed(timeline, at: t, window: momentaryWindow, step: 0.1, features: features), m > -70 { blocks.append(m) }
            t += 0.1
        }
        guard !blocks.isEmpty else { return nil }
        func mean(_ xs: [Double]) -> Double { 10 * log10(xs.map { pow(10, $0 / 10) }.reduce(0, +) / Double(xs.count)) }
        let gate = mean(blocks) - 10
        let kept = blocks.filter { $0 >= gate }
        return kept.isEmpty ? mean(blocks) : mean(kept)
    }

    public static func verdict(_ lufs: Double, target: Double, tolerance: Double = 1) -> Verdict {
        if lufs > target + tolerance { return .hot }
        if lufs < target - tolerance { return .quiet }
        return .onTarget
    }
}
