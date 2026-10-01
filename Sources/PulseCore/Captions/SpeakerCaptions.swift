import Foundation

/// How one speaker's captions differ from the track style. Nil fields inherit.
public struct SpeakerCaptionStyle: Codable, Hashable, Sendable {
    public var textColor: RGBAColor?
    public var highlightColor: RGBAColor?
    public var positionX: Double?
    public var positionY: Double?

    public init(textColor: RGBAColor? = nil, highlightColor: RGBAColor? = nil, positionX: Double? = nil, positionY: Double? = nil) {
        self.textColor = textColor
        self.highlightColor = highlightColor
        self.positionX = positionX
        self.positionY = positionY
    }

    public var isEmpty: Bool { textColor == nil && highlightColor == nil && positionX == nil && positionY == nil }
}

extension CaptionPage {
    /// Pages never mix speakers, so the first word's speaker is the page's.
    public var speaker: Int? { words.first?.speaker }
}

extension CaptionTrack {
    /// Text / highlight colors given to speakers by "Color by speaker" (the first speaker keeps the style's own).
    public static let speakerPalette: [(text: RGBAColor, highlight: RGBAColor)] = [
        (RGBAColor(hex: "#5CE1FF")!, RGBAColor(hex: "#FFFFFF")!),   // cyan
        (RGBAColor(hex: "#8CFF6B")!, RGBAColor(hex: "#FFFFFF")!),   // green
        (RGBAColor(hex: "#FF7AD9")!, RGBAColor(hex: "#FFFFFF")!),   // pink
        (RGBAColor(hex: "#FFB347")!, RGBAColor(hex: "#FFFFFF")!),   // orange
        (RGBAColor(hex: "#B48CFF")!, RGBAColor(hex: "#FFFFFF")!),   // violet
    ]

    /// Speakers present in the captions, in order of first appearance.
    public var captionSpeakers: [Int] {
        var seen: [Int] = []
        for w in words where !w.isHidden {
            if let s = w.speaker, !seen.contains(s) { seen.append(s) }
        }
        return seen
    }

    public func speakerName(_ id: Int) -> String { speakerNames[id] ?? "Speaker \(id + 1)" }

    /// The full caption style for a page spoken by `speaker`.
    public func style(forSpeaker speaker: Int?) -> CaptionStyle {
        guard let speaker, let override = speakerStyles[speaker], !override.isEmpty else { return style }
        var s = style
        if let c = override.textColor { s.text.color = c }
        if let c = override.highlightColor { s.highlightColor = c }
        if let x = override.positionX { s.positionX = x }
        if let y = override.positionY { s.positionY = y }
        return s
    }

    public var isColoredBySpeaker: Bool { speakerStyles.values.contains { $0.textColor != nil } }

    /// Gives every speaker after the first their own text color (keeps positions the user set).
    public mutating func colorBySpeaker() {
        let speakers = captionSpeakers
        guard speakers.count >= 2 else { return }
        for (i, id) in speakers.enumerated() {
            var s = speakerStyles[id] ?? SpeakerCaptionStyle()
            if i == 0 {
                s.textColor = nil
                s.highlightColor = nil
            } else {
                let colors = Self.speakerPalette[(i - 1) % Self.speakerPalette.count]
                s.textColor = colors.text
                // Keep the highlight visible against the new color.
                s.highlightColor = style.highlightColor == colors.text ? .white : (style.highlightColor == .white ? RGBAColor(hex: "#FFE14D")! : colors.highlight)
            }
            speakerStyles[id] = s.isEmpty ? nil : s
        }
    }

    /// Removes per-speaker colors (positions stay).
    public mutating func clearSpeakerColors() {
        for (id, var s) in speakerStyles {
            s.textColor = nil
            s.highlightColor = nil
            speakerStyles[id] = s.isEmpty ? nil : s
        }
    }

    /// Re-labels caption words from a (re-)diarized transcript: each word takes the speaker of the
    /// transcript word it overlaps most. Names follow too.
    public mutating func syncSpeakers(from transcript: Transcript) {
        let source = transcript.words
        guard !source.isEmpty else { return }
        func center(_ w: TranscriptWord) -> Seconds { (w.start + w.end) / 2 }
        var j = 0
        for i in words.indices {
            let w = words[i]
            let mid = (w.start + w.end) / 2
            while j < source.count - 1 && source[j].end < mid { j += 1 }
            let candidates = [j - 1, j, j + 1].filter { $0 >= 0 && $0 < source.count }
            let best = candidates.min { abs(center(source[$0]) - mid) < abs(center(source[$1]) - mid) }
            words[i].speaker = best.flatMap { source[$0].speaker }
        }
        speakerNames = [:]
        for speaker in transcript.speakers { speakerNames[speaker.id] = speaker.name }
        let present = Set(captionSpeakers)
        speakerStyles = speakerStyles.filter { present.contains($0.key) }
    }
}
