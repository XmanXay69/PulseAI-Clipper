import Foundation

/// A chapter of the story before it's built (#86): a run of moments, named from what they are.
public struct StoryChapter: Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var momentIDs: [UUID]

    public init(id: UUID = UUID(), name: String, momentIDs: [UUID]) {
        self.id = id
        self.name = name
        self.momentIDs = momentIDs
    }
}

public enum ChapterOutline {
    /// Three to five chapters from the kept moments in time order, split at the biggest jumps in the stream.
    /// Fewer when there aren't enough moments. Every kept moment lands in exactly one chapter.
    public static func propose(plan: LongFormPlan, words: [TranscriptWord] = [], minimum: Int = 3, maximum: Int = 5) -> [StoryChapter] {
        let kept = plan.moments.filter { plan.selected.contains($0.id) }.sorted { $0.range.start < $1.range.start }
        guard !kept.isEmpty else { return [] }
        let count = min(maximum, max(1, min(minimum, kept.count)), kept.count)
        let wanted = kept.count >= maximum * 2 ? maximum : (kept.count >= minimum ? max(minimum, min(maximum, kept.count / 2)) : count)
        // Split points: the largest gaps between consecutive moments (source time).
        var gaps: [(index: Int, gap: Seconds)] = []
        for i in 1..<kept.count { gaps.append((i, kept[i].range.start - kept[i - 1].range.end)) }
        let splits = Set(gaps.sorted { $0.gap > $1.gap }.prefix(max(0, wanted - 1)).map(\.index))
        var chapters: [[LongFormSegment]] = [[]]
        for (i, m) in kept.enumerated() {
            if splits.contains(i) { chapters.append([]) }
            chapters[chapters.count - 1].append(m)
        }
        var used = Set<String>()
        return chapters.enumerated().map { index, moments in
            var name = title(for: moments, words: words)
            if used.contains(name) { name += " \(index + 1)" }
            used.insert(name)
            return StoryChapter(name: name, momentIDs: moments.map(\.id))
        }
    }

    /// A short name from the strongest moment's own words, else from what the chapter mostly is.
    static func title(for moments: [LongFormSegment], words: [TranscriptWord]) -> String {
        guard let best = moments.max(by: { $0.potential < $1.potential }) else { return "Chapter" }
        if let phrase = RetentionCards.phrase(from: words, in: best) {
            let bare = phrase.trimmingCharacters(in: CharacterSet(charactersIn: "!?.…"))
            if !bare.isEmpty { return bare.capitalized }
        }
        var counts: [ClipTag: Int] = [:]
        for m in moments { for t in m.tags { counts[t, default: 0] += 1 } }
        let top = counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key.rawValue > $1.key.rawValue }?.key
        switch top {
        case .hype, .highEnergy, .gaming: return "The Big Plays"
        case .funny, .reaction: return "The Laughs"
        case .fail, .rage: return "It Goes Wrong"
        case .story, .emotional: return "Story Time"
        case .conversation, .question: return "Just Chatting"
        case nil: return "Chapter"
        }
    }
}
