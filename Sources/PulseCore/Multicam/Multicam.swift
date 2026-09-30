import Foundation

/// One camera/screen of a synchronized recording session.
///
/// Session time is the shared clock of the group: an asset's own time `s` sits at session time
/// `s + offset` (`MediaAsset.syncOffset`, as produced by `AudioSync` or by PULSE's recorder).
public struct MulticamAngle: Hashable, Identifiable, Sendable {
    public var id: UUID { assetID }
    public var assetID: UUID
    public var name: String
    public var role: MediaRole
    public var offset: Seconds
    public var duration: Seconds
    public var hasVideo: Bool
    public var hasAudio: Bool
    public var size: Size2

    /// Session-time span this angle covers.
    public var sessionRange: TimeRange { TimeRange(start: offset, duration: duration) }

    public func sourceTime(atSession t: Seconds) -> Seconds { t - offset }
    public func sessionTime(atSource s: Seconds) -> Seconds { s + offset }

    public init(asset: MediaAsset) {
        assetID = asset.id
        name = asset.name
        role = asset.role
        offset = asset.syncOffset
        duration = asset.metadata.duration
        hasVideo = asset.kind == .video && asset.metadata.hasVideo
        hasAudio = asset.metadata.hasAudio
        size = asset.metadata.size
    }
}

/// A synchronized recording session with at least two video angles (podcast cameras, screen + webcam…).
public struct MulticamGroup: Hashable, Identifiable, Sendable {
    public var id: UUID
    public var angles: [MulticamAngle]

    public init(id: UUID, angles: [MulticamAngle]) {
        self.id = id
        self.angles = angles
    }

    /// Video angles, numbered 1…n for keyboard switching.
    public var videoAngles: [MulticamAngle] { angles.filter(\.hasVideo) }
    public var audioAngles: [MulticamAngle] { angles.filter(\.hasAudio) }

    public func angle(_ assetID: UUID) -> MulticamAngle? { angles.first { $0.assetID == assetID } }

    /// Union of all angles in session time.
    public var sessionRange: TimeRange {
        let starts = angles.map(\.sessionRange.start), ends = angles.map(\.sessionRange.end)
        return TimeRange(start: starts.min() ?? 0, end: ends.max() ?? 0)
    }

    /// Span where every video angle has picture (the safe range for a switched edit).
    public var commonVideoRange: TimeRange? {
        let video = videoAngles
        guard let start = video.map(\.sessionRange.start).max(), let end = video.map(\.sessionRange.end).min(), end > start else { return nil }
        return TimeRange(start: start, end: end)
    }

    /// The angle whose microphone should carry the edit: a dedicated mic, then a webcam, then the first with audio.
    public var preferredAudioAngle: MulticamAngle? {
        let audio = audioAngles
        return audio.first { $0.role == .microphone } ?? audio.first { $0.role == .webcam || $0.role == .camera } ?? audio.first
    }

    /// Groups the project's media by `syncGroupID`; only sessions with ≥2 video angles are multicam.
    public static func groups(in media: [MediaAsset]) -> [MulticamGroup] {
        var byGroup: [UUID: [MediaAsset]] = [:]
        for asset in media {
            guard let group = asset.syncGroupID else { continue }
            byGroup[group, default: []].append(asset)
        }
        return byGroup.compactMap { id, assets in
            let group = MulticamGroup(id: id, angles: assets.sorted { $0.importedAt < $1.importedAt }.map(MulticamAngle.init(asset:)))
            return group.videoAngles.count >= 2 ? group : nil
        }
        .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    public static func group(containing assetID: UUID, in media: [MediaAsset]) -> MulticamGroup? {
        groups(in: media).first { $0.angle(assetID) != nil }
    }
}

/// A span of the edit showing one angle (session time).
public struct MulticamCut: Hashable, Sendable {
    public var range: TimeRange
    public var assetID: UUID

    public init(range: TimeRange, assetID: UUID) {
        self.range = range
        self.assetID = assetID
    }
}

public enum MulticamError: Error, LocalizedError, Equatable {
    case notMulticam
    case angleNotAvailable(String)
    case noVideoAngles

    public var errorDescription: String? {
        switch self {
        case .notMulticam: return "That clip isn't part of a synchronized multicam recording."
        case .angleNotAvailable(let name): return "“\(name)” wasn't recording at that moment, so PULSE can't switch to it here."
        case .noVideoAngles: return "Multicam needs at least two synchronized video recordings."
        }
    }
}

/// Multicam editing on a normal timeline: every angle switch is a regular clip whose source in-point
/// is derived from session time, so everything stays editable, trimmable and exportable.
public enum MulticamEditor {
    /// Builds an editable timeline from switch decisions: angle clips on V1, one continuous audio clip.
    public static func timeline(cuts: [MulticamCut], group: MulticamGroup, audioAssetID: UUID?, canvas: CanvasSettings, name: String) -> Timeline {
        var timeline = Timeline.empty(name: name, canvas: canvas)
        timeline.tracks[0].name = "V1 Multicam"
        let sorted = cuts.sorted { $0.range.start < $1.range.start }
        let origin = sorted.first?.range.start ?? 0
        for cut in sorted where cut.range.duration > Timeline.minimumClipDuration {
            guard let angle = group.angle(cut.assetID) else { continue }
            var clip = TimelineClip(name: angle.name, content: .media(assetID: angle.assetID), start: cut.range.start - origin,
                                    sourceIn: angle.sourceTime(atSession: cut.range.start), sourceDuration: cut.range.duration,
                                    role: angle.role == .gameplay ? .gameplay : .camera)
            clip.transform.fit = .fill
            timeline.tracks[0].clips.append(clip)
        }
        if let end = sorted.last?.range.end, let audioID = audioAssetID ?? group.preferredAudioAngle?.assetID, let angle = group.angle(audioID) {
            // Audio only where that mic was recording.
            let span = TimeRange(start: max(origin, angle.sessionRange.start), end: min(end, angle.sessionRange.end))
            if span.duration > Timeline.minimumClipDuration, let ai = timeline.tracks.firstIndex(where: { $0.kind == .audio }) {
                var audio = TimelineClip(name: "\(angle.name) audio", content: .media(assetID: angle.assetID), start: span.start - origin,
                                         sourceIn: angle.sourceTime(atSession: span.start), sourceDuration: span.duration, role: .microphone)
                audio.audio.normalize = true
                timeline.tracks[ai].clips.append(audio)
            }
        }
        timeline.notes = "Multicam edit · \(group.videoAngles.count) angles"
        return timeline
    }

    /// Session time shown at timeline time `t` by `clip`.
    public static func sessionTime(of clip: TimelineClip, atTimeline t: Seconds, group: MulticamGroup) -> Seconds? {
        guard let id = clip.assetID, let angle = group.angle(id) else { return nil }
        return angle.sessionTime(atSource: clip.sourceTime(atTimeline: t))
    }

    /// Replaces the angle of a whole clip, keeping it in sync (same session time, same length).
    public static func switchAngle(_ timeline: inout Timeline, clipID: UUID, to assetID: UUID, group: MulticamGroup) throws {
        guard let clip = timeline.clip(id: clipID), let current = clip.assetID, let from = group.angle(current) else { throw MulticamError.notMulticam }
        guard let to = group.angle(assetID), to.hasVideo else { throw MulticamError.notMulticam }
        let session = from.sessionTime(atSource: clip.sourceIn)
        let newIn = to.sourceTime(atSession: session)
        guard newIn >= -0.001, newIn + clip.sourceDuration <= to.duration + 0.05 else { throw MulticamError.angleNotAvailable(to.name) }
        timeline.updateClip(id: clipID) { c in
            c.content = .media(assetID: to.assetID)
            c.sourceIn = max(0, newIn)
            c.name = to.name
            c.role = to.role == .gameplay ? .gameplay : .camera
        }
    }

    /// Live-switch: cuts the multicam clip under `time` and shows `assetID` from there to the clip's end.
    /// Returns the id of the clip now showing the new angle.
    @discardableResult
    public static func cut(_ timeline: inout Timeline, at time: Seconds, to assetID: UUID, group: MulticamGroup) throws -> UUID {
        let candidates = timeline.tracks.filter { $0.kind == .video && !$0.isLocked }.flatMap(\.clips)
        guard let clip = candidates.first(where: { c in
            c.timelineRange.contains(time) && (c.assetID.map { group.angle($0) != nil } ?? false)
        }) ?? candidates.first(where: { c in
            abs(c.end - time) < 0.02 && (c.assetID.map { group.angle($0) != nil } ?? false)
        }) else { throw MulticamError.notMulticam }
        if clip.assetID == assetID { return clip.id }
        let frame = 1.0 / max(timeline.canvas.frameRate, 1)
        let target: UUID
        if time - clip.start < frame {
            target = clip.id
        } else if clip.end - time < frame {
            throw MulticamError.notMulticam
        } else {
            guard let right = try timeline.split(at: time, clipIDs: [clip.id]).first else { throw MulticamError.notMulticam }
            target = right
        }
        try switchAngle(&timeline, clipID: target, to: assetID, group: group)
        mergeAdjacentSameAngle(&timeline, around: target, group: group)
        return target
    }

    /// Joins neighbouring clips that ended up on the same angle with continuous source time.
    static func mergeAdjacentSameAngle(_ timeline: inout Timeline, around clipID: UUID, group: MulticamGroup) {
        guard let ti = timeline.tracks.firstIndex(where: { $0.clips.contains { $0.id == clipID } }) else { return }
        var clips = timeline.tracks[ti].clips.sorted { $0.start < $1.start }
        var i = 0
        while i + 1 < clips.count {
            let a = clips[i], b = clips[i + 1]
            let contiguous = abs(a.end - b.start) < 0.001 && abs(a.sourceOut - b.sourceIn) < 0.001
            if a.assetID == b.assetID, contiguous, a.speed == b.speed, a.linkGroup == nil, b.linkGroup == nil,
               a.transitionOut == nil, b.transitionIn == nil {
                clips[i].sourceDuration += b.sourceDuration
                clips.remove(at: i + 1)
            } else {
                i += 1
            }
        }
        timeline.tracks[ti].clips = clips
    }

    /// AI switching: shows whoever is talking. `levels` are each angle's RMS loudness (dB) in its own
    /// source time at `hop`. Angles without audio levels (e.g. a screen recording) are used as the
    /// "wide" shot when nobody speaks or several people talk at once.
    public static func autoSwitch(group: MulticamGroup, levels: [UUID: [Float]], hop: Seconds, range: TimeRange? = nil,
                                  minimumShot: Seconds = 2.0, silenceDB: Float = -45, crosstalkDB: Float = 3,
                                  wideAngle: UUID? = nil) -> [MulticamCut] {
        let video = group.videoAngles
        guard !video.isEmpty, hop > 0 else { return [] }
        let span = range ?? group.commonVideoRange ?? group.sessionRange
        guard span.duration > 0 else { return [] }
        let wide = wideAngle.flatMap { group.angle($0) } ?? video.first { levels[$0.assetID] == nil } ?? video.first!
        let speakers = video.filter { levels[$0.assetID] != nil }
        // Smoothed level of an angle's mic at session time (1 s moving average).
        func level(_ angle: MulticamAngle, _ t: Seconds) -> Float {
            guard let series = levels[angle.assetID], !series.isEmpty else { return -120 }
            let center = Int((angle.sourceTime(atSession: t) / hop).rounded())
            let radius = max(1, Int(0.5 / hop))
            var sum: Float = 0
            var n = 0
            for i in (center - radius)...(center + radius) where i >= 0 && i < series.count {
                sum += series[i]
                n += 1
            }
            return n > 0 ? sum / Float(n) : -120
        }
        // 1. Raw decision every 0.25 s.
        let step = 0.25
        var decisions: [(t: Seconds, angle: UUID)] = []
        var t = span.start
        while t < span.end {
            let available = speakers.filter { $0.sessionRange.contains(t) }
            let ranked = available.map { ($0, level($0, t)) }.sorted { $0.1 > $1.1 }
            var choice = wide.assetID
            if let best = ranked.first, best.1 > silenceDB {
                let second = ranked.dropFirst().first?.1 ?? -120
                choice = best.1 - second >= crosstalkDB || ranked.count == 1 ? best.0.assetID : wide.assetID
            }
            if !(group.angle(choice)?.sessionRange.contains(t) ?? false) {
                choice = video.first { $0.sessionRange.contains(t) }?.assetID ?? choice
            }
            decisions.append((t, choice))
            t += step
        }
        // 2. Runs of the same angle.
        var cuts: [MulticamCut] = []
        for (i, d) in decisions.enumerated() {
            let end = i + 1 < decisions.count ? decisions[i + 1].t : span.end
            if let last = cuts.last, last.assetID == d.angle {
                cuts[cuts.count - 1].range = TimeRange(start: last.range.start, end: end)
            } else {
                cuts.append(MulticamCut(range: TimeRange(start: d.t, end: end), assetID: d.angle))
            }
        }
        // 3. Enforce the minimum shot length by absorbing short shots into the previous one.
        var merged: [MulticamCut] = []
        for cut in cuts {
            if let last = merged.last, cut.range.duration < minimumShot || last.range.duration < minimumShot {
                let absorbed = last.range.duration < minimumShot && cut.range.duration >= minimumShot ? cut.assetID : last.assetID
                merged[merged.count - 1] = MulticamCut(range: TimeRange(start: last.range.start, end: cut.range.end), assetID: absorbed)
            } else if let last = merged.last, last.assetID == cut.assetID {
                merged[merged.count - 1].range = TimeRange(start: last.range.start, end: cut.range.end)
            } else {
                merged.append(cut)
            }
        }
        // 4. Every shot must be covered by its angle; otherwise fall back to one that is.
        return merged.map { cut in
            guard let angle = group.angle(cut.assetID), angle.sessionRange.start <= cut.range.start + 0.001,
                  angle.sessionRange.end >= cut.range.end - 0.001 else {
                let fallback = video.first { $0.sessionRange.start <= cut.range.start + 0.001 && $0.sessionRange.end >= cut.range.end - 0.001 }
                return MulticamCut(range: cut.range, assetID: fallback?.assetID ?? cut.assetID)
            }
            return cut
        }
    }
}
