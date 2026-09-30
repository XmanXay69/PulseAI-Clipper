import Foundation

/// AI reframing: pans a full-frame crop to follow the subject (face) with smooth, sparse keyframes.
public enum AutoReframer {
    /// Adds pan keyframes to a clip so its crop follows faces detected in the source.
    /// - Parameters:
    ///   - faces: face samples in SOURCE time of the clip's asset.
    ///   - deadZone: normalized movement ignored to avoid jitter.
    public static func applyFaceTracking(to clip: inout TimelineClip, faces: [FaceSample], deadZone: Double = 0.04, minInterval: Seconds = 0.8) {
        clip.transform.panX.removeAIKeyframes()
        clip.transform.panY.removeAIKeyframes()
        let src = clip.sourceRange
        let samples = faces.filter { src.contains($0.time) && !$0.boxes.isEmpty }
        guard samples.count >= 2 else { return }
        let baseCenter = clip.transform.crop.center
        let cropW = clip.transform.crop.width
        // Largest face per sample, smoothed with an exponential moving average.
        var smoothed: [(time: Seconds, x: Double)] = []
        var ema: Double?
        for s in samples {
            guard let face = s.boxes.max(by: { $0.area < $1.area }) else { continue }
            let x = face.center.x
            ema = ema.map { $0 * 0.6 + x * 0.4 } ?? x
            smoothed.append((s.time, ema!))
        }
        var lastKeyTime = -Double.infinity
        var lastX = smoothed.first!.x
        var added = 0
        for (i, sample) in smoothed.enumerated() {
            let isFirst = i == 0
            guard isFirst || (abs(sample.x - lastX) > deadZone && sample.time - lastKeyTime >= minInterval) else { continue }
            // Pan so the face sits at the crop center, clamped so the crop stays in frame.
            let desiredCenter = sample.x.clamped(cropW / 2, 1 - cropW / 2)
            let pan = desiredCenter - baseCenter.x
            let local = clip.localTime(atTimeline: clip.timelineTime(atSource: sample.time))
            clip.transform.panX.setKeyframe(at: max(local, 0), value: pan, interpolation: .easeInOut, aiGenerated: true)
            lastKeyTime = sample.time
            lastX = sample.x
            added += 1
        }
        if added == 1 {
            // A single keyframe is just a static offset.
            let v = clip.transform.panX.value(at: 0)
            clip.transform.panX.removeAIKeyframes()
            clip.transform.panX.value = v
        }
    }
}

public struct PunchInSettings: Codable, Hashable, Sendable {
    public var statementZoom: Double = 1.08
    public var punchlineZoom: Double = 1.14
    public var reactionZoom: Double = 1.2
    /// Minimum seconds between punch-ins so they stay tasteful.
    public var minimumSpacing: Seconds = 4
    public var rampDuration: Seconds = 0.18
    public var holdDuration: Seconds = 1.4

    public init() {}
}

/// Creates subtle AI zooms on emphasis moments. Every keyframe is marked AI-generated and editable.
public enum PunchInGenerator {
    public enum Moment: Sendable {
        case statement(Seconds)
        case punchline(Seconds)
        case reaction(Seconds)

        var time: Seconds {
            switch self {
            case .statement(let t), .punchline(let t), .reaction(let t): return t
            }
        }

        var priority: Int {
            switch self {
            case .reaction: return 3
            case .punchline: return 2
            case .statement: return 1
            }
        }
    }

    /// `moments` are in TIMELINE time. Applies zoom keyframes to the clips on `trackID` covering them.
    public static func apply(moments: [Moment], to timeline: inout Timeline, trackID: UUID, settings: PunchInSettings = PunchInSettings()) {
        guard let ti = timeline.trackIndex(id: trackID) else { return }
        for ci in timeline.tracks[ti].clips.indices {
            timeline.tracks[ti].clips[ci].transform.zoom.removeAIKeyframes()
        }
        // Highest priority first, enforcing spacing.
        var chosen: [Moment] = []
        for m in moments.sorted(by: { $0.priority != $1.priority ? $0.priority > $1.priority : $0.time < $1.time }) {
            if chosen.contains(where: { abs($0.time - m.time) < settings.minimumSpacing }) { continue }
            chosen.append(m)
        }
        for m in chosen.sorted(by: { $0.time < $1.time }) {
            guard let ci = timeline.tracks[ti].clips.firstIndex(where: { $0.timelineRange.contains(m.time) }) else { continue }
            let clip = timeline.tracks[ti].clips[ci]
            let local = m.time - clip.start
            let level: Double
            switch m {
            case .statement: level = settings.statementZoom
            case .punchline: level = settings.punchlineZoom
            case .reaction: level = settings.reactionZoom
            }
            let rampStart = max(0, local - settings.rampDuration)
            let holdEnd = min(clip.duration, local + settings.holdDuration)
            let release = min(clip.duration, holdEnd + settings.rampDuration * 1.5)
            var zoom = timeline.tracks[ti].clips[ci].transform.zoom
            let base = zoom.value
            zoom.setKeyframe(at: rampStart, value: base, interpolation: .easeOut, aiGenerated: true)
            zoom.setKeyframe(at: max(local, rampStart + 0.05), value: base * level, interpolation: .hold, aiGenerated: true)
            if holdEnd < clip.duration - 0.05 {
                zoom.setKeyframe(at: holdEnd, value: base * level, interpolation: .easeInOut, aiGenerated: true)
                zoom.setKeyframe(at: release, value: base, interpolation: .linear, aiGenerated: true)
            }
            timeline.tracks[ti].clips[ci].transform.zoom = zoom
        }
        timeline.modifiedAt = Date()
    }
}
