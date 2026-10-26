import Foundation

extension LongFormEditor {
    /// The best `count` shorts hiding in a YouTube edit (#69): one per story piece, cut around that piece's peak,
    /// 15–60 s, never two from the same stretch. Best first in the result? No — in stream order, like AI Clips.
    public static func shorts(from timeline: Timeline, analysis: MediaAnalysis, settings: ClipGenerationSettings, count: Int = 3) -> [ClipCandidate] {
        guard let track = timeline.tracks.first(where: { $0.kind == .video }) else { return [] }
        let hookEnd = timeline.markers.contains { $0.name == "Hook" } ? (track.clips.first?.end ?? 0) : 0
        let pieces = track.clips.filter {
            $0.content.assetID == analysis.assetID && $0.role != .graphic && $0.start >= hookEnd - 0.01 && $0.sourceDuration >= 12
        }
        guard !pieces.isEmpty else { return [] }
        let generator = ClipGenerator(input: ClipGenerationInput(analysis: analysis), settings: settings)
        let step = max(generator.signals.step, 0.05)
        var candidates: [ClipCandidate] = []
        for piece in pieces {
            let range = piece.sourceRange
            var peak = range.start + range.duration * 0.6
            var best: Float = -.infinity
            var t = range.start
            while t < range.end {
                let i = Int(t / step)
                if i < generator.signals.excitement.count, generator.signals.excitement[i] > best {
                    best = generator.signals.excitement[i]
                    peak = t
                }
                t += step
            }
            // More setup than aftermath around the peak, inside the piece.
            let length = min(max(15, settings.targetDuration), min(60, range.duration))
            let end = min(range.end, max(range.start + length, peak + length * 0.4))
            let start = max(range.start, end - length)
            candidates.append(generator.makeCandidate(range: TimeRange(start: start, end: end), payoff: min(max(peak, start), end)))
        }
        var picked: [ClipCandidate] = []
        for c in candidates.sorted(by: { $0.potential > $1.potential }) where !picked.contains(where: { $0.range.overlaps(c.range) }) {
            picked.append(c)
            if picked.count >= count { break }
        }
        return picked.sorted { $0.range.start < $1.range.start }
    }
}

extension EditPolish {
    /// A speed ramp on the payoff (#80): the piece before it at `slow` and the piece after at `fast`, linked
    /// audio following. Returns false when the payoff isn't inside a main-asset clip with room on both sides.
    @discardableResult
    public static func speedRamp(_ timeline: inout Timeline, assetID: UUID, payoffAtSource payoff: Seconds, before: Seconds = 1.2, after: Seconds = 0.8,
                                 slow: Double = 0.9, fast: Double = 1.1) -> Bool {
        guard let vi = timeline.tracks.firstIndex(where: { $0.kind == .video }),
              let clip = timeline.tracks[vi].clips.first(where: {
                  $0.content.assetID == assetID && $0.role != .graphic && abs($0.speed - 1) < 1e-6 &&
                      $0.sourceIn + before + 0.3 <= payoff && $0.sourceOut - after - 0.3 >= payoff
              }) else { return false }
        let t0 = clip.timelineTime(atSource: payoff - before), t1 = clip.timelineTime(atSource: payoff), t2 = clip.timelineTime(atSource: payoff + after)
        do {
            _ = try timeline.split(at: t2, clipIDs: [clip.id])
            let afterPieces = try timeline.split(at: t1, clipIDs: [clip.id])
            let beforePieces = try timeline.split(at: t0, clipIDs: [clip.id])
            if let piece = beforePieces.first { try timeline.setSpeed(clipID: piece, speed: slow) }
            if let piece = afterPieces.first { try timeline.setSpeed(clipID: piece, speed: fast) }
            for id in beforePieces + afterPieces {
                if let l = timeline.location(ofClip: id) { timeline.tracks[l.trackIndex].clips[l.clipIndex].name = "Ramp" }
            }
            return true
        } catch {
            return false
        }
    }

    /// Plays 1.2–4 s pauses at `speed` instead of cutting them (#96): the breath stays, the wait goes. Splits the
    /// main video clip around each pause (its linked audio follows) and ripples what comes after on those
    /// tracks, so it belongs early in an AI build, before overlays and music are placed. Returns the count.
    @discardableResult
    public static func shortenPauses(_ timeline: inout Timeline, words: [TranscriptWord], after: Seconds,
                                     minimum: Seconds = 1.2, maximum: Seconds = 4, speed: Double = 1.6) -> Int {
        guard words.count > 1, speed > 1, let vi = timeline.tracks.firstIndex(where: { $0.kind == .video }) else { return 0 }
        let margin: Seconds = 0.15
        var pauses: [TimeRange] = []
        for (a, b) in zip(words, words.dropFirst()) where b.start - a.end >= minimum && b.start - a.end <= maximum {
            pauses.append(TimeRange(start: a.end + margin, end: b.start - margin))
        }
        var count = 0
        for pause in pauses {
            guard let clip = timeline.tracks[vi].clips.first(where: {
                $0.content.assetID != nil && $0.role != .graphic && abs($0.speed - 1) < 1e-6 && $0.start >= after - 0.01 &&
                    $0.sourceIn + 0.3 <= pause.start && $0.sourceOut - 0.3 >= pause.end
            }) else { continue }
            let t1 = clip.timelineTime(atSource: pause.start), t2 = clip.timelineTime(atSource: pause.end)
            guard t2 - t1 >= Timeline.minimumClipDuration * 2 else { continue }
            do {
                _ = try timeline.split(at: t2, clipIDs: [clip.id])          // the clip keeps its id on the left: [start, t2)
                let middle = try timeline.split(at: t1, clipIDs: [clip.id]) // the new right pieces: [t1, t2) on each linked track
                guard let piece = middle.first else { continue }
                try timeline.setSpeed(clipID: piece, speed: speed)
                for id in middle {
                    if let l = timeline.location(ofClip: id) { timeline.tracks[l.trackIndex].clips[l.clipIndex].name = "Pause" }
                }
                count += 1
            } catch {
                continue
            }
        }
        return count
    }
}
