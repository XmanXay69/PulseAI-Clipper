import Foundation

/// Finds an ending that cuts cleanly back to the opening (#541). A short that loops without a seam is
/// watched again before the viewer notices it restarted, and every replay counts as watch time.
///
/// Three things make a seam clean: the cut falls between phrases rather than through a word, the sound at
/// the end sits at about the level the opening starts at, and the last words either leave a sentence open
/// for the opening to finish or come back to where the short began.
public enum LoopBuilder {
    public struct Word: Hashable, Sendable {
        public var text: String
        public var start: Seconds
        public var end: Seconds

        public init(_ text: String, start: Seconds, end: Seconds) {
            self.text = text
            self.start = start
            self.end = end
        }
    }

    public struct Loop: Hashable, Sendable {
        /// Where the short should end, in timeline seconds.
        public var end: Seconds
        /// How much comes off the current ending.
        public var trim: Seconds
        /// 0…1: how cleanly this ending joins the opening.
        public var quality: Double
        /// The same measure for the ending the short has now.
        public var currentQuality: Double
        /// Why this point, in words.
        public var reason: String

        /// Worth suggesting: a real trim to a clearly cleaner seam.
        public var isWorthOffering: Bool { trim >= 0.3 && quality >= 0.55 && quality - currentQuality >= 0.1 }
    }

    /// Words a sentence can be left hanging on, for the opening to finish.
    static let openEndings: Set<String> = ["and", "so", "because", "but", "then", "when", "until", "if", "or", "while", "which", "that", "to", "the"]

    /// `words` and `level` (loudness in dB at a timeline time) are in timeline time. Endings are looked for in
    /// the last part of the short only, never before `keepUntil` (the payoff must stay) and never cutting more
    /// than `1 − minimumKept` of it.
    public static func find(duration: Seconds, words: [Word], level: (Seconds) -> Double, keepUntil: Seconds? = nil,
                            minimumKept: Double = 0.7) -> Loop? {
        guard duration >= 5 else { return nil }
        let earliest = max(duration * minimumKept, (keepUntil ?? 0) + 1, 4)
        guard earliest < duration else { return nil }
        let opening = level(0.15)
        let openingWords = words.filter { $0.start < 3 }.map { TranscriptWord.normalize($0.text) }.filter { $0.count > 3 }

        func quality(at time: Seconds, lastWord index: Int?) -> (score: Double, reason: String) {
            // Sound: the end sits near the level the opening starts at, and the cut isn't on a loud instant.
            let atCut = level(max(0, time - 0.12))
            var score = 0.4 * (1 - min(1, abs(atCut - opening) / 18))
            var reasons: [String] = []
            if abs(atCut - opening) <= 6 { reasons.append("the sound at the cut matches the opening") }
            guard let index else { return (score + 0.1, reasons.first ?? "it ends between sounds") }
            let word = words[index]
            let next = index + 1 < words.count ? words[index + 1] : nil
            let gap = (next?.start ?? duration) - word.end
            let text = word.text
            let normal = TranscriptWord.normalize(text)
            // Sense: between phrases at least; better, hanging for the opening to finish, or back where it began.
            if gap >= 0.15 || next == nil { score += 0.15 }
            if text.hasSuffix("?") {
                score += 0.25
                reasons.insert("it ends on a question the opening answers", at: 0)
            } else if openEndings.contains(normal) {
                score += 0.3
                reasons.insert("it ends on “…\(normal)”, which the opening finishes", at: 0)
            } else if text.hasSuffix(".") || text.hasSuffix("!") {
                score += 0.15
                reasons.append("it ends on a finished sentence")
            }
            // The last few seconds before the cut (never the opening itself, on a very short short).
            let closing = words[...index].filter { $0.start >= 3 && $0.end > time - 4 }.map { TranscriptWord.normalize($0.text) }
            if !openingWords.isEmpty, closing.contains(where: { openingWords.contains($0) }) {
                score += 0.15
                // Said after a hanging word or a question, which is the stronger reason when both hold.
                let strongest = reasons.first.map { $0.hasPrefix("it ends on a question") || $0.hasPrefix("it ends on “") } ?? false
                reasons.insert("it comes back to the words it opened with", at: strongest ? 1 : 0)
            }
            return (min(1, score), reasons.first ?? "it ends between phrases")
        }

        // The ending as it is.
        let lastSpoken = words.lastIndex { $0.end <= duration + 0.05 }
        let current = quality(at: duration, lastWord: lastSpoken.flatMap { duration - words[$0].end < 1.5 ? $0 : nil })

        var best: (time: Seconds, score: Double, reason: String)?
        for (i, word) in words.enumerated() where word.end >= earliest && word.end < duration - 0.25 {
            let next = i + 1 < words.count ? words[i + 1] : nil
            let gap = (next?.start ?? duration) - word.end
            // Only where a cut doesn't clip the next word: a breath, or the end of a sentence.
            let sentenceEnd = word.text.hasSuffix(".") || word.text.hasSuffix("!") || word.text.hasSuffix("?")
            guard gap >= 0.12 || sentenceEnd else { continue }
            let time = word.end + min(max(gap, 0) / 2, 0.12)
            var (score, reason) = quality(at: time, lastWord: i)
            // A shorter trim is preferred, all else equal.
            score -= 0.08 * (duration - time) / max(duration - earliest, 0.1)
            if score > (best?.score ?? -1) { best = (time, score, reason) }
        }
        guard let best else {
            return Loop(end: duration, trim: 0, quality: current.score, currentQuality: current.score, reason: current.reason)
        }
        if best.score <= current.score {
            return Loop(end: duration, trim: 0, quality: current.score, currentQuality: current.score, reason: current.reason)
        }
        return Loop(end: best.time, trim: duration - best.time, quality: max(0, min(1, best.score)), currentQuality: current.score,
                    reason: best.reason)
    }

    /// The loop for a short built from one recording: its words and loudness followed through the edit's cuts.
    public static func find(in timeline: Timeline, analysis: MediaAnalysis?, keepUntil: Seconds? = nil) -> Loop? {
        guard let analysis, EditFormat.of(timeline) == .short else { return nil }
        let program = EditCoach.Program(timeline: timeline, assetID: analysis.assetID)
        guard !program.segments.isEmpty else { return nil }
        var words: [Word] = []
        if let transcript = analysis.transcript {
            for clip in program.segments {
                let source = clip.sourceRange
                for word in transcript.words where word.start < source.end && word.end > source.start {
                    let middle = (word.start + word.end) / 2
                    guard source.contains(middle) else { continue }
                    words.append(Word(word.text, start: clip.timelineTime(atSource: max(word.start, source.start)),
                                      end: clip.timelineTime(atSource: min(word.end, source.end))))
                }
            }
            words.sort { $0.start < $1.start }
        }
        let audio = analysis.audio
        return find(duration: timeline.duration, words: words, level: { time in
            guard let audio, let source = program.sourceTime(at: min(max(time, 0), max(timeline.duration - 0.01, 0))) else { return -40 }
            return Double(audio.rms(at: source))
        }, keepUntil: keepUntil)
    }
}
