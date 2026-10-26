import Foundation

/// Three YouTube title options and a description (chapters + hashtags) for a long-form edit (#94). Titles are
/// sentence case and under 70 characters; nothing is ever posted.
public enum YouTubeCopy {
    static let templates: [ClipTag: [String]] = [
        .funny: ["I could not stop laughing at this", "This stream got out of hand"],
        .hype: ["We actually pulled this off", "The best moments of the stream"],
        .highEnergy: ["This stream went crazy", "Everything happened at once"],
        .fail: ["It all went wrong", "I really thought that would work"],
        .reaction: ["I was not ready for this", "You need to see this"],
        .story: ["The full story", "Story time: how it really went"],
        .rage: ["This game broke me", "I lost it on stream"],
        .gaming: ["The plays that made the stream", "Full stream highlights"],
        .conversation: ["Let's talk about it", "The conversation that got out of hand"],
        .question: ["Nobody could answer this", "Wait, is this true?"],
        .emotional: ["This one hit different", "An emotional stream"],
    ]

    public static func generate(segments: [LongFormSegment], transcript: Transcript?, hookPayoff: Seconds?, chapters: String,
                                seed: Int = 0) -> ClipCopy {
        let ranked = segments.sorted { $0.potential > $1.potential }
        var titles: [String] = []
        // 1. The best quote near the hook (or the best moment), as a sentence.
        if let transcript, let payoff = hookPayoff ?? ranked.first?.payoff {
            let around = TimeRange(start: payoff - 12, end: payoff + 8)
            if let quote = TitleGenerator.bestQuote(words: Array(transcript.words(in: around)), payoff: payoff) {
                titles.append(sentenceCase(quote))
            }
        }
        // 2. A line for the stream's dominant mood.
        var counts: [ClipTag: Int] = [:]
        for s in segments { for t in s.tags { counts[t, default: 0] += 1 } }
        let moods = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue }.map(\.key)
        var rng = SeededGenerator(seed: UInt64(truncatingIfNeeded: seed &* 1_103_515_245 &+ 12_345))
        for mood in moods {
            guard let pool = templates[mood], let pick = pool.shuffled(using: &rng).first, !titles.contains(pick) else { continue }
            titles.append(pick)
            if titles.count >= 2 { break }
        }
        // 3. A count line.
        let count = segments.count
        titles.append(count >= 3 ? "\(count) moments from today's stream" : "Today's stream, cut down")
        var seen = Set<String>()
        titles = titles.map { String($0.prefix(70)) }.filter { seen.insert($0.lowercased()).inserted }
        let hashtags = Array(Set(moods.prefix(3).map(\.hashtag) + ["#stream", "#highlights"])).sorted()
        let description = chapters + "\n\n" + hashtags.joined(separator: " ")
        return ClipCopy(titles: Array(titles.prefix(3)), shortsTitle: titles.first ?? "", tiktokCaption: description,
                        instagramCaption: description, hashtags: hashtags)
    }

    static func sentenceCase(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        return String(first).uppercased() + trimmed.dropFirst().lowercased()
    }
}
