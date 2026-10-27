import Foundation

/// How hard each second of a timeline is to draw (#183): layers, effects, keys and captions add up, and
/// the ruler shows green where the viewer will keep up and red where it may not.
public enum RenderLoad {
    public struct Span: Hashable, Sendable {
        public var range: TimeRange
        /// Roughly the number of full-frame passes a frame needs; 1 = one plain layer.
        public var cost: Double
        public var isHeavy: Bool { cost >= heavyThreshold }
    }

    /// The cost from which a second counts as heavy on an average machine at full quality.
    public static let heavyThreshold: Double = 6

    /// The cost of drawing `clip` for one frame.
    public static func cost(of clip: TimelineClip) -> Double {
        var c = 1.0
        if clip.style.chromaKey?.enabled == true { c += 2 }
        if let feather = clip.style.feather, feather > 0 { c += 1 }
        if clip.style.shadowOpacity > 0 { c += 0.5 }
        if !clip.color.isIdentity { c += 0.5 }
        if clip.color.autoWhiteBalance { c += 1 }
        if clip.color.grain > 0 { c += 1 }
        for effect in clip.effects where effect.isEnabled {
            switch effect.kind {
            case .gaussianBlur, .motionBlur, .glow: c += 2.5
            case .chromaticAberration, .filmGrain: c += 1.5
            case .shake, .zoomPulse: c += 0.3
            default: c += 0.8
            }
        }
        if clip.speed != 1 { c += 0.5 }
        if case .text = clip.content { c = 0.6 }
        if case .compound = clip.content { c += 2 }
        return c
    }

    /// One span per second of the timeline, with the summed cost of everything on screen then.
    public static func profile(_ timeline: Timeline, step: Seconds = 1) -> [Span] {
        let duration = timeline.duration
        guard duration > 0, step > 0 else { return [] }
        let clips = timeline.tracks.filter { $0.kind != .audio && !$0.isHidden }.flatMap(\.clips).filter(\.isEnabled)
        var spans: [Span] = []
        var t: Seconds = 0
        while t < duration {
            let end = min(t + step, duration)
            let mid = (t + end) / 2
            var cost = 0.0
            for clip in clips where clip.timelineRange.contains(mid) { cost += self.cost(of: clip) }
            if timeline.captions?.isEnabled == true { cost += 0.8 }
            spans.append(Span(range: TimeRange(start: t, end: end), cost: cost))
            t = end
        }
        return spans
    }

    /// Neighbouring seconds with the same verdict merged, for drawing.
    public static func merged(_ spans: [Span]) -> [Span] {
        var out: [Span] = []
        for span in spans {
            if let last = out.last, last.isHeavy == span.isHeavy {
                out[out.count - 1] = Span(range: TimeRange(start: last.range.start, end: span.range.end), cost: max(last.cost, span.cost))
            } else {
                out.append(span)
            }
        }
        return out
    }
}
