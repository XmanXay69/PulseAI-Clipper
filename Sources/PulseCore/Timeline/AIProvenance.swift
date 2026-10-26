import Foundation

extension TimelineClip {
    /// "Why is this here?" for a clip an AI pass placed (#230): which pass, in plain words. Nil for your own clips.
    public var aiPassDescription: String? {
        guard aiGenerated else { return nil }
        let lower = name.lowercased()
        if name == "Hook" || name == "Hook Title" { return "Cold open — the hook Edit My VOD put first" }
        if name == "Replay" || lower.hasPrefix("▶ replay") { return "Instant replays extra — the play again in slow motion" }
        if lower.hasPrefix("meme") { return "Meme pop-ups — a text pop on a big moment" }
        if name == "Title Card" { return "Title cards extra — a card at the start of a section" }
        if name == "Pause" { return "Shorten pauses — a pause played at 1.6×" }
        if name == "End Screen" || name == "End Screen Subtitle" { return "End screen — the closing card with chapters" }
        if name == "Freeze" || lower.contains("freeze") { return "Freeze frame" }
        if lower.contains("b-roll") || role == .graphic && content.assetID != nil && lower.contains("broll") { return "B-roll extra — a cutaway under the talking" }
        switch role {
        case .soundEffect: return "Sound effects pass — a whoosh, boom or sting on a cut or a punchline"
        case .music: return "Music — a bed per chapter, ducked under the talking"
        case .graphic: return "A cutaway placed by an AI pass"
        default: break
        }
        switch content {
        case .text: return "A text card placed by an AI pass"
        case .solid: return "A background placed by an AI pass"
        default: return "Placed by an AI pass (Edit My VOD or Make More Entertaining)"
        }
    }

    /// True when the clip or any of its transform keyframes was set by an AI pass.
    public var hasAIMarks: Bool {
        aiGenerated || transform.hasAnyAIKeyframes
    }

    /// "Make mine" (#210): keeps every value and keyframe, drops the AI flags so nothing shows an AI badge or
    /// gets cleaned up by a later AI pass.
    public mutating func stripAIFlags() {
        aiGenerated = false
        transform.stripAIFlags()
        if transitionIn?.aiGenerated == true { transitionIn?.aiGenerated = false }
        if transitionOut?.aiGenerated == true { transitionOut?.aiGenerated = false }
    }
}

extension VisualTransform {
    static let animatedProperties: [WritableKeyPath<VisualTransform, AnimatedDouble>] = [
        \.positionX, \.positionY, \.scale, \.rotation, \.opacity, \.zoom, \.panX, \.panY,
    ]

    public var hasAnyAIKeyframes: Bool {
        VisualTransform.animatedProperties.contains { self[keyPath: $0].hasAIKeyframes }
    }

    public mutating func stripAIFlags() {
        for keyPath in VisualTransform.animatedProperties {
            let animated = self[keyPath: keyPath]
            guard animated.hasAIKeyframes else { continue }
            var rebuilt = AnimatedDouble(animated.value)
            for k in animated.keyframes {
                _ = rebuilt.setKeyframe(at: k.time, value: k.value, interpolation: k.interpolation, aiGenerated: false)
            }
            self[keyPath: keyPath] = rebuilt
        }
    }
}
