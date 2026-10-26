import Foundation

/// The three trims every editor reaches for besides a plain trim (#143), all keeping the timeline's length:
/// slip moves the source window inside a clip, slide moves the clip between its neighbours, roll moves the
/// cut between two clips. Linked sound pieces follow.
extension Timeline {
    /// Slip: the clip stays where it is and as long as it is; what plays inside it moves by `delta`
    /// (positive = later source). Clamped to the start of the file and, when `mediaDuration` is known, its end.
    public mutating func slip(clipID: UUID, by delta: Seconds, mediaDuration: Seconds? = nil) throws {
        guard clip(id: clipID) != nil else { throw TimelineEditError.clipNotFound }
        var allowed = delta
        for id in linkedClipIDs(of: clipID) {
            guard let l = location(ofClip: id) else { continue }
            let c = tracks[l.trackIndex].clips[l.clipIndex]
            guard c.content.hasSourceTime else { continue }
            allowed = max(allowed, -c.sourceIn / c.speed)
            if let mediaDuration { allowed = min(allowed, (mediaDuration - c.sourceOut) / c.speed) }
        }
        guard abs(allowed) > TimeRange.epsilon else { return }
        for id in linkedClipIDs(of: clipID) {
            guard let l = location(ofClip: id), tracks[l.trackIndex].clips[l.clipIndex].content.hasSourceTime else { continue }
            if tracks[l.trackIndex].isLocked { throw TimelineEditError.trackLocked(tracks[l.trackIndex].name) }
            tracks[l.trackIndex].clips[l.clipIndex].sourceIn += allowed * tracks[l.trackIndex].clips[l.clipIndex].speed
        }
        touch()
    }

    /// Slide: the clip moves by `delta` and its neighbours give or take the room — the one before gets
    /// longer (or shorter) at its tail, the one after shorter (or longer) at its head — so nothing else moves.
    /// Clamped so neither neighbour drops under the minimum clip length. A side with no neighbour just moves.
    public mutating func slide(clipID: UUID, by delta: Seconds) throws {
        guard clip(id: clipID) != nil else { throw TimelineEditError.clipNotFound }
        var allowed = delta
        for id in linkedClipIDs(of: clipID) {
            guard let l = location(ofClip: id) else { continue }
            let clips = tracks[l.trackIndex].clips
            if l.clipIndex > 0 {
                let prev = clips[l.clipIndex - 1]
                allowed = max(allowed, -(prev.duration - Timeline.minimumClipDuration))
            } else {
                allowed = max(allowed, -clips[l.clipIndex].start)
            }
            if l.clipIndex + 1 < clips.count {
                let next = clips[l.clipIndex + 1]
                allowed = min(allowed, next.duration - Timeline.minimumClipDuration)
                if next.content.hasSourceTime { allowed = max(allowed, -next.sourceIn / next.speed) }
            }
        }
        guard abs(allowed) > TimeRange.epsilon else { return }
        for id in linkedClipIDs(of: clipID) {
            guard let l = location(ofClip: id) else { continue }
            if tracks[l.trackIndex].isLocked { throw TimelineEditError.trackLocked(tracks[l.trackIndex].name) }
            let i = l.clipIndex
            if i > 0 {
                let speed = tracks[l.trackIndex].clips[i - 1].speed
                tracks[l.trackIndex].clips[i - 1].sourceDuration += allowed * speed
            }
            tracks[l.trackIndex].clips[i].start += allowed
            if i + 1 < tracks[l.trackIndex].clips.count {
                let speed = tracks[l.trackIndex].clips[i + 1].speed
                if tracks[l.trackIndex].clips[i + 1].content.hasSourceTime { tracks[l.trackIndex].clips[i + 1].sourceIn += allowed * speed }
                tracks[l.trackIndex].clips[i + 1].sourceDuration -= allowed * speed
                tracks[l.trackIndex].clips[i + 1].start += allowed
            }
        }
        touch()
    }

    /// Roll: the cut after `clipID` moves by `delta`; this clip ends later (or earlier) and the next one
    /// starts later (or earlier) by the same amount, so the whole stays in place. Nothing happens without a
    /// clip right after this one on the same track.
    public mutating func roll(edgeAfter clipID: UUID, by delta: Seconds, mediaDuration: Seconds? = nil) throws {
        guard let l = location(ofClip: clipID) else { throw TimelineEditError.clipNotFound }
        let clips = tracks[l.trackIndex].clips
        guard l.clipIndex + 1 < clips.count else { return }
        let this = clips[l.clipIndex], next = clips[l.clipIndex + 1]
        guard abs(next.start - this.end) < 0.05 else { return }   // only a real cut, not a gap
        var allowed = delta.clamped(-(this.duration - Timeline.minimumClipDuration), next.duration - Timeline.minimumClipDuration)
        if let mediaDuration, this.content.hasSourceTime { allowed = min(allowed, (mediaDuration - this.sourceOut) / this.speed) }
        if next.content.hasSourceTime { allowed = max(allowed, -next.sourceIn / next.speed) }
        guard abs(allowed) > TimeRange.epsilon else { return }
        if allowed > 0 {
            try trimStart(clipID: next.id, to: next.start + allowed)
            try trimEnd(clipID: this.id, to: this.end + allowed, mediaDuration: mediaDuration)
        } else {
            try trimEnd(clipID: this.id, to: this.end + allowed, mediaDuration: mediaDuration)
            try trimStart(clipID: next.id, to: next.start + allowed)
        }
    }
}
