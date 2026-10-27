import Foundation

/// What you did to an AI edit by hand, carried into the next build of it (#116): your own text and
/// graphic clips, your markers, the notes, the caption look and the cover frame. The AI's own clips and
/// markers are rebuilt, so they're left behind.
public struct TimelineCarryOver: Codable, Hashable, Sendable {
    public var clips: [TimelineClip]
    public var markers: [Marker]
    public var notes: String
    public var captionStyle: CaptionStyle?
    public var captionsEnabled: Bool?
    public var coverTime: Seconds?

    public var isEmpty: Bool { clips.isEmpty && markers.isEmpty && notes.isEmpty && captionStyle == nil && coverTime == nil }

    /// Everything hand-made in `timeline`. Clips of `primaryAssetID` are the AI's cut and never carried.
    public static func capture(from timeline: Timeline, primaryAssetID: UUID?) -> TimelineCarryOver {
        var clips: [TimelineClip] = []
        for track in timeline.tracks {
            for clip in track.clips where !clip.aiGenerated {
                switch clip.content {
                case .media(let id):
                    if id != primaryAssetID { clips.append(clip) }
                case .text, .solid, .compound:
                    clips.append(clip)
                }
            }
        }
        return TimelineCarryOver(clips: clips, markers: timeline.markers.filter { !$0.aiGenerated }, notes: timeline.notes,
                                 captionStyle: timeline.captions?.style, captionsEnabled: timeline.captions?.isEnabled, coverTime: timeline.coverTime)
    }

    /// Puts the carried pieces onto `timeline`: clips land where they were (a free lane of their kind), later
    /// than the new end they're dropped; markers and notes come back, the caption look is restored.
    @discardableResult
    public func apply(to timeline: inout Timeline) -> Int {
        var placed = 0
        let end = timeline.duration
        for clip in clips where clip.start < end {
            let kind: TrackKind
            switch clip.content {
            case .text: kind = .text
            case .media(let id):
                kind = timeline.tracks.contains { t in t.kind == .audio && t.clips.contains { $0.assetID == id } } ? .audio : .video
            case .solid, .compound: kind = .video
            }
            var copy = clip
            copy.id = UUID()
            copy.linkGroup = nil
            let track = timeline.freeTrack(kind: kind, for: copy.timelineRange)
            if (try? timeline.insert(copy, onTrack: track, mode: .overwrite)) != nil { placed += 1 }
        }
        for marker in markers where marker.time <= end && !timeline.markers.contains(where: { abs($0.time - marker.time) < 0.05 }) {
            var copy = marker
            copy.id = UUID()
            timeline.markers.append(copy)
        }
        timeline.markers.sort { $0.time < $1.time }
        if !notes.isEmpty {
            timeline.notes = timeline.notes.isEmpty ? notes : notes + "\n\n" + timeline.notes
        }
        if let captionStyle { timeline.captions?.style = captionStyle }
        if let captionsEnabled { timeline.captions?.isEnabled = captionsEnabled }
        if let coverTime, coverTime <= end { timeline.coverTime = coverTime }
        return placed
    }
}
