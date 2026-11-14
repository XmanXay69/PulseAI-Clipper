import Foundation

/// Trimming a cut while it plays in a loop (#661): the edit plays the seconds around one cut over and over,
/// and each press moves the cut a frame earlier or later. The cut is judged by eye and ear as it moves,
/// which is how a cut that feels right is found.
public enum TrimLoop {
    /// A cut on the main picture track: the clip it follows and where it is.
    public struct Cut: Hashable, Sendable {
        public var clipID: UUID
        public var time: Seconds

        public init(clipID: UUID, time: Seconds) {
            self.clipID = clipID
            self.time = time
        }
    }

    /// The cut on the main picture track nearest `time`, when one is within `reach` seconds. A cut is where
    /// one clip ends and the next begins with no gap.
    public static func nearestCut(in timeline: Timeline, to time: Seconds, reach: Seconds = 10) -> Cut? {
        guard let track = timeline.tracks.first(where: { $0.kind == .video && !$0.clips.isEmpty }) else { return nil }
        var best: Cut?
        for (clip, next) in zip(track.clips, track.clips.dropFirst()) where abs(next.start - clip.end) < 0.05 {
            if abs(clip.end - time) <= reach, abs(clip.end - time) < abs((best?.time ?? .infinity) - time) {
                best = Cut(clipID: clip.id, time: clip.end)
            }
        }
        return best
    }

    /// The stretch that plays while trimming: `lead` seconds either side of the cut, inside the edit.
    public static func range(around cut: Seconds, in timeline: Timeline, lead: Seconds = 2) -> TimeRange {
        TimeRange(start: max(0, cut - lead), end: min(timeline.duration, cut + lead))
    }

    /// Moves the cut after `clipID` by `frames` (negative = earlier). The sound linked to the two clips moves
    /// with them (the roll edit keeps linked clips together), the edit keeps its length, and the cut stops where
    /// a clip or the recording runs out. Returns where the cut is now, or nil when there is no cut after that clip.
    @discardableResult
    public static func roll(_ timeline: inout Timeline, after clipID: UUID, frames: Int, mediaDuration: Seconds? = nil) -> Seconds? {
        guard let location = timeline.location(ofClip: clipID) else { return nil }
        let track = timeline.tracks[location.trackIndex]
        guard location.clipIndex + 1 < track.clips.count else { return nil }
        let clip = track.clips[location.clipIndex], next = track.clips[location.clipIndex + 1]
        guard abs(next.start - clip.end) < 0.05 else { return nil }
        guard frames != 0 else { return clip.end }
        let delta = Double(frames) / max(timeline.canvas.frameRate, 1)
        var rolled = timeline
        guard (try? rolled.roll(edgeAfter: clipID, by: delta, mediaDuration: mediaDuration)) != nil else { return clip.end }
        timeline = rolled
        return timeline.location(ofClip: clipID).map { timeline.tracks[$0.trackIndex].clips[$0.clipIndex].end }
    }
}
