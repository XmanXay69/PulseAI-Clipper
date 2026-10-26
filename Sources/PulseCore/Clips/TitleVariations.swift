import Foundation

extension TitleGenerator {
    static let relatedTags: [ClipTag: [ClipTag]] = [
        .funny: [.reaction, .fail], .reaction: [.funny, .hype], .hype: [.highEnergy, .gaming], .highEnergy: [.hype, .gaming],
        .fail: [.funny, .rage], .rage: [.fail], .story: [.conversation, .emotional], .conversation: [.story, .question],
        .question: [.conversation], .gaming: [.hype], .emotional: [.story],
    ]

    /// More titles in the spirit of `title` (#60): a quote gets the next-best quotes from the same words, a
    /// template gets its siblings for the same and related tags. Never repeats `title` or anything in `avoiding`.
    public static func moreLike(_ title: String, words: [TranscriptWord], payoff: Seconds, tags: [ClipTag], seed: Int,
                                avoiding: [String] = [], count: Int = 3) -> [String] {
        let suffix = emojiSuffix(for: tags, seed: seed)
        let quotes = rankedQuotes(words: words, payoff: payoff).map { $0 + suffix }
        var rng = SeededGenerator(seed: UInt64(truncatingIfNeeded: seed &* 1_000_003 &+ 17))
        var family = tags.flatMap { templates[$0] ?? [] }
        family.shuffle(using: &rng)
        var related = tags.flatMap { relatedTags[$0] ?? [] }.flatMap { templates[$0] ?? [] }
        related.shuffle(using: &rng)
        let pool: [String]
        if title.hasPrefix("“") {
            pool = quotes + family + related
        } else {
            pool = family + related + Array(quotes.prefix(1)) + ["YOU NEED TO SEE THIS", "WAIT FOR IT…"]
        }
        let banned = Set([title] + avoiding)
        var out: [String] = []
        for t in pool where !banned.contains(t) && !out.contains(t) {
            out.append(t)
            if out.count == count { break }
        }
        return out
    }
}
