import Foundation

/// The parts of a stream nobody wants in the video: the "mic check, can you hear me?" setup at the start and
/// the "thanks for watching, raiding now" wind-down at the end. Found from what's said, so they're only
/// trimmed when they're really there.
public enum StreamEdges {
    static let introCues = ["mic check", "can you hear me", "can you guys hear me", "can y'all hear me", "am i live", "are we live",
                            "is it working", "stream starting", "let me set up", "setting up", "give me a sec", "give me a second",
                            "one sec", "hold on let me", "audio good", "sound good", "is the audio", "can you see", "let me fix"]
    static let outroCues = ["thanks for watching", "thank you for watching", "see you tomorrow", "see you guys", "see you next",
                            "see you all", "raid", "raiding", "ending stream", "ending the stream", "end the stream", "end stream",
                            "done for today", "that's it for today", "that's all for today", "goodnight", "good night chat",
                            "peace out", "have a good one", "i'm gonna head out", "gonna head out", "catch you"]

    /// Setup talk at the start (source time), or nil when the stream just starts.
    public static func intro(words: [TranscriptWord], window: Seconds = 180) -> TimeRange? {
        let early = words.filter { $0.start < window }.sorted { $0.start < $1.start }
        guard let last = lastCue(in: early, cues: introCues) else { return nil }
        // Through the end of the sentence that held the cue.
        var end = early[last].end
        var i = last
        while i < early.count - 1, !endsSentence(early[i]), early[i + 1].start - early[i].end < 0.8 { i += 1; end = early[i].end }
        return TimeRange(start: 0, end: min(end + 0.4, window))
    }

    /// Wind-down talk at the end (source time), or nil.
    public static func outro(words: [TranscriptWord], duration: Seconds, window: Seconds = 180) -> TimeRange? {
        let late = words.filter { $0.end > duration - window }.sorted { $0.start < $1.start }
        guard let first = firstCue(in: late, cues: outroCues) else { return nil }
        // From the start of the sentence that holds the cue.
        var start = late[first].start
        var i = first
        while i > 0, !endsSentence(late[i - 1]), late[i].start - late[i - 1].end < 0.8 { i -= 1; start = late[i].start }
        return TimeRange(start: max(start - 0.4, duration - window), end: duration)
    }

    static func endsSentence(_ w: TranscriptWord) -> Bool { w.text.hasSuffix(".") || w.text.hasSuffix("?") || w.text.hasSuffix("!") }

    static func normalized(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "'" }
    }

    /// Index of the last word that ends a cue phrase.
    static func lastCue(in words: [TranscriptWord], cues: [String]) -> Int? {
        matches(in: words, cues: cues).last
    }

    static func firstCue(in words: [TranscriptWord], cues: [String]) -> Int? {
        matches(in: words, cues: cues).first
    }

    /// For each cue, the index of the word where it ends (phrases span up to 5 words).
    static func matches(in words: [TranscriptWord], cues: [String]) -> [Int] {
        let tokens = words.map { normalized($0.text).trimmingCharacters(in: .whitespaces) }
        var out: [Int] = []
        for i in tokens.indices {
            for n in 1...5 where i + n <= tokens.count {
                let phrase = tokens[i..<(i + n)].joined(separator: " ")
                if cues.contains(phrase) { out.append(i + n - 1) }
            }
        }
        return out.sorted()
    }
}

// MARK: - Looks

extension ColorAdjustments {
    /// One-click grades. Each is a gentle, broadcast-safe starting point; `intensity` scales it.
    public enum Look: String, CaseIterable, Codable, Sendable {
        case clean, punchy, film, cold, warm

        public var displayName: String { rawValue.capitalized }
        public var detail: String {
            switch self {
            case .clean: return "A touch of contrast and colour"
            case .punchy: return "Bold contrast and saturation for gameplay"
            case .film: return "Softer colour, warmer, light vignette"
            case .cold: return "Cooler, slightly desaturated"
            case .warm: return "Warmer skin tones, a little richer"
            }
        }
    }

    public static func look(_ look: Look, intensity: Double = 1) -> ColorAdjustments {
        var c = ColorAdjustments()
        switch look {
        case .clean: c.contrast = 0.06; c.saturation = 0.06
        case .punchy: c.contrast = 0.16; c.saturation = 0.2; c.shadows = -0.06; c.sharpness = 0.15
        case .film: c.contrast = 0.08; c.saturation = -0.14; c.temperature = 0.07; c.highlights = -0.12; c.vignette = 0.28
        case .cold: c.temperature = -0.2; c.tint = 0.03; c.saturation = -0.06; c.contrast = 0.04
        case .warm: c.temperature = 0.18; c.saturation = 0.08; c.contrast = 0.04; c.shadows = 0.04
        }
        let k = intensity.clamped(0, 1.5)
        c.exposure *= k; c.contrast *= k; c.highlights *= k; c.shadows *= k; c.saturation *= k
        c.temperature *= k; c.tint *= k; c.sharpness *= k; c.vignette *= k
        return c
    }
}


// MARK: - Scene cuts

public enum SceneSnap {
    /// Moves a section's start onto a scene change just before it (≤ `tolerance` s earlier), so sections open
    /// on a fresh shot instead of a frame after one — unless a word is being spoken across that cut.
    public static func snapStarts(_ segments: [LongFormSegment], sceneCuts: [Seconds], words: [TranscriptWord], tolerance: Seconds = 1.5) -> [LongFormSegment] {
        guard !sceneCuts.isEmpty else { return segments }
        let cuts = sceneCuts.sorted()
        return segments.map { segment in
            var s = segment
            let start = segment.range.start
            guard let cut = cuts.last(where: { $0 <= start && $0 >= start - tolerance }), cut < start - 0.05,
                  !words.contains(where: { $0.start < cut - 0.05 && $0.end > cut + 0.05 }) else { return s }
            s.range = TimeRange(start: cut, end: segment.range.end)
            return s
        }
    }
}
