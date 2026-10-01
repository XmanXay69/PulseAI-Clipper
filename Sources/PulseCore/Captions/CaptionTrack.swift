import Foundation

/// A caption word in SOURCE time of the captioned asset. Keeping source time means captions stay
/// in sync automatically through every trim, split, silence cut and speed change.
public struct CaptionWord: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var text: String
    public var start: Seconds
    public var end: Seconds
    public var isEmphasized: Bool
    /// Emphasis chosen by AI (vs. the user) — shown with an AI badge, cleared by "Reset AI emphasis".
    public var emphasisIsAI: Bool
    public var speaker: Int?
    public var isHidden: Bool

    public init(id: UUID = UUID(), text: String, start: Seconds, end: Seconds, isEmphasized: Bool = false,
                emphasisIsAI: Bool = false, speaker: Int? = nil, isHidden: Bool = false) {
        self.id = id
        self.text = text
        self.start = start
        self.end = end
        self.isEmphasized = isEmphasized
        self.emphasisIsAI = emphasisIsAI
        self.speaker = speaker
        self.isHidden = isHidden
    }
}

public struct CaptionTrack: Codable, Hashable, Sendable {
    public var sourceAssetID: UUID
    public var words: [CaptionWord]
    public var style: CaptionStyle
    public var isEnabled: Bool
    public var aiGenerated: Bool
    public var profanity: ProfanityMode
    public var showSpeakerLabels: Bool
    /// Per-speaker look (color, highlight, position) layered over `style`.
    public var speakerStyles: [Int: SpeakerCaptionStyle]
    /// Speaker names for labels ("Speaker 1" when unknown).
    public var speakerNames: [Int: String]

    public init(sourceAssetID: UUID, words: [CaptionWord], style: CaptionStyle = .bold, isEnabled: Bool = true,
                aiGenerated: Bool = false, profanity: ProfanityMode = .off, showSpeakerLabels: Bool = false) {
        self.sourceAssetID = sourceAssetID
        self.words = words.sorted { $0.start < $1.start }
        self.style = style
        self.isEnabled = isEnabled
        self.aiGenerated = aiGenerated
        self.profanity = profanity
        self.showSpeakerLabels = showSpeakerLabels
        self.speakerStyles = [:]
        self.speakerNames = [:]
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceAssetID = try c.decode(UUID.self, forKey: .sourceAssetID)
        words = c.decode([CaptionWord].self, forKey: .words, default: [])
        style = c.decode(CaptionStyle.self, forKey: .style, default: .bold)
        isEnabled = c.decode(Bool.self, forKey: .isEnabled, default: true)
        aiGenerated = c.decode(Bool.self, forKey: .aiGenerated, default: false)
        profanity = c.decode(ProfanityMode.self, forKey: .profanity, default: .off)
        showSpeakerLabels = c.decode(Bool.self, forKey: .showSpeakerLabels, default: false)
        speakerStyles = c.decode([Int: SpeakerCaptionStyle].self, forKey: .speakerStyles, default: [:])
        speakerNames = c.decode([Int: String].self, forKey: .speakerNames, default: [:])
    }

    /// Builds captions from a transcript range.
    public static func make(from transcript: Transcript, range: TimeRange, assetID: UUID, style: CaptionStyle,
                            emphasize: Bool, aiGenerated: Bool = true) -> CaptionTrack {
        var words = transcript.words(in: range).map {
            CaptionWord(text: $0.text, start: $0.start, end: $0.end, speaker: $0.speaker)
        }
        if emphasize {
            for i in EmphasisDetector.emphasisIndices(words.map(\.text)) {
                words[i].isEmphasized = true
                words[i].emphasisIsAI = true
            }
        }
        var track = CaptionTrack(sourceAssetID: assetID, words: words, style: style, aiGenerated: aiGenerated)
        for speaker in transcript.speakers { track.speakerNames[speaker.id] = speaker.name }
        return track
    }

    public mutating func setWordText(id: UUID, text: String) {
        guard let i = words.firstIndex(where: { $0.id == id }) else { return }
        let parts = text.split(separator: " ").map(String.init)
        if parts.count <= 1 {
            words[i].text = text.trimmingCharacters(in: .whitespaces)
            if words[i].text.isEmpty { words[i].isHidden = true }
        } else {
            // Typing several words into one caption word splits its timing proportionally.
            let original = words[i]
            let pieces = TranscriptParser.distribute(text: text, over: TimeRange(start: original.start, end: original.end), speaker: original.speaker)
            let replacements = pieces.map { CaptionWord(text: $0.text, start: $0.start, end: $0.end, isEmphasized: original.isEmphasized, speaker: $0.speaker) }
            words.replaceSubrange(i...i, with: replacements)
        }
    }

    public mutating func toggleEmphasis(id: UUID) {
        guard let i = words.firstIndex(where: { $0.id == id }) else { return }
        words[i].isEmphasized.toggle()
        words[i].emphasisIsAI = false
    }

    public mutating func resetAIEmphasis() {
        for i in words.indices where words[i].emphasisIsAI {
            words[i].isEmphasized = false
            words[i].emphasisIsAI = false
        }
    }

    public mutating func applyAIEmphasis() {
        resetAIEmphasis()
        for i in EmphasisDetector.emphasisIndices(words.map(\.text)) where !words[i].isEmphasized {
            words[i].isEmphasized = true
            words[i].emphasisIsAI = true
        }
    }

    /// Plain text for export / search.
    public var text: String { words.filter { !$0.isHidden }.map(\.text).joined(separator: " ") }
}

/// Picks words worth emphasising ("I literally FELL OFF THE MAP").
public enum EmphasisDetector {
    static let stopwords: Set<String> = ["the", "a", "an", "and", "or", "but", "to", "of", "in", "on", "at", "for", "with", "is", "are", "was",
                                         "were", "be", "it", "that", "this", "i", "you", "he", "she", "we", "they", "me", "my", "your", "so",
                                         "just", "like", "um", "uh", "do", "did", "have", "has", "had", "not", "if", "then", "there", "what"]

    public static func score(_ text: String) -> Double {
        let n = TranscriptWord.normalize(text)
        guard !n.isEmpty, !stopwords.contains(n) else { return 0 }
        var s = Double(EngagementLexicon.words[n] ?? 0)
        if text.hasSuffix("!") { s += 0.8 }
        if text.count > 2, text == text.uppercased(), text.rangeOfCharacter(from: .letters) != nil { s += 0.6 }
        if n.rangeOfCharacter(from: .decimalDigits) != nil { s += 0.5 }
        if n.count >= 6 { s += 0.25 }
        return s
    }

    /// At most ~1 emphasised word per 5 words, highest scores first.
    public static func emphasisIndices(_ words: [String], density: Double = 0.2, minimumScore: Double = 0.7) -> [Int] {
        let scored = words.enumerated().map { ($0.offset, score($0.element)) }.filter { $0.1 >= minimumScore }
        let budget = max(1, Int((Double(words.count) * density).rounded()))
        var chosen: [Int] = []
        for (i, _) in scored.sorted(by: { $0.1 > $1.1 }) {
            if chosen.count >= budget { break }
            if chosen.contains(where: { abs($0 - i) < 3 }) { continue }
            chosen.append(i)
        }
        return chosen.sorted()
    }
}
