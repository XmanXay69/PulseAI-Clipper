import Foundation

public enum TimelineEditError: Error, Equatable, LocalizedError {
    case clipNotFound
    case trackNotFound
    case trackLocked(String)
    case incompatibleTrack(clip: String, track: String)
    case timeOutsideClip
    case wouldBeEmpty
    case nothingToRestore

    public var errorDescription: String? {
        switch self {
        case .clipNotFound: return "The clip no longer exists on the timeline."
        case .trackNotFound: return "The track no longer exists."
        case .trackLocked(let name): return "Track \(name) is locked. Unlock it to edit its clips."
        case .incompatibleTrack(let clip, let track): return "\(clip) can't be placed on \(track)."
        case .timeOutsideClip: return "The playhead isn't over the selected clip."
        case .wouldBeEmpty: return "That edit would leave a clip with no duration."
        case .nothingToRestore: return "PULSE couldn't find where to put that section back. Try Undo instead."
        }
    }
}

public enum InsertMode: String, Codable, Sendable {
    /// Replaces whatever is under the new clip.
    case overwrite
    /// Pushes later clips to the right.
    case insert
}

/// Location of a clip inside a timeline.
public struct ClipLocation: Hashable, Sendable {
    public var trackIndex: Int
    public var clipIndex: Int
}

/// All timeline edit operations. They are pure value mutations so the History system can
/// snapshot before/after, and every operation is unit tested.
extension Timeline {
    /// Shortest clip the editor allows (≈ one frame at 120 fps).
    public static let minimumClipDuration: Seconds = 1.0 / 120.0

    // MARK: Lookup

    public func location(ofClip id: UUID) -> ClipLocation? {
        for (ti, track) in tracks.enumerated() {
            if let ci = track.clips.firstIndex(where: { $0.id == id }) {
                return ClipLocation(trackIndex: ti, clipIndex: ci)
            }
        }
        return nil
    }

    public func clip(id: UUID) -> TimelineClip? {
        guard let loc = location(ofClip: id) else { return nil }
        return tracks[loc.trackIndex].clips[loc.clipIndex]
    }

    public func trackIndex(id: UUID) -> Int? {
        tracks.firstIndex { $0.id == id }
    }

    public func track(containingClip id: UUID) -> Track? {
        guard let loc = location(ofClip: id) else { return nil }
        return tracks[loc.trackIndex]
    }

    /// The clip plus every clip linked to it.
    public func linkedClipIDs(of id: UUID) -> [UUID] {
        guard let clip = clip(id: id) else { return [] }
        guard let group = clip.linkGroup else { return [id] }
        return allClips.filter { $0.linkGroup == group }.map(\.id)
    }

    /// Clips intersecting a timeline time, top-most video layer last.
    public func clips(at time: Seconds) -> [(track: Track, clip: TimelineClip)] {
        var result: [(Track, TimelineClip)] = []
        for track in tracks {
            for clip in track.clips where clip.timelineRange.contains(time) {
                result.append((track, clip))
            }
        }
        return result
    }

    // MARK: Tracks

    @discardableResult
    public mutating func addTrack(kind: TrackKind, name: String? = nil) -> UUID {
        let count = tracks.filter { $0.kind == kind }.count
        let track = Track(kind: kind, name: name ?? "\(kind.shortPrefix)\(count + 1)")
        // Keep tracks grouped: video, text, audio.
        let order: [TrackKind: Int] = [.video: 0, .text: 1, .audio: 2]
        let insertIndex = tracks.lastIndex { (order[$0.kind] ?? 0) <= (order[kind] ?? 0) }.map { $0 + 1 } ?? tracks.count
        tracks.insert(track, at: insertIndex)
        return track.id
    }

    public mutating func removeTrack(id: UUID) {
        tracks.removeAll { $0.id == id }
    }

    /// Returns the id of the first track of `kind` whose range is free, creating one if needed.
    public mutating func freeTrack(kind: TrackKind, for range: TimeRange, preferring preferred: UUID? = nil) -> UUID {
        func isFree(_ track: Track) -> Bool {
            !track.isLocked && !track.clips.contains { $0.timelineRange.overlaps(range) }
        }
        if let preferred, let idx = trackIndex(id: preferred), tracks[idx].kind == kind, isFree(tracks[idx]) {
            return preferred
        }
        if let track = tracks.first(where: { $0.kind == kind && isFree($0) }) {
            return track.id
        }
        return addTrack(kind: kind)
    }

    // MARK: Insert

    /// Places a clip on a track. Overwrite clears the destination range; insert ripples later clips.
    public mutating func insert(_ clip: TimelineClip, onTrack trackID: UUID, mode: InsertMode = .overwrite) throws {
        guard let ti = trackIndex(id: trackID) else { throw TimelineEditError.trackNotFound }
        guard !tracks[ti].isLocked else { throw TimelineEditError.trackLocked(tracks[ti].name) }
        guard tracks[ti].kind.accepts(clip.content) else {
            throw TimelineEditError.incompatibleTrack(clip: clip.name, track: tracks[ti].name)
        }
        guard clip.duration >= Timeline.minimumClipDuration else { throw TimelineEditError.wouldBeEmpty }
        var placed = clip
        placed.start = max(0, clip.start)
        switch mode {
        case .overwrite:
            clearRange(placed.timelineRange, trackIndex: ti)
        case .insert:
            splitTrack(ti, at: placed.start)
            for ci in tracks[ti].clips.indices where tracks[ti].clips[ci].start >= placed.start - TimeRange.epsilon {
                tracks[ti].clips[ci].start += placed.duration
            }
        }
        tracks[ti].clips.append(placed)
        tracks[ti].sortClips()
        touch()
    }

    /// Removes everything in `range` on a track, trimming/splitting clips that straddle it.
    mutating func clearRange(_ range: TimeRange, trackIndex ti: Int) {
        splitTrack(ti, at: range.start)
        splitTrack(ti, at: range.end)
        tracks[ti].clips.removeAll { range.contains(TimeRange(start: $0.start, end: $0.end)) || (range.overlaps($0.timelineRange) && range.contains($0.timelineRange.midpoint)) }
    }

    /// Splits any clip on the track that strictly contains `time`.
    mutating func splitTrack(_ ti: Int, at time: Seconds) {
        guard let ci = tracks[ti].clips.firstIndex(where: { $0.start < time - Timeline.minimumClipDuration / 2 && $0.end > time + Timeline.minimumClipDuration / 2 }) else { return }
        let original = tracks[ti].clips[ci]
        let (left, right) = Timeline.splitClip(original, at: time, rightLinkGroup: original.linkGroup)
        tracks[ti].clips[ci] = left
        tracks[ti].clips.insert(right, at: ci + 1)
    }

    /// Pure split of a single clip at timeline time `time`.
    static func splitClip(_ clip: TimelineClip, at time: Seconds, rightLinkGroup: UUID?) -> (TimelineClip, TimelineClip) {
        var left = clip
        var right = clip
        right.id = UUID()
        right.linkGroup = rightLinkGroup
        let local = time - clip.start
        let sourceOffset = local * clip.speed
        left.sourceDuration = sourceOffset
        left.transitionOut = nil
        right.start = time
        if clip.content.assetID != nil {
            right.sourceIn = clip.sourceIn + sourceOffset
        } else {
            // Generated content (text/solid) has no real source time; keep sourceIn 0-based.
            right.sourceIn = clip.sourceIn + sourceOffset
        }
        right.sourceDuration = clip.sourceDuration - sourceOffset
        right.transitionIn = nil
        // Keyframes stay locked to content.
        left.transform.retainKeyframes(in: TimeRange(start: 0, end: local), rebasingTo: 0)
        right.transform.retainKeyframes(in: TimeRange(start: local, end: clip.duration), rebasingTo: local)
        left.audio.volume.retainKeyframes(in: TimeRange(start: 0, end: local), rebasingTo: 0)
        right.audio.volume.retainKeyframes(in: TimeRange(start: local, end: clip.duration), rebasingTo: local)
        left.audio.fadeOut = 0
        right.audio.fadeIn = 0
        return (left, right)
    }

    // MARK: Split (blade)

    /// Blades the given clips (and their linked partners) at `time`. When `clipIDs` is nil,
    /// every unlocked track is cut at `time`. Returns ids of the new right-hand clips.
    @discardableResult
    public mutating func split(at time: Seconds, clipIDs: [UUID]? = nil) throws -> [UUID] {
        var targets: Set<UUID>
        if let clipIDs {
            targets = Set(clipIDs.flatMap { linkedClipIDs(of: $0) })
        } else {
            targets = Set(tracks.filter { !$0.isLocked }.flatMap { $0.clips.map(\.id) })
        }
        var newGroups: [UUID: UUID] = [:]
        var created: [UUID] = []
        for ti in tracks.indices where !tracks[ti].isLocked {
            guard let ci = tracks[ti].clips.firstIndex(where: {
                targets.contains($0.id) && $0.start < time - Timeline.minimumClipDuration / 2 && $0.end > time + Timeline.minimumClipDuration / 2
            }) else { continue }
            let original = tracks[ti].clips[ci]
            var rightGroup: UUID?
            if let g = original.linkGroup {
                if let existing = newGroups[g] { rightGroup = existing } else {
                    let fresh = UUID()
                    newGroups[g] = fresh
                    rightGroup = fresh
                }
            }
            let (left, right) = Timeline.splitClip(original, at: time, rightLinkGroup: rightGroup)
            tracks[ti].clips[ci] = left
            tracks[ti].clips.insert(right, at: ci + 1)
            created.append(right.id)
        }
        if clipIDs != nil && created.isEmpty { throw TimelineEditError.timeOutsideClip }
        touch()
        return created
    }

    // MARK: Delete

    /// Deletes clips (with linked partners unless `includeLinked` is false).
    /// With `ripple`, later clips on affected tracks shift left to close the gap.
    public mutating func delete(clipIDs: [UUID], ripple: Bool, includeLinked: Bool = true) {
        let ids = Set(includeLinked ? clipIDs.flatMap { linkedClipIDs(of: $0) } : clipIDs)
        guard !ids.isEmpty else { return }
        if ripple {
            // Collect removed timeline ranges per track, then ripple each track from right to left.
            for ti in tracks.indices where !tracks[ti].isLocked {
                let removed = tracks[ti].clips.filter { ids.contains($0.id) }.map(\.timelineRange)
                guard !removed.isEmpty else { continue }
                tracks[ti].clips.removeAll { ids.contains($0.id) }
                for range in removed.merged().reversed() {
                    for ci in tracks[ti].clips.indices where tracks[ti].clips[ci].start >= range.end - TimeRange.epsilon {
                        tracks[ti].clips[ci].start -= range.duration
                    }
                }
            }
        } else {
            for ti in tracks.indices where !tracks[ti].isLocked {
                tracks[ti].clips.removeAll { ids.contains($0.id) }
            }
        }
        touch()
    }

    /// Removes `range` from the given tracks (all unlocked tracks when nil) and closes the gap.
    public mutating func rippleDelete(range: TimeRange, trackIDs: Set<UUID>? = nil) {
        guard !range.isEmpty else { return }
        for ti in tracks.indices where !tracks[ti].isLocked {
            if let trackIDs, !trackIDs.contains(tracks[ti].id) { continue }
            clearRange(range, trackIndex: ti)
            for ci in tracks[ti].clips.indices where tracks[ti].clips[ci].start >= range.end - TimeRange.epsilon {
                tracks[ti].clips[ci].start -= range.duration
            }
            tracks[ti].sortClips()
        }
        for i in markers.indices where markers[i].time >= range.end {
            markers[i].time -= range.duration
        }
        markers.removeAll { range.contains($0.time) && $0.time > range.start + TimeRange.epsilon }
        relinkSplitSegments()
        touch()
    }

    /// After a range is cut out of linked clips, the pieces on either side of the cut still share the
    /// original link group. Give each time-aligned set of pieces its own group so moving one segment
    /// doesn't drag the others along.
    mutating func relinkSplitSegments() {
        var groups: [UUID: [(Int, Int)]] = [:]
        for ti in tracks.indices {
            for ci in tracks[ti].clips.indices {
                if let g = tracks[ti].clips[ci].linkGroup { groups[g, default: []].append((ti, ci)) }
            }
        }
        for (_, members) in groups {
            var keys: [Int] = []
            for member in members {
                keys.append(Int((tracks[member.0].clips[member.1].start * 1000).rounded()))
            }
            guard Set(keys).count > 1 else { continue }
            var newGroupForStart: [Int: UUID] = [:]
            for (member, k) in zip(members, keys) {
                let group = newGroupForStart[k] ?? UUID()
                newGroupForStart[k] = group
                tracks[member.0].clips[member.1].linkGroup = group
            }
        }
    }

    /// Closes every gap on a track (magnetic timeline behaviour).
    public mutating func closeGaps(trackID: UUID) {
        guard let ti = trackIndex(id: trackID), !tracks[ti].isLocked else { return }
        var cursor: Seconds = 0
        for ci in tracks[ti].clips.indices {
            tracks[ti].clips[ci].start = cursor
            cursor += tracks[ti].clips[ci].duration
        }
        touch()
    }

    // MARK: Move

    /// Moves a clip (and linked partners by the same delta) to `newStart`, optionally changing
    /// the primary clip's track. Destination ranges are overwritten.
    public mutating func move(clipID: UUID, toStart newStart: Seconds, toTrack destinationTrackID: UUID? = nil) throws {
        guard let loc = location(ofClip: clipID) else { throw TimelineEditError.clipNotFound }
        let primary = tracks[loc.trackIndex].clips[loc.clipIndex]
        let delta = max(newStart, 0) - primary.start
        let group = linkedClipIDs(of: clipID)
        // Linked clips can't move before 0 either.
        let minStart = group.compactMap { clip(id: $0)?.start }.min() ?? 0
        let appliedDelta = max(delta, -minStart)

        var moving: [(clip: TimelineClip, trackIndex: Int)] = []
        for id in group {
            guard let l = location(ofClip: id) else { continue }
            if tracks[l.trackIndex].isLocked { throw TimelineEditError.trackLocked(tracks[l.trackIndex].name) }
            moving.append((tracks[l.trackIndex].clips[l.clipIndex], l.trackIndex))
        }
        var destinationIndexForPrimary = loc.trackIndex
        if let destinationTrackID {
            guard let di = trackIndex(id: destinationTrackID) else { throw TimelineEditError.trackNotFound }
            guard !tracks[di].isLocked else { throw TimelineEditError.trackLocked(tracks[di].name) }
            guard tracks[di].kind.accepts(primary.content) else {
                throw TimelineEditError.incompatibleTrack(clip: primary.name, track: tracks[di].name)
            }
            destinationIndexForPrimary = di
        }
        // Remove all moving clips first so they don't clear each other.
        let movingIDs = Set(moving.map(\.clip.id))
        for ti in tracks.indices {
            tracks[ti].clips.removeAll { movingIDs.contains($0.id) }
        }
        for item in moving {
            var c = item.clip
            c.start += appliedDelta
            let ti = c.id == clipID ? destinationIndexForPrimary : item.trackIndex
            clearRange(c.timelineRange, trackIndex: ti)
            tracks[ti].clips.append(c)
            tracks[ti].sortClips()
        }
        touch()
    }

    // MARK: Trim

    /// Trims the head of a clip (and linked partners) so it starts at `newStart`.
    /// `mediaDuration` bounds how far the source can extend.
    public mutating func trimStart(clipID: UUID, to newStart: Seconds, ripple: Bool = false) throws {
        guard let primary = clip(id: clipID) else { throw TimelineEditError.clipNotFound }
        var delta = newStart - primary.start
        // Compute the allowed delta across all linked clips.
        for id in linkedClipIDs(of: clipID) {
            guard let l = location(ofClip: id) else { continue }
            let c = tracks[l.trackIndex].clips[l.clipIndex]
            let previousEnd = l.clipIndex > 0 ? tracks[l.trackIndex].clips[l.clipIndex - 1].end : 0
            let minDelta: Seconds
            if c.content.hasSourceTime {
                // Can't reveal source before 0.
                minDelta = max(-c.sourceIn / c.speed, previousEnd - c.start)
            } else {
                minDelta = previousEnd - c.start
            }
            let maxDelta = c.duration - Timeline.minimumClipDuration
            delta = delta.clamped(ripple ? -c.sourceIn / c.speed : minDelta, maxDelta)
        }
        guard abs(delta) > TimeRange.epsilon else { return }
        for id in linkedClipIDs(of: clipID) {
            guard let l = location(ofClip: id) else { continue }
            if tracks[l.trackIndex].isLocked { throw TimelineEditError.trackLocked(tracks[l.trackIndex].name) }
            var c = tracks[l.trackIndex].clips[l.clipIndex]
            c.sourceIn += delta * c.speed
            c.sourceDuration -= delta * c.speed
            c.transform.shiftKeyframes(by: -delta)
            c.audio.volume.shiftKeyframes(by: -delta)
            if ripple {
                // Head ripple: clip stays at its start, later clips shift by -delta.
                tracks[l.trackIndex].clips[l.clipIndex] = c
                for ci in tracks[l.trackIndex].clips.indices where ci > l.clipIndex {
                    tracks[l.trackIndex].clips[ci].start -= delta
                }
            } else {
                c.start += delta
                tracks[l.trackIndex].clips[l.clipIndex] = c
            }
        }
        touch()
    }

    /// Trims the tail of a clip (and linked partners) so it ends at `newEnd`.
    public mutating func trimEnd(clipID: UUID, to newEnd: Seconds, mediaDuration: Seconds? = nil, ripple: Bool = false) throws {
        guard let primary = clip(id: clipID) else { throw TimelineEditError.clipNotFound }
        var delta = newEnd - primary.end
        for id in linkedClipIDs(of: clipID) {
            guard let l = location(ofClip: id) else { continue }
            let c = tracks[l.trackIndex].clips[l.clipIndex]
            let nextStart = l.clipIndex + 1 < tracks[l.trackIndex].clips.count ? tracks[l.trackIndex].clips[l.clipIndex + 1].start : .infinity
            var maxDelta = ripple ? .infinity : nextStart - c.end
            if c.content.hasSourceTime, let mediaDuration {
                maxDelta = min(maxDelta, (mediaDuration - c.sourceOut) / c.speed)
            }
            let minDelta = -(c.duration - Timeline.minimumClipDuration)
            delta = delta.clamped(minDelta, maxDelta)
        }
        guard abs(delta) > TimeRange.epsilon else { return }
        for id in linkedClipIDs(of: clipID) {
            guard let l = location(ofClip: id) else { continue }
            if tracks[l.trackIndex].isLocked { throw TimelineEditError.trackLocked(tracks[l.trackIndex].name) }
            tracks[l.trackIndex].clips[l.clipIndex].sourceDuration += delta * tracks[l.trackIndex].clips[l.clipIndex].speed
            if ripple {
                for ci in tracks[l.trackIndex].clips.indices where ci > l.clipIndex {
                    tracks[l.trackIndex].clips[ci].start += delta
                }
            }
        }
        touch()
    }

    // MARK: Speed

    /// Changes playback speed; the clip keeps its start and later clips ripple to make room/close gaps.
    public mutating func setSpeed(clipID: UUID, speed newSpeed: Double) throws {
        let speed = newSpeed.clamped(0.1, 16)
        for id in linkedClipIDs(of: clipID) {
            guard let l = location(ofClip: id) else { continue }
            if tracks[l.trackIndex].isLocked { throw TimelineEditError.trackLocked(tracks[l.trackIndex].name) }
            let oldDuration = tracks[l.trackIndex].clips[l.clipIndex].duration
            tracks[l.trackIndex].clips[l.clipIndex].speed = speed
            let newDuration = tracks[l.trackIndex].clips[l.clipIndex].duration
            let ratio = oldDuration > 0 ? newDuration / oldDuration : 1
            // Rescale keyframe times so animation keeps its relative timing.
            var c = tracks[l.trackIndex].clips[l.clipIndex]
            c.transform = Timeline.rescaleKeyframes(c.transform, by: ratio)
            tracks[l.trackIndex].clips[l.clipIndex] = c
            let delta = newDuration - oldDuration
            for ci in tracks[l.trackIndex].clips.indices where ci > l.clipIndex {
                tracks[l.trackIndex].clips[ci].start += delta
            }
        }
        touch()
    }

    static func rescaleKeyframes(_ transform: VisualTransform, by ratio: Double) -> VisualTransform {
        guard ratio != 1 else { return transform }
        func rescale(_ a: AnimatedDouble) -> AnimatedDouble {
            guard a.isAnimated else { return a }
            let frames = a.keyframes.map { k -> ValueKeyframe in
                var k = k
                k.time *= ratio
                return k
            }
            return AnimatedDouble(a.value, keyframes: frames)
        }
        var t = transform
        t.positionX = rescale(t.positionX)
        t.positionY = rescale(t.positionY)
        t.scale = rescale(t.scale)
        t.rotation = rescale(t.rotation)
        t.opacity = rescale(t.opacity)
        t.zoom = rescale(t.zoom)
        t.panX = rescale(t.panX)
        t.panY = rescale(t.panY)
        return t
    }

    // MARK: Duplicate / link

    /// Duplicates clips (and linked partners) to right after the group's end.
    @discardableResult
    public mutating func duplicate(clipIDs: [UUID]) throws -> [UUID] {
        let ids = Array(Set(clipIDs.flatMap { linkedClipIDs(of: $0) }))
        let clips = ids.compactMap { id -> (TimelineClip, Int)? in
            guard let l = location(ofClip: id) else { return nil }
            return (tracks[l.trackIndex].clips[l.clipIndex], l.trackIndex)
        }
        guard let groupStart = clips.map(\.0.start).min(), let groupEnd = clips.map(\.0.end).max() else {
            throw TimelineEditError.clipNotFound
        }
        let offset = groupEnd - groupStart
        var groupMap: [UUID: UUID] = [:]
        var created: [UUID] = []
        for (clip, ti) in clips {
            var copy = clip
            copy.id = UUID()
            copy.start += offset
            if let g = clip.linkGroup {
                if groupMap[g] == nil { groupMap[g] = UUID() }
                copy.linkGroup = groupMap[g]
            }
            try insert(copy, onTrack: tracks[ti].id, mode: .overwrite)
            created.append(copy.id)
        }
        return created
    }

    /// Unlinks audio from video (Detach Audio).
    public mutating func unlink(clipID: UUID) {
        for id in linkedClipIDs(of: clipID) {
            guard let l = location(ofClip: id) else { continue }
            tracks[l.trackIndex].clips[l.clipIndex].linkGroup = nil
        }
        touch()
    }

    public mutating func link(clipIDs: [UUID]) {
        let group = UUID()
        for id in clipIDs {
            guard let l = location(ofClip: id) else { continue }
            tracks[l.trackIndex].clips[l.clipIndex].linkGroup = group
        }
        touch()
    }

    /// Applies a mutation to a single clip in place.
    public mutating func updateClip(id: UUID, _ body: (inout TimelineClip) -> Void) {
        guard let l = location(ofClip: id) else { return }
        body(&tracks[l.trackIndex].clips[l.clipIndex])
        tracks[l.trackIndex].sortClips()
        touch()
    }

    // MARK: Snapping

    /// Edit points used for snapping: clip edges, markers and timeline start.
    public func snapPoints(excluding excluded: Set<UUID> = []) -> [Seconds] {
        var points: Set<Double> = [0]
        for clip in allClips where !excluded.contains(clip.id) {
            points.insert(clip.start)
            points.insert(clip.end)
        }
        for marker in markers { points.insert(marker.time) }
        return points.sorted()
    }

    /// Snaps `time` to the nearest point within `tolerance`.
    public static func snap(_ time: Seconds, to points: [Seconds], tolerance: Seconds) -> Seconds {
        var best = time
        var bestDistance = tolerance
        for p in points {
            let d = abs(p - time)
            if d <= bestDistance {
                best = p
                bestDistance = d
            }
        }
        return best
    }

    /// Quantizes to the canvas frame grid.
    public func frameAligned(_ time: Seconds) -> Seconds {
        let fd = canvas.frameDuration
        return (time / fd).rounded() * fd
    }

    // MARK: Source-range editing (text-based editing, silence & filler removal)

    /// Timeline ranges where `assetID` source time `sourceRange` is visible, per track.
    public func timelineRanges(forSource sourceRange: TimeRange, assetID: UUID) -> [TimeRange] {
        var result: [TimeRange] = []
        for track in tracks {
            for clip in track.clips where clip.assetID == assetID {
                guard let overlap = clip.sourceRange.intersection(sourceRange) else { continue }
                result.append(TimeRange(start: clip.timelineTime(atSource: overlap.start), end: clip.timelineTime(atSource: overlap.end)))
            }
        }
        return result.merged()
    }

    /// Removes source ranges of an asset from every track that shows it, rippling the gap closed
    /// on those tracks. Returns the total timeline duration removed.
    @discardableResult
    public mutating func removeSourceRanges(_ sourceRanges: [TimeRange], assetID: UUID, reason: RemovedSection.Reason,
                                            texts: [String?]? = nil, aiGenerated: Bool = false) -> Seconds {
        // Tracks holding the asset, plus tracks with clips linked to it (a separate facecam or mic
        // recording of the same moment) so everything stays in sync.
        let linkedGroups = Set(tracks.flatMap(\.clips).filter { $0.assetID == assetID }.compactMap(\.linkGroup))
        let affectedTracks = Set(tracks.filter { t in
            !t.isLocked && t.clips.contains { $0.assetID == assetID || ($0.linkGroup.map(linkedGroups.contains) ?? false) }
        }.map(\.id))
        guard !affectedTracks.isEmpty else { return 0 }
        var timelineCuts: [TimeRange] = []
        for range in sourceRanges.merged() {
            timelineCuts.append(contentsOf: timelineRanges(forSource: range, assetID: assetID))
        }
        let cuts = timelineCuts.merged()
        var removed: Seconds = 0
        for cut in cuts.reversed() {
            rippleDelete(range: cut, trackIDs: affectedTracks)
            removed += cut.duration
        }
        for (i, range) in sourceRanges.enumerated() {
            let text = texts.flatMap { i < $0.count ? $0[i] : nil }
            removedSections.append(RemovedSection(assetID: assetID, sourceRange: range, reason: reason, text: text, aiGenerated: aiGenerated))
        }
        touch()
        return removed
    }

    /// Puts a previously removed section back where it belongs.
    public mutating func restore(removedSectionID id: UUID) throws {
        guard let sectionIndex = removedSections.firstIndex(where: { $0.id == id }) else { throw TimelineEditError.nothingToRestore }
        let section = removedSections[sectionIndex]
        let range = section.sourceRange
        let tolerance: Seconds = 0.02
        // Find, on each track, the clip that ends where the removed section began.
        var anchors: [(trackIndex: Int, clipIndex: Int)] = []
        for ti in tracks.indices where !tracks[ti].isLocked {
            if let ci = tracks[ti].clips.firstIndex(where: { $0.assetID == section.assetID && abs($0.sourceOut - range.start) <= tolerance }) {
                anchors.append((ti, ci))
            } else if let ci = tracks[ti].clips.firstIndex(where: { $0.assetID == section.assetID && abs($0.sourceIn - range.end) <= tolerance }) {
                anchors.append((ti, -(ci + 1))) // negative marks "insert before"
            }
        }
        guard !anchors.isEmpty else { throw TimelineEditError.nothingToRestore }
        for (ti, rawIndex) in anchors {
            let insertBefore = rawIndex < 0
            let ci = insertBefore ? -(rawIndex + 1) : rawIndex
            let anchor = tracks[ti].clips[ci]
            let gap = range.duration / anchor.speed
            let position = insertBefore ? anchor.start : anchor.end
            for k in tracks[ti].clips.indices where tracks[ti].clips[k].start >= position - TimeRange.epsilon && k != (insertBefore ? -1 : ci) {
                tracks[ti].clips[k].start += gap
            }
            if insertBefore {
                // Extend the following clip's head back over the restored range.
                tracks[ti].clips[ci].start = position
                tracks[ti].clips[ci].sourceIn = range.start
                tracks[ti].clips[ci].sourceDuration += range.duration
                tracks[ti].clips[ci].transform.shiftKeyframes(by: gap)
            } else {
                tracks[ti].clips[ci].sourceDuration += range.duration
                // If the next clip continues the source right after, merge it back in.
                if ci + 1 < tracks[ti].clips.count {
                    let next = tracks[ti].clips[ci + 1]
                    let cur = tracks[ti].clips[ci]
                    if next.assetID == cur.assetID, abs(next.sourceIn - cur.sourceOut) <= tolerance,
                       abs(next.start - cur.end) <= tolerance, next.speed == cur.speed,
                       next.transform.crop == cur.transform.crop, !next.transform.hasKeyframes, !cur.transform.hasKeyframes {
                        tracks[ti].clips[ci].sourceDuration += next.sourceDuration
                        tracks[ti].clips[ci].transitionOut = next.transitionOut
                        tracks[ti].clips.remove(at: ci + 1)
                    }
                }
            }
            tracks[ti].sortClips()
        }
        removedSections.remove(at: sectionIndex)
        touch()
    }

    mutating func touch() {
        modifiedAt = Date()
    }
}
