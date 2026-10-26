import Foundation

/// Hashtags from the moment's tags and the names said in it (#72): a game, a friend, a place that comes up
/// more than once becomes a tag you can edit on the card.
public enum Hashtags {
    static let notTags: Set<String> = ["i", "i'm", "i'll", "i've", "i'd", "ok", "okay", "yeah", "yes", "no", "oh", "chat", "bro", "dude",
                                       "man", "guys", "lol", "wait", "what", "god", "jesus", "nah", "yo", "hey", "hi", "bye", "the", "a"]

    public static func suggest(words: [TranscriptWord], tags: [ClipTag], limit: Int = 8) -> [String] {
        var out: [String] = []
        func add(_ h: String) {
            let t = h.lowercased()
            guard t.count > 1, !out.contains(t) else { return }
            out.append(t)
        }
        for tag in tags { add(tag.hashtag) }
        add("#shorts")
        var counts: [String: Int] = [:]
        for (i, w) in words.enumerated() {
            let raw = w.text.trimmingCharacters(in: .punctuationCharacters)
            guard raw.count >= 2, raw.first?.isUppercase == true, raw.allSatisfy({ $0.isLetter || $0.isNumber }) else { continue }
            let allCaps = raw == raw.uppercased() && raw.count <= 5
            let sentenceStart = i == 0 || words[i - 1].endsSentence
            // "The" at a sentence start isn't a name; "GG" anywhere is.
            if sentenceStart && !allCaps { continue }
            if raw.count < 3 && !allCaps { continue }
            let key = raw.lowercased()
            if notTags.contains(key) || SpeakerNameSuggester.notNames.contains(key) { continue }
            counts[key, default: 0] += 1
        }
        for (word, n) in counts.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }) where n >= 2 {
            add("#" + word)
            if out.count >= limit - 1 { break }
        }
        add("#clips")
        return Array(out.prefix(limit))
    }

    /// "#a #b" → ["#a", "#b"], cleaned (#72).
    public static func parse(_ text: String) -> [String] {
        var out: [String] = []
        for piece in text.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" }) {
            var t = piece.trimmingCharacters(in: .whitespaces).lowercased()
            if !t.hasPrefix("#") { t = "#" + t }
            t = "#" + t.dropFirst().filter { $0.isLetter || $0.isNumber || $0 == "_" }
            if t.count > 1, !out.contains(t) { out.append(t) }
        }
        return out
    }
}
