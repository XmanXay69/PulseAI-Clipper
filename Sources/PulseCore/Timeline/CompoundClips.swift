import Foundation

public enum CompoundError: Error, LocalizedError, Equatable {
    case nothingSelected
    case notCompound
    case missingNestedTimeline
    case wouldNestItself

    public var errorDescription: String? {
        switch self {
        case .nothingSelected: return "Select the clips to combine into a compound clip."
        case .notCompound: return "That clip isn't a compound clip."
        case .missingNestedTimeline: return "The compound clip's contents are missing from this project."
        case .wouldNestItself: return "A compound clip can't contain itself."
        }
    }
}

/// One clip of a nested timeline, mapped into its parent's time (and trimmed to the compound's window).
public struct FlattenedClip: Hashable, Sendable {
    public var trackIndex: Int
    public var trackKind: TrackKind
    public var trackName: String
    public var clip: TimelineClip
}

/// Compound clips: a group of clips collapsed into one clip whose content is a nested timeline.
/// The compound behaves like any clip (move, trim, fade, transform, color) and can be opened,
/// edited and broken apart again.
public enum CompoundEditor {
    public static let maximumDepth = 6

    /// Collapses `clipIDs` (plus linked partners) into a compound clip. Returns the nested timeline,
    /// which the caller stores in `ProjectDocument.compounds`; the parent now holds one compound clip.
    @discardableResult
    public static func makeCompound(in timeline: inout Timeline, clipIDs: [UUID], name: String) throws -> (nested: Timeline, clipID: UUID) {
        let ids = Set(clipIDs.flatMap { timeline.linkedClipIDs(of: $0) })
        let selected = timeline.allClips.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { throw CompoundError.nothingSelected }
        let span = TimeRange(start: selected.map(\.start).min()!, end: selected.map(\.end).max()!)

        // Nested timeline: same canvas, one track per parent track that had selected clips.
        var nested = Timeline(name: name, canvas: timeline.canvas)
        var hasVisual = false
        for track in timeline.tracks {
            let clips = track.clips.filter { ids.contains($0.id) }
            guard !clips.isEmpty else { continue }
            var copy = Track(kind: track.kind, name: track.name)
            copy.clips = clips.map { var c = $0; c.start -= span.start; return c }.sorted { $0.start < $1.start }
            nested.tracks.append(copy)
            if track.kind != .audio { hasVisual = true }
        }
        nested.notes = "Compound clip"

        // Parent: remove the clips, place the compound where the topmost selected visual clip was.
        let preferredTrack = timeline.tracks.last { t in t.kind != .audio && t.clips.contains { ids.contains($0.id) } }?.id
            ?? timeline.tracks.first { t in t.clips.contains { ids.contains($0.id) } }?.id
        for ti in timeline.tracks.indices {
            timeline.tracks[ti].clips.removeAll { ids.contains($0.id) }
        }
        let kind: TrackKind = hasVisual ? .video : .audio
        let preferredOfKind = preferredTrack.flatMap { id in timeline.tracks.first { $0.id == id && $0.kind == kind }?.id }
        let target = timeline.freeTrack(kind: kind, for: span, preferring: preferredOfKind)
        var compound = TimelineClip(name: name, content: .compound(timelineID: nested.id), start: span.start, sourceIn: 0, sourceDuration: span.duration)
        compound.transform.fit = .fill
        try timeline.insert(compound, onTrack: target)
        return (nested, compound.id)
    }

    /// The nested timeline's clips as they appear inside the compound clip, in the parent's time.
    public static func flatten(_ compound: TimelineClip, nested: Timeline) -> [FlattenedClip] {
        let window = compound.sourceRange
        let delta = compound.start - compound.sourceIn
        var out: [FlattenedClip] = []
        for (ti, track) in nested.tracks.enumerated() where !track.isHidden {
            for clip in track.clips where clip.isEnabled {
                let range = clip.timelineRange
                guard range.end > window.start + TimeRange.epsilon, range.start < window.end - TimeRange.epsilon else { continue }
                var c = clip
                // Trim to the compound's window (source time follows, respecting speed).
                if range.start < window.start {
                    let cut = window.start - range.start
                    c.start = window.start
                    c.sourceIn += cut * c.speed
                    c.sourceDuration -= cut * c.speed
                    c.transitionIn = nil
                    c.transform.retainKeyframes(in: TimeRange(start: cut, end: clip.duration), rebasingTo: cut)
                    c.styleKeyframes = c.styleKeyframes.retained(in: TimeRange(start: cut, end: clip.duration), rebasingTo: cut)
                }
                if c.end > window.end {
                    c.sourceDuration -= (c.end - window.end) * c.speed
                    c.transitionOut = nil
                }
                guard c.duration > Timeline.minimumClipDuration else { continue }
                c.start += delta
                if track.isMuted { c.audio.isMuted = true }
                out.append(FlattenedClip(trackIndex: ti, trackKind: track.kind, trackName: track.name, clip: c))
            }
        }
        return out
    }

    /// Replaces a compound clip with its contents (trimmed to what the compound showed).
    public static func breakApart(_ timeline: inout Timeline, clipID: UUID, nested: Timeline) throws {
        guard let compound = timeline.clip(id: clipID), compound.content.compoundID == nested.id else { throw CompoundError.notCompound }
        let pieces = flatten(compound, nested: nested)
        timeline.delete(clipIDs: [clipID], ripple: false, includeLinked: false)
        // Keep nested tracks together: each nested track goes to one parent track of the same kind.
        var trackFor: [Int: UUID] = [:]
        for index in Set(pieces.map(\.trackIndex)).sorted() {
            let group = pieces.filter { $0.trackIndex == index }
            guard let first = group.first else { continue }
            let span = TimeRange(start: group.map(\.clip.start).min()!, end: group.map(\.clip.end).max()!)
            let used = Set(trackFor.values)
            let free = timeline.tracks.first { t in
                t.kind == first.trackKind && !t.isLocked && !used.contains(t.id) && !t.clips.contains { $0.timelineRange.overlaps(span) }
            }?.id
            trackFor[index] = free ?? timeline.addTrack(kind: first.trackKind, name: first.trackName)
        }
        // Fresh link groups so broken-apart clips don't link to other copies of the nested timeline.
        var groups: [UUID: UUID] = [:]
        for piece in pieces {
            guard let trackID = trackFor[piece.trackIndex] else { continue }
            var c = piece.clip
            c.id = UUID()
            if let g = c.linkGroup {
                if groups[g] == nil { groups[g] = UUID() }
                c.linkGroup = groups[g]
            }
            try timeline.insert(c, onTrack: trackID)
        }
    }

    /// Nested timelines referenced (directly or deeply) by a timeline — used to refuse cycles.
    public static func referencedCompounds(of timeline: Timeline, in compounds: [UUID: Timeline], depth: Int = 0) -> Set<UUID> {
        guard depth < maximumDepth else { return [] }
        var ids = Set<UUID>()
        for clip in timeline.allClips {
            guard let id = clip.content.compoundID, !ids.contains(id) else { continue }
            ids.insert(id)
            if let nested = compounds[id] { ids.formUnion(referencedCompounds(of: nested, in: compounds, depth: depth + 1)) }
        }
        return ids
    }

    /// Length of the nested content (for trimming limits).
    public static func contentDuration(_ nested: Timeline) -> Seconds { nested.duration }
}
