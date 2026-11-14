import Foundation

/// Finds the stretches of a recording that sound like a music track playing (#521): a steady level with a
/// regular beat, held for a quarter of a minute or more. One copyright claim can cost a video its revenue,
/// so the stretches are flagged before export, when muting or cutting them is still one click.
///
/// A rule of thumb, not a fingerprint. It hears rhythm and steadiness in the loudness and onset curves the
/// analysis already has; it does not know what the song is or who owns it. It can miss quiet music under
/// loud game sound, and it can flag a rhythmic game soundtrack, which is music too and may be just as claimable.
public enum MusicDetector {
    public struct Stretch: Hashable, Codable, Sendable {
        /// In the recording's own time.
        public var range: TimeRange
        /// 0…1: how much it sounds like a music track.
        public var confidence: Double

        public init(range: TimeRange, confidence: Double) {
            self.range = range
            self.confidence = confidence
        }
    }

    /// Seconds of sound judged at a time, and how far the window moves each step.
    static let window: Seconds = 10
    static let step: Seconds = 2

    /// How music-like the window starting at `start` is: nil when it is too quiet or too short to judge.
    static func score(_ audio: AudioFeatureSeries, from start: Int, count: Int) -> Double? {
        guard count >= 40, start >= 0, start + count <= audio.count else { return nil }
        var levels = [Float](repeating: 0, count: count)
        var flux = [Float](repeating: 0, count: count)
        for i in 0..<count {
            levels[i] = audio.rmsDB[start + i]
            flux[i] = audio.spectralFlux[start + i]
        }
        let median = levels.sorted()[count / 2]
        guard median > -50 else { return nil }
        // Steadiness: a track holds its level; speech and gameplay keep dropping away and coming back.
        let near = levels.filter { abs($0 - median) <= 7 }.count
        let steadiness = Double(near) / Double(count)
        // Rhythm: the onsets repeat at a fixed interval somewhere between 0.3 and 1.0 s (60…200 beats a minute).
        let mean = flux.reduce(0, +) / Float(count)
        var variance: Float = 0
        for value in flux { variance += (value - mean) * (value - mean) }
        guard variance > 1e-6 else { return 0 }
        func correlation(_ lag: Int) -> Double {
            guard lag < count else { return 0 }
            var sum: Float = 0
            for i in 0..<(count - lag) { sum += (flux[i] - mean) * (flux[i + lag] - mean) }
            return Double(sum / variance) * Double(count) / Double(count - lag)
        }
        let hop = max(audio.hop, 0.01)
        let lags = max(2, Int((0.3 / hop).rounded()))...max(3, Int((1.0 / hop).rounded()))
        // A beat shows at its own interval and again at twice it; a one-off pair of sounds does not.
        let rhythm = lags.map { 0.6 * correlation($0) + 0.4 * correlation($0 * 2) }.max() ?? 0
        let rhythmic = ((rhythm - 0.2) / 0.4).clamped(0, 1)
        let steady = ((steadiness - 0.55) / 0.3).clamped(0, 1)
        return rhythmic * 0.6 + steady * 0.4 * (rhythmic > 0 ? 1 : 0)
    }

    /// Music-like stretches of at least `minimumLength` seconds. `within` limits the search to those parts of
    /// the recording (the parts an edit uses); nil searches all of it.
    public static func stretches(in audio: AudioFeatureSeries, within ranges: [TimeRange]? = nil, minimumLength: Seconds = 15) -> [Stretch] {
        guard audio.count > 0, audio.hop > 0 else { return [] }
        let frames = Int((window / audio.hop).rounded())
        let stride = max(1, Int((step / audio.hop).rounded()))
        guard audio.count >= frames else { return [] }
        // Windows that sound like music, as (start, end, score) in seconds.
        var hits: [(start: Seconds, end: Seconds, score: Double)] = []
        var index = 0
        while index + frames <= audio.count {
            let start = Double(index) * audio.hop
            let end = start + window
            defer { index += stride }
            if let ranges, !ranges.contains(where: { $0.start < end && $0.end > start }) { continue }
            if let value = score(audio, from: index, count: frames), value >= 0.5 { hits.append((start, end, value)) }
        }
        // Neighbouring windows join; a gap of up to four seconds (a shout over the track) doesn't break a stretch.
        var out: [Stretch] = []
        var current: (start: Seconds, end: Seconds, total: Double, count: Int)?
        // A ten-second window that is half music still hears the beat, so a joined stretch overshoots at both
        // ends. Four-second windows walk each edge in to where the music really starts and stops.
        let small = max(40, Int((4 / audio.hop).rounded()))
        func isMusic(at time: Seconds) -> Bool {
            let from = Int((time / audio.hop).rounded())
            return (score(audio, from: from, count: small) ?? 0) >= 0.5
        }
        func close() {
            guard let c = current else { return }
            current = nil
            var start = c.start, end = c.end
            let length = Double(small) * audio.hop
            while start + length < end, !isMusic(at: start) { start += 1 }
            while end - length > start, !isMusic(at: end - length) { end -= 1 }
            if end - start >= minimumLength {
                out.append(Stretch(range: TimeRange(start: start, end: end), confidence: (c.total / Double(c.count)).clamped(0, 1)))
            }
        }
        for hit in hits {
            if let c = current, hit.start <= c.end + 4 {
                current = (c.start, max(c.end, hit.end), c.total + hit.score, c.count + 1)
            } else {
                close()
                current = (hit.start, hit.end, hit.score, 1)
            }
        }
        close()
        return out
    }
}

/// Music in the recording, as an edit uses it: where in the edit it plays, and how to take it out.
public enum MusicRisk {
    public struct Flag: Hashable, Sendable {
        /// Where it plays in the edit.
        public var range: TimeRange
        public var confidence: Double
    }

    /// The clips that carry the recording's own sound into the mix: on an audio track, switched on and audible.
    static func soundClips(of assetID: UUID, in timeline: Timeline) -> [TimelineClip] {
        timeline.tracks.filter { $0.kind == .audio && !$0.isMuted }.flatMap(\.clips)
            .filter { $0.assetID == assetID && $0.isEnabled && $0.role != .music && $0.role != .soundEffect }
    }

    /// Where the recording's own sound in this edit is music-like. The beds and effects PULSE added are not
    /// looked at: those come from its own library or the Creative Commons search.
    public static func flags(in timeline: Timeline, analysis: MediaAnalysis?) -> [Flag] {
        guard let analysis, let audio = analysis.audio else { return [] }
        let clips = soundClips(of: analysis.assetID, in: timeline)
        guard !clips.isEmpty else { return [] }
        let stretches = MusicDetector.stretches(in: audio, within: clips.map(\.sourceRange))
        guard !stretches.isEmpty else { return [] }
        var flags: [Flag] = []
        for clip in clips {
            let source = clip.sourceRange
            for stretch in stretches where stretch.range.start < source.end && stretch.range.end > source.start {
                let from = max(stretch.range.start, source.start), to = min(stretch.range.end, source.end)
                // Already silenced there: nothing left to claim.
                let middle = clip.timelineTime(atSource: (from + to) / 2) - clip.start
                if clip.audio.volume.value(at: middle) <= 0.02 { continue }
                let range = TimeRange(start: clip.timelineTime(atSource: from), end: clip.timelineTime(atSource: to))
                if range.duration >= 5 { flags.append(Flag(range: range, confidence: stretch.confidence)) }
            }
        }
        flags.sort { $0.range.start < $1.range.start }
        // Pieces that touch read as one.
        var merged: [Flag] = []
        for flag in flags {
            if let last = merged.last, flag.range.start <= last.range.end + 1 {
                merged[merged.count - 1] = Flag(range: TimeRange(start: last.range.start, end: max(last.range.end, flag.range.end)),
                                                confidence: max(last.confidence, flag.confidence))
            } else {
                merged.append(flag)
            }
        }
        return merged
    }

    /// Silences the recording's own sound over the flagged stretches, with a short fade each side. The picture,
    /// the captions and everything PULSE added stay. Returns how many stretches were silenced.
    @discardableResult
    public static func mute(_ flags: [Flag], in timeline: inout Timeline, assetID: UUID) -> Int {
        var silenced = 0
        for flag in flags {
            var touched = false
            for ti in timeline.tracks.indices where timeline.tracks[ti].kind == .audio {
                for ci in timeline.tracks[ti].clips.indices {
                    let clip = timeline.tracks[ti].clips[ci]
                    guard clip.assetID == assetID, clip.isEnabled, clip.role != .music, clip.role != .soundEffect,
                          clip.start < flag.range.end, clip.end > flag.range.start else { continue }
                    let from = max(flag.range.start, clip.start) - clip.start
                    let to = min(flag.range.end, clip.end) - clip.start
                    guard to - from > 0.3 else { continue }
                    var volume = clip.audio.volume
                    let before = volume.value(at: max(0, from - 0.15))
                    let after = volume.value(at: min(clip.duration, to + 0.15))
                    if from > 0.15 { volume.setKeyframe(at: from - 0.15, value: before, interpolation: .linear, aiGenerated: true) }
                    volume.setKeyframe(at: from, value: 0, interpolation: .hold, aiGenerated: true)
                    volume.setKeyframe(at: to, value: 0, interpolation: .linear, aiGenerated: true)
                    if to + 0.15 < clip.duration { volume.setKeyframe(at: to + 0.15, value: after, interpolation: .linear, aiGenerated: true) }
                    timeline.tracks[ti].clips[ci].audio.volume = volume
                    touched = true
                }
            }
            if touched { silenced += 1 }
        }
        if silenced > 0 { timeline.modifiedAt = Date() }
        return silenced
    }

    /// "0:42–1:55 and 6:10–7:02"
    public static func describe(_ flags: [Flag]) -> String {
        let parts = flags.map { "\(Timecode.short($0.range.start))–\(Timecode.short($0.range.end))" }
        switch parts.count {
        case 0: return ""
        case 1: return parts[0]
        case 2, 3: return parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        default: return parts.prefix(2).joined(separator: ", ") + " and \(parts.count - 2) more"
        }
    }
}
