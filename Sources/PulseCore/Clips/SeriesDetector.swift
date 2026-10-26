import Foundation

/// Running bits (#66): moments that reference each other — a callback joke, a story told in parts — get
/// "Part 1/2" labels so you post them as a series. The link is lexical: the moments share rare words, or the
/// later one calls back ("remember when", "like I said", "again").
public enum SeriesDetector {
    static let callbacks = ["remember when", "like i said", "as i said", "last time", "earlier", "again", "part two", "part 2",
                            "the sequel", "round two", "round 2", "told you", "same thing"]
    static let stop: Set<String> = ["this", "that", "with", "have", "what", "they", "them", "then", "there", "their", "were", "will",
                                    "would", "could", "should", "about", "just", "like", "yeah", "okay", "right", "going", "gonna",
                                    "really", "thing", "things", "because", "being", "been", "from", "into", "some", "more", "when",
                                    "where", "which", "while", "your", "you're", "it's", "that's", "don't", "can't", "didn't", "doesn't",
                                    "know", "think", "want", "here", "come", "came", "back", "over", "down", "much", "very", "also",
                                    "something", "everything", "nothing", "anything", "people", "time", "good", "well", "mean", "guys",
                                    "chat", "stream", "game", "play", "played", "playing", "little", "actually", "literally", "wait",
                                    "look", "make", "made", "take", "took", "even", "still", "only", "again", "does", "those", "these",
                                    "other", "every", "never", "always", "maybe", "though", "around", "first", "last", "next", "than",
                                    "sure", "does", "done", "doing", "said", "says", "tell", "told", "need", "gotta", "wanna"]

    /// Groups of candidate ids in time order; only groups of two or more.
    public static func series(candidates: [ClipCandidate], words: [TranscriptWord], minimumGap: Seconds = 30, maxGroup: Int = 4) -> [[UUID]] {
        let ordered = candidates.filter { $0.status != .dismissed }.sorted { $0.range.start < $1.range.start }
        guard ordered.count >= 2 else { return [] }
        var bags: [Set<String>] = []
        var texts: [String] = []
        for c in ordered {
            let inside = words.filter { $0.start >= c.range.start - 1 && $0.end <= c.range.end + 1 }
            let normalized = inside.map(\.normalized)
            bags.append(Set(normalized.filter { $0.count >= 4 && !stop.contains($0) && $0.allSatisfy { $0.isLetter || $0 == "'" } }))
            texts.append(normalized.joined(separator: " "))
        }
        var frequency: [String: Int] = [:]
        for bag in bags { for w in bag { frequency[w, default: 0] += 1 } }
        let rareLimit = max(2, ordered.count / 3)
        var parent = Array(ordered.indices)
        func find(_ i: Int) -> Int { parent[i] == i ? i : { parent[i] = find(parent[i]); return parent[i] }() }
        for i in ordered.indices {
            for j in (i + 1)..<ordered.count {
                guard ordered[j].range.start - ordered[i].range.end >= minimumGap else { continue }
                let shared = bags[i].intersection(bags[j]).filter { frequency[$0, default: 0] <= rareLimit }
                let callsBack = callbacks.contains { texts[j].contains($0) }
                guard shared.count >= 2 || (shared.count >= 1 && callsBack) else { continue }
                let a = find(i), b = find(j)
                if a != b { parent[max(a, b)] = min(a, b) }
            }
        }
        var groups: [Int: [UUID]] = [:]
        for i in ordered.indices { groups[find(i), default: []].append(ordered[i].id) }
        var out: [[UUID]] = []
        for (_, ids) in groups.sorted(by: { $0.key < $1.key }) where ids.count >= 2 {
            var rest = ids
            while rest.count >= 2 {
                out.append(Array(rest.prefix(maxGroup)))
                rest.removeFirst(min(maxGroup, rest.count))
            }
        }
        return out
    }

    /// "Part 1/2" per candidate id.
    public static func partLabels(_ groups: [[UUID]]) -> [UUID: String] {
        var labels: [UUID: String] = [:]
        for group in groups { for (i, id) in group.enumerated() { labels[id] = "Part \(i + 1)/\(group.count)" } }
        return labels
    }
}
