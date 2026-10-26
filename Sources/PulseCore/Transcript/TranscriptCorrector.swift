import Foundation

/// Fixes the words speech-to-text gets wrong on purpose-built names — "valerant" → "Valorant", "x q c" → "xQc",
/// "sea of theives" → "Sea of Thieves" — from the vocabulary in Settings, keeping every word's timing (#43).
public enum TranscriptCorrector {
    public struct Result: Sendable {
        public var transcript: Transcript
        public var changes: Int
    }

    /// Letters and digits only, lower-cased: the shape of a word that survives mishearing and punctuation.
    static func key(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// Trailing punctuation of a recognised word, kept on the corrected one.
    static func trailingPunctuation(_ text: String) -> String {
        String(text.reversed().prefix { !$0.isLetter && !$0.isNumber }.reversed())
    }

    /// How many edits a misheard version of a term may be away from it: none for short terms, one per
    /// five letters beyond that.
    static func tolerance(for key: String) -> Int { key.count / 5 }

    public static func correct(_ transcript: Transcript, vocabulary: [String]) -> Result {
        let terms = vocabulary.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            .map { (term: $0, key: key($0), pieces: $0.split(separator: " ").count) }
            .filter { $0.key.count >= 3 }
        guard !terms.isEmpty, !transcript.words.isEmpty else { return Result(transcript: transcript, changes: 0) }
        var words = transcript.words
        var changes = 0
        var i = 0
        while i < words.count {
            var replaced = false
            // Longest windows first so "sea of thieves" beats "thieves"; a window may span up to four words.
            for size in stride(from: Swift.min(4, words.count - i), through: 1, by: -1) {
                let window = words[i..<(i + size)]
                let joined = window.map { key($0.text) }.joined()
                guard !joined.isEmpty else { continue }
                for term in terms {
                    // A multi-word term only matches a run of words; a one-word term also matches letters spelled out.
                    if term.pieces > 1 && size < term.pieces { continue }
                    guard joined != term.key || window.count > 1 || window.first!.text != term.term else {
                        if joined == term.key && window.count == 1 && window.first!.text != term.term { break }
                        continue
                    }
                    let distance = joined == term.key ? 0 : Levenshtein.distance(joined, term.key)
                    let allowed = size == 1 && joined.count < 4 ? 0 : tolerance(for: term.key)
                    guard distance <= allowed, joined.first == term.key.first else { continue }
                    let first = window.first!, last = window.last!
                    let merged = TranscriptWord(text: term.term + trailingPunctuation(last.text), start: first.start, end: last.end,
                                                confidence: window.compactMap(\.confidence).min(), speaker: first.speaker)
                    words.replaceSubrange(i..<(i + size), with: [merged])
                    changes += 1
                    replaced = true
                    break
                }
                if replaced { break }
            }
            i += 1
        }
        var out = transcript
        out.words = words
        return Result(transcript: out, changes: changes)
    }
}

enum Levenshtein {
    static func distance(_ a: String, _ b: String) -> Int {
        let x = Array(a.unicodeScalars), y = Array(b.unicodeScalars)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var previous = Array(0...y.count)
        var current = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            current[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                current[j] = Swift.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[y.count]
    }
}
