import Foundation

/// The bars of a waveform visual (#9): a window of the recording's peak envelope around the current time,
/// newest to the right of centre, so a podcast WAV gets a picture that moves with the voice.
public enum AudiogramLayout {
    /// Bar heights (0…1) for `count` bars spanning `span` seconds centred on `time`. Bars outside the file are 0.
    public static func bars(peaks: [Float], perSecond: Double, at time: Seconds, count: Int = 64, span: Seconds = 4) -> [Float] {
        guard count > 0, perSecond > 0 else { return [] }
        let secondsPerBar = span / Double(count)
        var out = [Float](repeating: 0, count: count)
        for b in 0..<count {
            let start = time - span / 2 + Double(b) * secondsPerBar
            let end = start + secondsPerBar
            let first = Int((start * perSecond).rounded(.down))
            let last = Int((end * perSecond).rounded(.up)) - 1
            guard last >= 0, first < peaks.count else { continue }
            var peak: Float = 0
            for i in max(first, 0)...min(last, peaks.count - 1) { peak = max(peak, peaks[i]) }
            out[b] = min(1, max(0, peak))
        }
        return out
    }

    /// Which bar is "now" (the centre).
    public static func centreIndex(count: Int) -> Int { max(0, count / 2) }

    /// A gentle lift so quiet speech still shows: 0 stays 0, 1 stays 1, 0.25 becomes 0.5.
    public static func eased(_ height: Float) -> Float { height <= 0 ? 0 : min(1, Float(sqrt(Double(height)))) }
}

/// Puts a generated waveform video under every clip of an audio-only recording so the long-form edit has a
/// picture (#9). The visual asset was rendered for the whole recording, so timeline clips of the audio map one
/// to one onto it.
public enum AudiogramPlacer {
    /// Mirrors each audio-track clip of `audioAssetID` onto the first video track as a clip of `visualAssetID`
    /// with the same timing, speed and link group. Stretches that already have video are skipped.
    /// Returns how many clips were placed.
    @discardableResult
    public static func place(_ timeline: inout Timeline, audioAssetID: UUID, visualAssetID: UUID) -> Int {
        guard let v = timeline.tracks.firstIndex(where: { $0.kind == .video }) else { return 0 }
        var covered = timeline.tracks[v].clips.map(\.timelineRange)
        var placed = 0
        for track in timeline.tracks where track.kind == .audio {
            for clip in track.clips {
                guard case .media(let id) = clip.content, id == audioAssetID else { continue }
                let range = clip.timelineRange
                if covered.contains(where: { $0.overlaps(range) }) { continue }
                var visual = TimelineClip(name: clip.name, content: .media(assetID: visualAssetID), start: clip.start, sourceIn: clip.sourceIn,
                                          sourceDuration: clip.sourceDuration, linkGroup: clip.linkGroup ?? UUID(), role: .main, aiGenerated: true)
                visual.speed = clip.speed
                visual.audio.isMuted = true
                timeline.tracks[v].clips.append(visual)
                covered.append(range)
                placed += 1
            }
        }
        timeline.tracks[v].clips.sort { $0.start < $1.start }
        return placed
    }

    /// Tag on the generated asset that ties it to its recording.
    public static func tag(for audioAssetID: UUID) -> String { "audiogram:\(audioAssetID.uuidString)" }
}
