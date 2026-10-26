import Foundation

extension Timeline {
    /// Appends another timeline after this one's end (#65): tracks match by kind and order, clips and link
    /// groups get fresh ids, caption words merge (they live in source time, so the clips place them), markers
    /// shift. The join is a cut.
    public mutating func append(_ other: Timeline, gap: Seconds = 0) {
        let offset = duration + gap
        var groupMap: [UUID: UUID] = [:]
        var seenOfKind: [TrackKind: Int] = [:]
        for track in other.tracks {
            let n = seenOfKind[track.kind, default: 0]
            seenOfKind[track.kind] = n + 1
            let mine = tracks.indices.filter { tracks[$0].kind == track.kind }
            let ti: Int
            if n < mine.count {
                ti = mine[n]
            } else {
                tracks.append(Track(kind: track.kind, name: track.name))
                ti = tracks.count - 1
            }
            for clip in track.clips {
                var moved = clip
                moved.id = UUID()
                moved.start += offset
                if let g = clip.linkGroup {
                    let fresh = groupMap[g] ?? UUID()
                    groupMap[g] = fresh
                    moved.linkGroup = fresh
                }
                tracks[ti].clips.append(moved)
            }
            tracks[ti].sortClips()
        }
        if let theirs = other.captions {
            if captions == nil {
                captions = theirs
            } else {
                var known = Set(captions!.words.map { "\($0.start)-\($0.end)-\($0.text)" })
                for w in theirs.words where !known.contains("\(w.start)-\(w.end)-\(w.text)") {
                    known.insert("\(w.start)-\(w.end)-\(w.text)")
                    captions!.words.append(w)
                }
                captions!.words.sort { $0.start < $1.start }
            }
        }
        for m in other.markers {
            var moved = m
            moved.id = UUID()
            moved.time += offset
            markers.append(moved)
        }
        removedSections += other.removedSections
        for change in other.layoutChanges {
            var moved = change
            moved.id = UUID()
            moved.time += offset
            layoutChanges.append(moved)
        }
        modifiedAt = Date()
    }
}

extension ClipCandidate {
    /// Two moments as one short (#65): the card keeps the first moment's range and payoff, carries the second
    /// as an extra range, and takes the best of both scores.
    public static func merged(_ a: ClipCandidate, _ b: ClipCandidate) -> ClipCandidate {
        let (first, second) = a.range.start <= b.range.start ? (a, b) : (b, a)
        var out = first
        out.id = UUID()
        out.extraRanges = (first.extraRanges ?? []) + [second.range] + (second.extraRanges ?? [])
        out.potential = max(first.potential, second.potential)
        out.basePotential = nil
        var tags = first.tags
        for t in second.tags where !tags.contains(t) { tags.append(t) }
        out.tags = tags
        out.transcriptSnippet = [first.transcriptSnippet, second.transcriptSnippet].filter { !$0.isEmpty }.joined(separator: " … ")
        out.status = .new
        out.timelineID = nil
        out.feedback = nil
        out.isFavorite = first.isFavorite || second.isFavorite
        out.createdAt = Date()
        out.userAdjusted = true
        return out
    }

    /// The length of the short with every merged moment.
    public var totalDuration: Seconds { range.duration + (extraRanges ?? []).reduce(0) { $0 + $1.duration } }

    public var isMerged: Bool { !(extraRanges ?? []).isEmpty }
}
