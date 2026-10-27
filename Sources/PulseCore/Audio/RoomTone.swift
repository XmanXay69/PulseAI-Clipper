import Foundation

/// Fills the short silences between audio clips with the recording's own room tone (#273), so cuts
/// don't drop to digital silence and back.
public enum RoomTone {
    public static let maxGap: Seconds = 1.5
    public static let minGap: Seconds = 0.04

    /// The quietest `length` of the clip's source, from its analysis (mean RMS over a sliding window).
    public static func quietestWindow(in range: TimeRange, features: AudioFeatureSeries, length: Seconds) -> Seconds? {
        guard features.hop > 0, features.rmsDB.count > 0 else { return nil }
        let hop = features.hop
        let rms = features.rmsDB.values
        let windowHops = max(1, Int((length / hop).rounded(.up)))
        let first = max(0, Int((range.start / hop).rounded(.up)))
        let last = min(rms.count, Int((range.end / hop).rounded(.down)))
        guard last - first >= windowHops else { return nil }
        var best: (start: Int, mean: Float)?
        var sum: Float = 0
        for i in first..<(first + windowHops) { sum += rms[i] }
        var start = first
        while start + windowHops <= last {
            let mean = sum / Float(windowHops)
            if best == nil || mean < best!.mean { best = (start, mean) }
            if start + windowHops < last { sum += rms[start + windowHops] - rms[start] }
            start += 1
        }
        return best.map { Double($0.start) * hop }
    }

    /// Inserts a room-tone clip into every gap between `minGap` and `maxGap` on the audio tracks whose
    /// recordings have an analysis. Returns how many gaps were filled.
    @discardableResult
    public static func fill(_ timeline: inout Timeline, features: [UUID: AudioFeatureSeries], maxGap: Seconds = maxGap, gainDB: Double = -6) -> Int {
        var filled = 0
        for ti in timeline.tracks.indices where timeline.tracks[ti].kind == .audio {
            let clips = timeline.tracks[ti].clips.sorted { $0.start < $1.start }
            var additions: [TimelineClip] = []
            for (a, b) in zip(clips, clips.dropFirst()) {
                let gap = b.start - a.end
                guard gap >= minGap, gap <= maxGap, a.isEnabled, a.speed == 1 else { continue }
                guard let assetID = a.assetID, let series = features[assetID] else { continue }
                guard let quiet = quietestWindow(in: a.sourceRange, features: series, length: max(gap, 0.5)) else { continue }
                var tone = TimelineClip(name: "Room tone", content: .media(assetID: assetID), start: a.end, sourceIn: quiet, sourceDuration: gap,
                                        role: a.role, aiGenerated: true)
                tone.audio.gainDB = gainDB
                tone.audio.fadeIn = min(0.05, gap / 4)
                tone.audio.fadeOut = min(0.05, gap / 4)
                tone.audio.normalize = false
                tone.linkGroup = nil
                additions.append(tone)
            }
            guard !additions.isEmpty else { continue }
            timeline.tracks[ti].clips = (timeline.tracks[ti].clips + additions).sorted { $0.start < $1.start }
            filled += additions.count
        }
        return filled
    }
}
