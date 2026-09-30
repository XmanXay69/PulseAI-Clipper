import Foundation

public enum SilencePreset: String, Codable, CaseIterable, Sendable {
    case conservative
    case balanced
    case aggressive

    public var displayName: String { rawValue.capitalized }

    /// Silences shorter than this are left alone.
    public var minimumSilence: Seconds {
        switch self {
        case .conservative: return 1.2
        case .balanced: return 0.7
        case .aggressive: return 0.4
        }
    }

    /// Breathing room kept on each side of a cut.
    public var padding: Seconds {
        switch self {
        case .conservative: return 0.3
        case .balanced: return 0.18
        case .aggressive: return 0.08
        }
    }

    public var summary: String {
        switch self {
        case .conservative: return "Removes only long pauses (1.2 s+). Keeps natural pacing."
        case .balanced: return "Removes pauses over 0.7 s. Good default for shorts."
        case .aggressive: return "Jump-cut style. Removes almost every pause over 0.4 s."
        }
    }
}

/// Finds removable dead air using audio levels, protected by transcript word timings.
public enum SilenceDetector {
    public static func detect(audio: AudioFeatureSeries?, transcript: Transcript?, in range: TimeRange, preset: SilencePreset) -> [TimeRange] {
        let minSilence = preset.minimumSilence
        let pad = preset.padding
        var silentRuns: [TimeRange] = []

        if let audio, audio.count > 0 {
            let a = audio.index(at: range.start)
            let b = audio.index(at: max(range.start, range.end - audio.hop / 2))
            guard b > a else { return [] }
            let levels = Array(audio.rmsDB.values[a...b])
            let noiseFloor = SeriesMath.percentile(levels, 0.1)
            let speech = SeriesMath.percentile(levels, 0.9)
            // Threshold sits a quarter of the way from the noise floor to typical speech level.
            let threshold = min(noiseFloor + max((speech - noiseFloor) * 0.25, 6), -28)
            var protected = [Bool](repeating: false, count: levels.count)
            if let transcript {
                for word in transcript.words(in: range) {
                    let wa = audio.index(at: word.start) - a
                    let wb = audio.index(at: word.end) - a
                    if wb < 0 || wa >= levels.count { continue }
                    for i in max(wa, 0)...min(wb, levels.count - 1) { protected[i] = true }
                }
            }
            var runStart: Int?
            for i in 0...levels.count {
                let silent = i < levels.count && levels[i] < threshold && !protected[i]
                if silent {
                    if runStart == nil { runStart = i }
                } else if let s = runStart {
                    let start = Double(a + s) * audio.hop
                    let end = Double(a + i) * audio.hop
                    if end - start >= minSilence { silentRuns.append(TimeRange(start: start, end: end)) }
                    runStart = nil
                }
            }
        } else if let transcript {
            let words = Array(transcript.words(in: range))
            var cursor = range.start
            for w in words {
                if w.start - cursor >= minSilence { silentRuns.append(TimeRange(start: cursor, end: w.start)) }
                cursor = max(cursor, w.end)
            }
            if range.end - cursor >= minSilence { silentRuns.append(TimeRange(start: cursor, end: range.end)) }
        }

        return silentRuns.compactMap { run -> TimeRange? in
            // Never pad past the clip bounds; edges of the clip get trimmed fully.
            let s = run.start <= range.start + 0.01 ? run.start : run.start + pad
            let e = run.end >= range.end - 0.01 ? run.end : run.end - pad
            guard e - s > 0.05 else { return nil }
            return TimeRange(start: s, end: e).clamped(to: range)
        }.filter { !$0.isEmpty }
    }

    /// Fraction of `range` that is silent (used by the ending-quality score).
    public static func silentFraction(audio: AudioFeatureSeries, in range: TimeRange, threshold: Float) -> Double {
        guard audio.count > 0, range.duration > 0 else { return 0 }
        let a = audio.index(at: range.start)
        let b = max(a, audio.index(at: range.end - audio.hop / 2))
        var silent = 0
        for i in a...b where audio.rmsDB[i] < threshold { silent += 1 }
        return Double(silent) / Double(b - a + 1)
    }
}
