import Foundation

/// Local, deterministic title + platform copy generator. Cloud `InsightProvider`s can replace it
/// with LLM-written copy when the user allows cloud AI.
public enum TitleGenerator {
    static let templates: [ClipTag: [String]] = [
        .funny: ["I CAN'T BREATHE 😭", "NAH THIS CANNOT BE REAL 😭", "WHY IS THIS SO FUNNY 💀", "I'M CRYING 😭"],
        .reaction: ["BRO WHAT JUST HAPPENED?!", "NO WAY HE JUST DID THAT", "I WAS NOT READY FOR THIS 😳", "WAIT FOR IT…"],
        .highEnergy: ["HE ACTUALLY DID IT", "THIS WAS INSANE 🔥", "THE CHAT WENT CRAZY"],
        .hype: ["LET'S GOOO 🔥", "HE ACTUALLY DID IT", "CLUTCH OF THE YEAR?!"],
        .fail: ["THE WORST DECISION OF MY LIFE", "HE REALLY THOUGHT THAT WOULD WORK 💀", "IT WENT SO WRONG"],
        .story: ["THIS STORY GETS WORSE 👀", "YOU WON'T BELIEVE THIS STORY", "STORY TIME 👀"],
        .rage: ["HE LOST IT 😤", "THIS GAME IS RIGGED", "I'M DONE WITH THIS GAME 😤"],
        .question: ["WAIT… IS THIS TRUE?", "NOBODY KNOWS THE ANSWER 🤔"],
        .gaming: ["THIS PLAY WAS DIFFERENT", "HOW DID THAT WORK?!"],
        .conversation: ["HE SAID WHAT?!", "THIS TAKE IS WILD"],
        .emotional: ["THIS HIT DIFFERENT 🥹"],
    ]

    static let stripWords: Set<String> = ["um", "uh", "uhh", "umm", "like", "so", "and", "but", "well", "okay", "ok", "yeah", "you", "know"]

    public static func generate(words: [TranscriptWord], payoff: Seconds, tags: [ClipTag], seed: Int) -> ClipCopy {
        var titles: [String] = []
        if let quote = bestQuote(words: words, payoff: payoff) {
            titles.append(quote + emojiSuffix(for: tags, seed: seed))
        }
        var rng = SeededGenerator(seed: UInt64(truncatingIfNeeded: seed &* 2_654_435_761 &+ 97))
        for tag in tags {
            guard var pool = templates[tag] else { continue }
            pool.shuffle(using: &rng)
            for t in pool.prefix(2) where !titles.contains(t) { titles.append(t) }
            if titles.count >= 5 { break }
        }
        if titles.isEmpty { titles = ["YOU NEED TO SEE THIS", "WAIT FOR IT…"] }
        titles = Array(titles.prefix(5))

        let hashtags = Array(Set(tags.map(\.hashtag) + ["#shorts", "#clips"])).sorted()
        let main = titles[0]
        let plain = main.trimmingCharacters(in: .whitespaces)
        let sentenceCase = plain.prefix(1).uppercased() + plain.dropFirst().lowercased()
        let shortsTitle = String((plain + " #shorts").prefix(100))
        let tiktok = sentenceCase + " " + hashtags.filter { $0 != "#shorts" }.prefix(4).joined(separator: " ")
        let instagram = sentenceCase + "\n\n" + hashtags.joined(separator: " ")
        return ClipCopy(titles: titles, shortsTitle: shortsTitle, tiktokCaption: tiktok, instagramCaption: instagram, hashtags: hashtags)
    }

    /// Picks the most quotable sentence near the payoff and turns it into a punchy title.
    static func bestQuote(words: [TranscriptWord], payoff: Seconds) -> String? {
        guard !words.isEmpty else { return nil }
        // Build sentences locally.
        var sentences: [[TranscriptWord]] = []
        var current: [TranscriptWord] = []
        for (i, w) in words.enumerated() {
            current.append(w)
            let next = i + 1 < words.count ? words[i + 1] : nil
            if w.endsSentence || next == nil || (next!.start - w.end) > 0.8 {
                sentences.append(current)
                current = []
            }
        }
        var best: (score: Double, text: [String])?
        for sentence in sentences {
            let content = sentence.map(\.text).filter { !stripWords.contains(TranscriptWord.normalize($0)) }
            guard content.count >= 2 else { continue }
            let start = sentence.first!.start
            let end = sentence.last!.end
            let distance = payoff < start ? start - payoff : (payoff > end ? payoff - end : 0)
            var score = 1.0 / (1.0 + distance / 3)
            let joined = sentence.map(\.normalized).joined(separator: " ")
            for (phrase, weight) in EngagementLexicon.phrases where joined.contains(phrase) { score += Double(weight) * 0.5 }
            for w in sentence.map(\.normalized) { score += Double(EngagementLexicon.words[w] ?? 0) * 0.2 }
            if sentence.last!.isExclamation { score += 0.4 }
            if sentence.last!.isQuestion { score += 0.3 }
            let n = content.count
            score *= n >= 3 && n <= 8 ? 1.2 : (n > 12 ? 0.6 : 0.9)
            if best == nil || score > best!.score { best = (score, content) }
        }
        guard let chosen = best?.text else { return nil }
        var tokens = Array(chosen.prefix(8))
        let endedWithQuestion = tokens.last?.hasSuffix("?") == true
        tokens = tokens.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",.;:…\"")) }
        var title = tokens.joined(separator: " ").uppercased()
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "!? "))
        if chosen.count > 8 { title += "…" } else { title += endedWithQuestion ? "?" : "!" }
        return title.isEmpty ? nil : "“\(title)”"
    }

    static func emojiSuffix(for tags: [ClipTag], seed: Int) -> String {
        guard let first = tags.first(where: { $0 != .gaming && $0 != .conversation }) else { return "" }
        return " " + first.emoji
    }

    /// Short transcript excerpt centred on the payoff for candidate cards.
    public static func snippet(words: [TranscriptWord], around payoff: Seconds, maxWords: Int = 18) -> String {
        guard !words.isEmpty else { return "" }
        let center = words.firstIndex { $0.end >= payoff } ?? words.count / 2
        let lo = max(0, center - maxWords / 2)
        let hi = min(words.count, lo + maxWords)
        var text = words[lo..<hi].map(\.text).joined(separator: " ")
        if lo > 0 { text = "…" + text }
        if hi < words.count { text += "…" }
        return text
    }
}

/// Deterministic PRNG (SplitMix64) so titles/regeneration are reproducible in tests.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    var state: UInt64

    public init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
