import Foundation

/// Names for speakers from how people are introduced (#40): "this is Mark", "here's Sarah", "joined by Dan" —
/// the next voice to start after the introduction gets the name. A suggestion only; nothing is applied.
public enum SpeakerNameSuggester {
    static let introductions: [[String]] = [
        ["this", "is"], ["here's"], ["here", "is"], ["joined", "by"], ["with", "me"], ["welcome"], ["say", "hi", "to"],
        ["my", "guest"], ["introducing"], ["please", "welcome"], ["i'm", "here", "with"], ["we", "have"], ["it's"],
    ]
    static let notNames: Set<String> = ["the", "a", "an", "my", "our", "your", "me", "you", "it", "that", "this", "here", "back", "today",
                                        "everyone", "everybody", "guys", "chat", "live", "going", "gonna", "so", "all", "right", "okay",
                                        "stream", "streaming", "time", "now", "just", "again", "him", "her", "them", "one", "us"]

    /// Speaker id → suggested name. Needs speaker labels on the words.
    public static func suggest(words: [TranscriptWord], window: Seconds = 20) -> [Int: String] {
        guard words.contains(where: { $0.speaker != nil }) else { return [:] }
        var names: [Int: String] = [:]
        var taken = Set<String>()
        let normalized = words.map(\.normalized)
        for i in words.indices {
            for pattern in introductions where i + pattern.count < words.count {
                guard (0..<pattern.count).allSatisfy({ normalized[i + $0] == pattern[$0] }) else { continue }
                let nameWord = words[i + pattern.count]
                let raw = nameWord.text.trimmingCharacters(in: .punctuationCharacters)
                guard raw.count >= 2, raw.first?.isUppercase == true, !notNames.contains(raw.lowercased()), raw.allSatisfy({ $0.isLetter || $0 == "-" }) else { continue }
                let introducer = words[i].speaker
                // The next voice that isn't the introducer, within the window.
                guard let next = words[(i + pattern.count)...].first(where: { $0.start <= nameWord.end + window && $0.speaker != nil && $0.speaker != introducer }),
                      let speaker = next.speaker, names[speaker] == nil, !taken.contains(raw) else { continue }
                names[speaker] = raw
                taken.insert(raw)
            }
        }
        return names
    }
}
