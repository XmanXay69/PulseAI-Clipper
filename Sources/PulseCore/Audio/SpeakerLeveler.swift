import Foundation

/// Guests as loud as the host (#266): each speaker's level is measured from the words they said, and the
/// dialogue clips get volume steps so everyone sits at the host's level.
public enum SpeakerLeveler {
    /// Gain in dB per speaker id, relative to the speaker with the most words. Speakers with fewer than
    /// `minimumWords` words aren't touched. Clamped to ±9 dB.
    public static func gains(words: [TranscriptWord], audio: AudioFeatureSeries, minimumWords: Int = 20) -> [Int: Double] {
        guard audio.count > 0, audio.hop > 0 else { return [:] }
        var levels: [Int: [Float]] = [:]
        for w in words {
            guard let speaker = w.speaker else { continue }
            let i = Int((w.start + w.end) / 2 / audio.hop)
            guard i >= 0, i < audio.count, audio.rmsDB.values[i] > -55 else { continue }
            levels[speaker, default: []].append(audio.rmsDB.values[i])
        }
        let counted = levels.filter { $0.value.count >= minimumWords }
        guard counted.count >= 2, let host = counted.max(by: { $0.value.count < $1.value.count }) else { return [:] }
        func median(_ v: [Float]) -> Double { let s = v.sorted(); return Double(s[s.count / 2]) }
        let reference = median(host.value)
        var out: [Int: Double] = [:]
        for (speaker, values) in counted where speaker != host.key {
            let gain = (reference - median(values)).clamped(-9, 9)
            if abs(gain) >= 0.5 { out[speaker] = (gain * 10).rounded() / 10 }
        }
        return out
    }

    /// Volume steps on every clip carrying the recording's audio: a keyframe where each speaker starts
    /// talking (held until the next). Returns keyframes added.
    @discardableResult
    public static func apply(_ timeline: inout Timeline, assetID: UUID, words: [TranscriptWord], gains: [Int: Double]) -> Int {
        guard !gains.isEmpty else { return 0 }
        // Runs of one speaker, in source time.
        var runs: [(start: Seconds, speaker: Int?)] = []
        for w in words {
            if let last = runs.last, last.speaker == w.speaker { continue }
            runs.append((w.start, w.speaker))
        }
        var added = 0
        for ti in timeline.tracks.indices where timeline.tracks[ti].kind == .audio {
            for ci in timeline.tracks[ti].clips.indices where timeline.tracks[ti].clips[ci].content.assetID == assetID {
                let clip = timeline.tracks[ti].clips[ci]
                var volume = clip.audio.volume
                let base = volume.value
                var current: Int? = runs.last(where: { $0.start <= clip.sourceIn })?.speaker
                let initial = base * pow(10, (current.flatMap { gains[$0] } ?? 0) / 20)
                volume = AnimatedDouble(initial)
                guard runs.contains(where: { $0.start > clip.sourceIn && $0.start < clip.sourceOut && $0.speaker != current }) else {
                    timeline.tracks[ti].clips[ci].audio.volume = volume
                    continue
                }
                // A keyframe at the start too: before the first keyframe a curve reads its first value.
                volume.setKeyframe(at: 0, value: initial, interpolation: .hold, aiGenerated: true)
                for run in runs where run.start > clip.sourceIn && run.start < clip.sourceOut {
                    guard run.speaker != current else { continue }
                    current = run.speaker
                    let local = (run.start - clip.sourceIn) / max(clip.speed, 0.01)
                    volume.setKeyframe(at: local, value: base * pow(10, (run.speaker.flatMap { gains[$0] } ?? 0) / 20), interpolation: .hold, aiGenerated: true)
                    added += 1
                }
                timeline.tracks[ti].clips[ci].audio.volume = volume
            }
        }
        if added > 0 { timeline.modifiedAt = Date() }
        return added
    }
}
