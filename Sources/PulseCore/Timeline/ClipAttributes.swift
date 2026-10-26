import Foundation

/// The look and sound of one clip, lifted off it to paste onto others (#165): transform (with its keyframes),
/// style, color, effects and audio, in any combination.
public struct ClipAttributes: Codable, Hashable, Sendable {
    public struct Parts: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let transform = Parts(rawValue: 1)
        public static let style = Parts(rawValue: 2)
        public static let color = Parts(rawValue: 4)
        public static let effects = Parts(rawValue: 8)
        public static let audio = Parts(rawValue: 16)
        public static let look: Parts = [.transform, .style, .color, .effects]
        public static let all: Parts = [.transform, .style, .color, .effects, .audio]

        public var displayName: String {
            var names: [String] = []
            if contains(.transform) { names.append("transform") }
            if contains(.style) { names.append("style") }
            if contains(.color) { names.append("color") }
            if contains(.effects) { names.append("effects") }
            if contains(.audio) { names.append("audio") }
            return names.joined(separator: ", ")
        }
    }

    public var transform: VisualTransform
    public var style: LayerStyle
    public var styleKeyframes: [StyleKeyframe]
    public var color: ColorAdjustments
    public var effects: [EffectInstance]
    public var audio: AudioSettings
    public var sourceName: String

    public init(from clip: TimelineClip) {
        transform = clip.transform
        style = clip.style
        styleKeyframes = clip.styleKeyframes
        color = clip.color
        effects = clip.effects
        audio = clip.audio
        sourceName = clip.name
    }

    /// Applies the chosen parts. Audio censoring and fades are left alone: they belong to the words and the
    /// edges of the target clip, not to the source.
    public func apply(to clip: inout TimelineClip, parts: Parts = .all) {
        if parts.contains(.transform) { clip.transform = transform }
        if parts.contains(.style) {
            clip.style = style
            clip.styleKeyframes = styleKeyframes
        }
        if parts.contains(.color) { clip.color = color }
        if parts.contains(.effects) { clip.effects = effects }
        if parts.contains(.audio) {
            var a = audio
            a.fadeIn = clip.audio.fadeIn
            a.fadeOut = clip.audio.fadeOut
            a.censor = clip.audio.censor
            a.censorRanges = clip.audio.censorRanges
            clip.audio = a
        }
    }
}

extension Timeline {
    /// Pastes attributes onto clips (linked partners of a different kind are skipped: a video clip's look
    /// doesn't apply to its audio). Returns how many clips changed.
    @discardableResult
    public mutating func paste(_ attributes: ClipAttributes, onto clipIDs: [UUID], parts: ClipAttributes.Parts = .all) -> Int {
        var count = 0
        for t in tracks.indices where !tracks[t].isLocked {
            for c in tracks[t].clips.indices where clipIDs.contains(tracks[t].clips[c].id) {
                let visual = tracks[t].kind != .audio
                let wanted = visual ? parts : parts.intersection(.audio)
                guard !wanted.isEmpty else { continue }
                attributes.apply(to: &tracks[t].clips[c], parts: wanted)
                count += 1
            }
        }
        if count > 0 { touch() }
        return count
    }

    /// Adds a transition at the edges of `clipIDs` that touch a neighbour on the same track (#168): the
    /// outgoing clip gets it as its out transition and the incoming one as its in, so either side of the
    /// edit carries it. Returns how many edit points got one.
    @discardableResult
    public mutating func addTransition(_ transition: ClipTransition, toEdgesOf clipIDs: [UUID]) -> Int {
        var count = 0
        for t in tracks.indices where !tracks[t].isLocked && tracks[t].kind != .audio {
            let clips = tracks[t].clips
            for c in clips.indices where clipIDs.contains(clips[c].id) {
                if c > 0, abs(clips[c - 1].end - clips[c].start) <= TimeRange.epsilon, tracks[t].clips[c].transitionIn == nil {
                    tracks[t].clips[c].transitionIn = transition
                    tracks[t].clips[c - 1].transitionOut = transition
                    count += 1
                }
                if c + 1 < clips.count, abs(clips[c].end - clips[c + 1].start) <= TimeRange.epsilon, tracks[t].clips[c].transitionOut == nil {
                    tracks[t].clips[c].transitionOut = transition
                    tracks[t].clips[c + 1].transitionIn = transition
                    count += 1
                }
            }
        }
        if count > 0 { touch() }
        return count
    }

    /// The edit point (a cut between two touching clips on a video track) nearest `time`, within `tolerance`.
    public func editPoint(near time: Seconds, tolerance: Seconds = 0.5) -> (trackIndex: Int, outgoing: UUID, incoming: UUID)? {
        var best: (Int, UUID, UUID, Seconds)?
        for t in tracks.indices where tracks[t].kind != .audio {
            let clips = tracks[t].clips
            for c in 1..<max(1, clips.count) where abs(clips[c - 1].end - clips[c].start) <= TimeRange.epsilon {
                let d = abs(clips[c].start - time)
                if d <= tolerance, best.map({ d < $0.3 }) ?? true { best = (t, clips[c - 1].id, clips[c].id, d) }
            }
        }
        return best.map { ($0.0, $0.1, $0.2) }
    }
}
