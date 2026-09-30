import Foundation

/// A detected filler word / phrase / stutter.
public struct FillerDetection: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable, Codable {
        case hesitation   // um, uh, er
        case filler       // like, you know, basically
        case repetition   // "I I I think"

        public var displayName: String {
            switch self {
            case .hesitation: return "Hesitation"
            case .filler: return "Filler"
            case .repetition: return "Repeated word"
            }
        }
    }

    public var id: Int { firstWord }
    public var firstWord: Int
    public var lastWord: Int
    public var range: TimeRange
    public var text: String
    public var kind: Kind
    /// 0…1 — how sure we are it's disposable. "um" is near-certain, "like" is ambiguous.
    public var confidence: Double
}

/// Detects filler words. Nothing is removed automatically — the user decides per detection.
public enum FillerWordDetector {
    static let hesitations: Set<String> = ["um", "umm", "uh", "uhh", "uhm", "er", "erm", "ah", "hmm", "mm", "eh"]
    static let singleFillers: [String: Double] = ["like": 0.45, "basically": 0.5, "literally": 0.3, "actually": 0.25, "so": 0.2, "right": 0.2, "okay": 0.2, "anyway": 0.3]
    static let phraseFillers: [[String]: Double] = [
        ["you", "know"]: 0.6, ["i", "mean"]: 0.5, ["kind", "of"]: 0.35, ["sort", "of"]: 0.35, ["you", "see"]: 0.4,
    ]
    /// Words that make "like" meaningful ("I like", "looks like", "feel like").
    static let likeKeepers: Set<String> = ["i", "you", "we", "they", "looks", "look", "looked", "feel", "feels", "felt", "would", "just", "seems", "sounds", "something", "anything", "nothing", "don't", "didn't", "do", "does"]

    public static func detect(in transcript: Transcript, range: TimeRange? = nil, minimumConfidence: Double = 0.3) -> [FillerDetection] {
        let words = transcript.words
        guard !words.isEmpty else { return [] }
        let indices: Range<Int> = range.map { transcript.wordIndices(in: $0) } ?? words.indices
        let norm = words.map(\.normalized)
        var results: [FillerDetection] = []
        var i = indices.lowerBound
        while i < indices.upperBound {
            let w = norm[i]
            // Hesitations.
            if hesitations.contains(w) {
                results.append(make(words, i, i, .hesitation, 0.95))
                i += 1
                continue
            }
            // Phrases.
            var matchedPhrase = false
            for (phrase, confidence) in phraseFillers where i + phrase.count <= indices.upperBound {
                if Array(norm[i..<(i + phrase.count)]) == phrase {
                    // "you know" at the end of a sentence/clause is filler; "do you know" is not.
                    let prev = i > 0 ? norm[i - 1] : ""
                    if phrase == ["you", "know"] && ["do", "did", "don't", "didn't", "if", "what"].contains(prev) { continue }
                    results.append(make(words, i, i + phrase.count - 1, .filler, confidence))
                    i += phrase.count
                    matchedPhrase = true
                    break
                }
            }
            if matchedPhrase { continue }
            // Single ambiguous fillers.
            if let base = singleFillers[w] {
                var confidence = base
                let prev = i > 0 ? norm[i - 1] : ""
                if w == "like" && likeKeepers.contains(prev) { confidence = 0.1 }
                // Surrounded by pauses → more likely a filler.
                let pauseBefore = i > 0 ? words[i].start - words[i - 1].end : 1
                let pauseAfter = i + 1 < words.count ? words[i + 1].start - words[i].end : 1
                if pauseBefore > 0.25 || pauseAfter > 0.25 { confidence += 0.2 }
                if words[i].text.hasSuffix(",") { confidence += 0.1 }
                if confidence >= minimumConfidence {
                    results.append(make(words, i, i, .filler, min(confidence, 0.9)))
                }
                i += 1
                continue
            }
            // Immediate repetitions ("I I", "the the"), excluding intentional ones ("no no no").
            if i + 1 < indices.upperBound, !w.isEmpty, norm[i + 1] == w, !["no", "yes", "go", "very", "really", "ha", "haha"].contains(w) {
                var j = i + 1
                while j + 1 < indices.upperBound, norm[j + 1] == w { j += 1 }
                // Keep the last occurrence, flag the earlier ones.
                results.append(make(words, i, j - 1, .repetition, 0.7))
                i = j + 1
                continue
            }
            i += 1
        }
        return results.filter { $0.confidence >= minimumConfidence }
    }

    static func make(_ words: [TranscriptWord], _ a: Int, _ b: Int, _ kind: FillerDetection.Kind, _ confidence: Double) -> FillerDetection {
        let text = words[a...b].map(\.text).joined(separator: " ")
        return FillerDetection(firstWord: a, lastWord: b, range: TimeRange(start: words[a].start, end: words[b].end), text: text, kind: kind, confidence: confidence)
    }

    /// Source ranges to cut for the chosen detections, extended slightly into surrounding
    /// silence so cuts land cleanly between words.
    public static func cutRanges(for detections: [FillerDetection], in transcript: Transcript, padding: Seconds = 0.04) -> [TimeRange] {
        detections.map { d in
            let prevEnd = d.firstWord > 0 ? transcript.words[d.firstWord - 1].end : d.range.start - padding
            let nextStart = d.lastWord + 1 < transcript.words.count ? transcript.words[d.lastWord + 1].start : d.range.end + padding
            let start = max(prevEnd, d.range.start - padding)
            let end = min(nextStart, d.range.end + padding)
            return TimeRange(start: start, end: end)
        }.merged()
    }
}
