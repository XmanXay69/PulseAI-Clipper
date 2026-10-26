import Foundation

/// What happens to the audio under a censored caption word.
public enum CensorAudio: String, Codable, CaseIterable, Sendable {
    case off, mute, bleep

    public var displayName: String {
        switch self {
        case .off: return "Leave it"
        case .mute: return "Mute"
        case .bleep: return "Bleep"
        }
    }
}

/// Mutes or bleeps the swear words in a clip's audio — the same words the caption filter masks — as part of
/// the (non-destructive) enhance render. Ranges live on the clip in source time; the render maps them.
public enum AudioCensor {
    public static let bleepHz = 1000.0
    public static let bleepDB = -14.0

    /// Source-time ranges of the profane words inside `range`, padded by `pad` and merged when they touch.
    public static func ranges(words: [TranscriptWord], in range: TimeRange, extra: Set<String> = [], pad: Seconds = 0.04) -> [TimeRange] {
        var out: [TimeRange] = []
        for w in words where w.end > range.start && w.start < range.end {
            let n = TranscriptWord.normalize(w.text)
            guard EngagementLexicon.isProfane(n) || extra.contains(n) else { continue }
            let r = TimeRange(start: max(range.start, w.start - pad), end: min(range.end, w.end + pad))
            guard r.duration > 0 else { continue }
            if let last = out.last, r.start <= last.end + 0.02 {
                out[out.count - 1] = TimeRange(start: last.start, end: max(last.end, r.end))
            } else {
                out.append(r)
            }
        }
        return out
    }

    /// Sets censoring on every clip of `assetID` in the timeline (off clears it). Returns how many stretches are covered.
    @discardableResult
    public static func apply(_ mode: CensorAudio, to timeline: inout Timeline, words: [TranscriptWord], assetID: UUID, extra: Set<String> = [],
                             tone: Double = 1000) -> Int {
        var count = 0
        for t in timeline.tracks.indices {
            for c in timeline.tracks[t].clips.indices where timeline.tracks[t].clips[c].content.assetID == assetID {
                let clip = timeline.tracks[t].clips[c]
                let found = mode == .off ? [] : ranges(words: words, in: clip.sourceRange, extra: extra)
                timeline.tracks[t].clips[c].audio.censor = found.isEmpty ? .off : mode
                timeline.tracks[t].clips[c].audio.censorRanges = found
                timeline.tracks[t].clips[c].audio.censorTone = tone
                count += found.count
            }
        }
        return count
    }

    /// Replaces clip-relative ranges with silence or a 1 kHz tone, with 5 ms ramps so there are no clicks.
    public static func process(_ channels: inout [[Float]], sampleRate: Double, ranges: [TimeRange], mode: CensorAudio, frequency: Double = bleepHz) {
        guard mode != .off, let length = channels.first?.count, length > 0, sampleRate > 0 else { return }
        let ramp = max(1, Int(sampleRate * 0.005))
        let tone = Float(pow(10, bleepDB / 20))
        let bleepHz = frequency.clamped(200, 4000)
        for r in ranges {
            let a = max(0, Int(r.start * sampleRate)), b = min(length, Int(r.end * sampleRate))
            guard b > a else { continue }
            for i in a..<b {
                let edge = min(i - a, b - 1 - i)
                let w = edge < ramp ? Float(edge) / Float(ramp) : 1
                let replacement: Float = mode == .bleep ? tone * Float(sin(2 * Double.pi * bleepHz * Double(i - a) / sampleRate)) : 0
                for c in channels.indices where i < channels[c].count {
                    channels[c][i] = channels[c][i] * (1 - w) + replacement * w
                }
            }
        }
    }
}
