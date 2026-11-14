import Foundation

/// One of the passes Edit My VOD makes over a cut, that can be made again on its own (#1101).
public enum EditPass: String, CaseIterable, Sendable {
    case zooms, popUps, soundEffects, captionLook, tease

    public var displayName: String {
        switch self {
        case .zooms: return "Zooms"
        case .popUps: return "Pop-ups"
        case .soundEffects: return "Sound Effects"
        case .captionLook: return "Caption Look"
        case .tease: return "Tease"
        }
    }

    public var symbolName: String {
        switch self {
        case .zooms: return "plus.magnifyingglass"
        case .popUps: return "face.smiling"
        case .soundEffects: return "speaker.wave.2"
        case .captionLook: return "captions.bubble"
        case .tease: return "hourglass"
        }
    }
}

/// Makes one pass of an edit again with new settings and leaves the rest of the edit alone (#1101): change
/// the editing style or how much editing you want, and only the zooms (or only the pop-ups, the sound
/// effects, the caption look, the tease) are redone. The cut, your own trims, your own text and everything
/// from the other passes stay.
///
/// It works by building the recording afresh from the moments the edit still holds, then carrying that one
/// pass across by where each item sits in the recording, not by where it sits on the timeline. So an edit
/// that was trimmed, reordered or shortened by hand still gets its new zooms in the right places, and an
/// item whose moment is no longer in the edit is simply not carried over.
public enum EditRebuilder {
    public struct Report: Hashable, Sendable {
        public var pass: EditPass
        public var removed: Int
        public var added: Int

        /// "Zooms redone: 14 now, 9 before"
        public var summary: String {
            switch pass {
            case .captionLook: return added > 0 ? "Caption look redone" : "No captions to restyle"
            case .tease: return added > 0 ? "Tease replanted" : (removed > 0 ? "Tease removed: nothing strong enough lands late" : "Nothing strong enough lands late for a tease")
            default: return "\(pass.displayName) redone: \(added) now, \(removed) before"
            }
        }
    }

    /// The moments the edit still holds: the plan's moments that the edit plays at least half of.
    static func moments(in timeline: Timeline, plan: LongFormPlan, assetID: UUID) -> [LongFormSegment] {
        let program = EditCoach.Program(timeline: timeline, assetID: assetID)
        let kept = program.segments.map(\.sourceRange)
        return plan.moments.filter { moment in
            let covered = kept.reduce(0.0) { $0 + max(0, min($1.end, moment.range.end) - max($1.start, moment.range.start)) }
            return covered >= moment.range.duration * 0.5
        }
    }

    /// Where a time of the fresh build falls in the edit: the same instant of the recording, at the place it
    /// plays nearest to where it played in the fresh build. Nil when the edit no longer holds that instant.
    static func carry(_ time: Seconds, from fresh: EditCoach.Program, to existing: EditCoach.Program) -> (clip: TimelineClip, time: Seconds)? {
        guard let source = fresh.sourceTime(at: time) else { return nil }
        var best: (clip: TimelineClip, time: Seconds)?
        for clip in existing.segments where clip.sourceRange.contains(source) {
            let at = clip.timelineTime(atSource: source)
            if best == nil || abs(at - time) < abs(best!.time - time) { best = (clip, at) }
        }
        return best
    }

    /// Redoes `pass` in `timeline` with `options`. `sounds` are the effects the sound-effect pass may place.
    @discardableResult
    public static func rebuild(_ pass: EditPass, in timeline: inout Timeline, asset: MediaAsset, analysis: MediaAnalysis, options: LongFormOptions,
                               sounds: LongFormSounds = LongFormSounds(), taste: TasteProfile = TasteProfile()) -> Report {
        let plan = LongFormEditor.planMoments(analysis: analysis, options: options, taste: taste)
        let kept = moments(in: timeline, plan: plan, assetID: asset.id)
        guard !kept.isEmpty else { return Report(pass: pass, removed: 0, added: 0) }
        if pass == .tease {
            let had = (timeline.openLoops ?? []).count
            OpenLoopBuilder.remove(from: &timeline)
            guard let tease = OpenLoopBuilder.plan(timeline: timeline, moments: kept, assetID: asset.id) else { return Report(pass: pass, removed: had, added: 0) }
            OpenLoopBuilder.plant(tease, in: &timeline, assetID: asset.id)
            return Report(pass: pass, removed: had, added: 1)
        }
        var only = options
        only.keepStoryOrder = false
        let fresh = LongFormEditor.build(asset: asset, analysis: analysis, options: only, sounds: sounds, taste: taste, segments: kept).timeline
        let from = EditCoach.Program(timeline: fresh, assetID: asset.id)
        let to = EditCoach.Program(timeline: timeline, assetID: asset.id)
        var removed = 0, added = 0

        switch pass {
        case .zooms:
            // Out with the zooms PULSE made (yours stay), in with the fresh ones at the same instants of the recording.
            for ti in timeline.tracks.indices where timeline.tracks[ti].kind == .video {
                for ci in timeline.tracks[ti].clips.indices {
                    let before = timeline.tracks[ti].clips[ci].transform.zoom.keyframes.filter(\.aiGenerated).count
                    guard before > 0 else { continue }
                    removed += PlaybookCoach.zoomArrivals(of: timeline.tracks[ti].clips[ci], aiOnly: true)
                    timeline.tracks[ti].clips[ci].transform.zoom.removeAIKeyframes()
                }
            }
            for clip in from.segments {
                let keyframes = clip.transform.zoom.keyframes.filter(\.aiGenerated)
                guard !keyframes.isEmpty else { continue }
                let base = max(clip.transform.zoom.value, 0.01)
                for keyframe in keyframes {
                    guard let landed = carry(clip.start + keyframe.time, from: from, to: to),
                          let location = timeline.location(ofClip: landed.clip.id) else { continue }
                    var zoom = timeline.tracks[location.trackIndex].clips[location.clipIndex].transform.zoom
                    // The same move, measured from this clip's own framing.
                    zoom.setKeyframe(at: landed.time - landed.clip.start, value: zoom.value * keyframe.value / base,
                                     interpolation: keyframe.interpolation, aiGenerated: true)
                    timeline.tracks[location.trackIndex].clips[location.clipIndex].transform.zoom = zoom
                }
            }
            added = timeline.tracks.filter { $0.kind == .video }.flatMap(\.clips).reduce(0) { $0 + PlaybookCoach.zoomArrivals(of: $1, aiOnly: true) }

        case .popUps, .soundEffects:
            let wanted: (TimelineClip) -> Bool = pass == .popUps
                ? { clip in
                    guard clip.aiGenerated, case .text = clip.content else { return false }
                    // The tease and a chosen opening line are their own passes.
                    return clip.name != OpenLoopBuilder.clipName && clip.name != HookWriter.clipName
                }
                : { clip in clip.aiGenerated && clip.role == .soundEffect }
            for ti in timeline.tracks.indices {
                let before = timeline.tracks[ti].clips.count
                timeline.tracks[ti].clips.removeAll(where: wanted)
                removed += before - timeline.tracks[ti].clips.count
            }
            for clip in fresh.allClips.filter(wanted).sorted(by: { $0.start < $1.start }) {
                guard let landed = carry(clip.start, from: from, to: to) else { continue }
                var copy = clip
                copy.id = UUID()
                copy.start = landed.time
                let kind: TrackKind = pass == .popUps ? .text : .audio
                let trackID = timeline.freeTrack(kind: kind, for: TimeRange(start: copy.start, end: copy.start + copy.duration))
                guard let index = timeline.trackIndex(id: trackID) else { continue }
                timeline.tracks[index].clips.append(copy)
                timeline.tracks[index].clips.sort { $0.start < $1.start }
                added += 1
            }

        case .captionLook:
            // The words and what you hid or fixed stay; only how they look changes.
            if let look = fresh.captions?.style, timeline.captions != nil {
                timeline.captions?.style = look
                added = 1
            } else if timeline.captions == nil, let track = fresh.captions {
                timeline.captions = track
                added = 1
            }

        case .tease:
            break
        }
        timeline.modifiedAt = Date()
        return Report(pass: pass, removed: removed, added: added)
    }
}
