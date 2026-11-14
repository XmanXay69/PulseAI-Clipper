import Foundation

/// The four beats a video people finish is built on (#581): what they set out to do, what got in the way,
/// what they tried, and how it ended.
public enum StoryBeat: String, CaseIterable, Codable, Sendable {
    case goal, obstacle, attempt, result

    public var displayName: String {
        switch self {
        case .goal: return "Goal"
        case .obstacle: return "Obstacle"
        case .attempt: return "Attempt"
        case .result: return "Result"
        }
    }

    public var symbolName: String {
        switch self {
        case .goal: return "flag"
        case .obstacle: return "exclamationmark.triangle"
        case .attempt: return "arrow.triangle.2.circlepath"
        case .result: return "flag.checkered"
        }
    }

    /// What to do about a video that has none of this beat.
    public var adviceWhenMissing: String {
        switch self {
        case .goal: return "Nothing says what you set out to do. Keep a moment that states it, or open with a title card that does: a viewer who knows the goal has a reason to see how it ends."
        case .obstacle: return "Nothing goes wrong. Without a setback there is no tension: keep a fail, a close call or the moment the plan falls apart."
        case .attempt: return "It jumps from the problem to the ending. Keep at least one try in between, so the ending is earned."
        case .result: return "There is no ending: no win, no loss, no last word. Keep how the final attempt turned out, even if it was a loss."
        }
    }
}

/// A set of moments read as a story: which beat each one is, the order that tells it, and what is missing.
public struct NarrativeArc: Hashable, Sendable {
    public struct Placement: Hashable, Sendable {
        public var momentID: UUID
        public var beat: StoryBeat
        /// 0…1: how sure the reading is.
        public var confidence: Double
        /// The words or signal that decided it ("“one more try”", "a win banner", "the strongest moment near the end").
        public var evidence: String
    }

    public var placements: [Placement]
    /// The moments in the order that tells the story: the goal first, the setbacks and tries as they happened,
    /// the result last.
    public var order: [UUID]
    public var missing: [StoryBeat]

    public func beat(of momentID: UUID) -> StoryBeat? { placements.first { $0.momentID == momentID }?.beat }

    public func count(_ beat: StoryBeat) -> Int { placements.filter { $0.beat == beat }.count }

    /// "A goal, 2 obstacles, 3 attempts and a result." or "2 obstacles and 3 attempts. Missing: a goal and a result."
    public var summary: String {
        func one(_ beat: StoryBeat) -> String { (beat == .obstacle || beat == .attempt ? "an " : "a ") + beat.displayName.lowercased() }
        let parts = StoryBeat.allCases.compactMap { beat -> String? in
            let n = count(beat)
            return n == 0 ? nil : (n == 1 ? one(beat) : "\(n) \(beat.displayName.lowercased())s")
        }
        let found = Self.list(parts)
        var text = found.isEmpty ? "No story beats found." : found.prefix(1).uppercased() + found.dropFirst() + "."
        if !missing.isEmpty { text += " Missing: " + Self.list(missing.map(one)) + "." }
        return text
    }

    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }
}

/// Reads the moments Edit My VOD picked as a story (#581). The reading uses what was said in each moment,
/// its tags and where in the stream it sits: nothing is sent anywhere.
public enum NarrativeArcBuilder {
    static let cues: [StoryBeat: [String]] = [
        .goal: ["going to", "gonna", "trying to", "try to", "need to", "want to", "have to", "today we", "today i", "the plan", "the goal",
                "challenge", "about to", "let's see if", "can we", "can i", "i bet", "the rule", "we're doing", "attempting"],
        .obstacle: ["oh no", "no no", "why", "can't", "cannot", "stuck", "died", "dead", "lost", "failed", "missed", "wrong", "problem",
                    "impossible", "so hard", "what happened", "broke", "broken", "unlucky", "are you kidding", "how did", "ruined", "back to the start"],
        .attempt: ["again", "one more", "this time", "retry", "almost", "so close", "come on", "okay okay", "here we go", "let me try",
                   "another go", "next try", "run it back", "let's try", "second try", "third try", "attempt"],
        .result: ["we did it", "did it", "finally", "we won", "i won", "victory", "gg", "that's it", "it worked", "no way", "let's go",
                  "we made it", "done", "it's over", "i give up", "we lost", "that's the run", "new record", "first try"],
    ]

    static let tagBeats: [ClipTag: [StoryBeat: Double]] = [
        .fail: [.obstacle: 0.5], .rage: [.obstacle: 0.45], .hype: [.result: 0.3, .attempt: 0.15], .highEnergy: [.attempt: 0.2, .result: 0.15],
        .story: [.goal: 0.25], .question: [.goal: 0.2], .emotional: [.result: 0.2], .funny: [.obstacle: 0.15], .reaction: [.attempt: 0.1],
        .conversation: [.goal: 0.1], .gaming: [.attempt: 0.1],
    ]

    /// `moments` are the ones to tell the story with (in source time); `duration` is the recording's.
    public static func build(moments: [LongFormSegment], transcript: Transcript?, duration: Seconds) -> NarrativeArc {
        guard !moments.isEmpty else { return NarrativeArc(placements: [], order: [], missing: StoryBeat.allCases) }
        let chronological = moments.sorted { $0.range.start < $1.range.start }
        let span = max(duration, chronological.last?.range.end ?? 1, 1)
        let strongest = moments.map(\.potential).max() ?? 0
        var placements: [NarrativeArc.Placement] = []
        for moment in chronological {
            let position = moment.range.start / span
            let text = spoken(in: moment.range, transcript: transcript)
            var scores: [StoryBeat: Double] = [:]
            var evidence: [StoryBeat: String] = [:]
            for beat in StoryBeat.allCases {
                // What was said.
                let hits = (cues[beat] ?? []).filter { text.contains($0) }
                var score = min(0.6, Double(hits.count) * 0.3)
                if let first = hits.first { evidence[beat] = "“\(first)”" }
                // What kind of moment it is.
                for tag in moment.tags {
                    if let weight = tagBeats[tag]?[beat] {
                        score += weight
                        if evidence[beat] == nil { evidence[beat] = "a \(tag.displayName.lowercased()) moment" }
                    }
                }
                scores[beat] = score
            }
            // Where it sits: goals are stated early, results come late, and the strongest late moment is the ending.
            scores[.goal, default: 0] += max(0, 0.3 - position) * 1.2
            if position < 0.12, evidence[.goal] == nil { evidence[.goal] = "it comes at the very start" }
            scores[.result, default: 0] += max(0, position - 0.6) * 0.9
            if moment.potential == strongest, position > 0.5 {
                scores[.result, default: 0] += 0.25
                if evidence[.result] == nil { evidence[.result] = "the strongest moment near the end" }
            }
            scores[.attempt, default: 0] += position > 0.15 && position < 0.85 ? 0.12 : 0
            let ranked = scores.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue }
            let (beat, top) = (ranked[0].key, ranked[0].value)
            let margin = top - (ranked.count > 1 ? ranked[1].value : 0)
            let confidence = max(0.1, min(1, top * 0.7 + margin * 0.6))
            placements.append(NarrativeArc.Placement(momentID: moment.id, beat: beat, confidence: confidence,
                                                     evidence: evidence[beat] ?? "where it sits in the stream"))
        }
        // A beat counts as there when at least one moment reads as it with some confidence.
        let missing = StoryBeat.allCases.filter { beat in !placements.contains { $0.beat == beat && $0.confidence >= 0.25 } }
        // The order: goals as they were stated, then everything that happened on the way in stream order, then
        // the results with the strongest one last.
        let byID = Dictionary(moments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func ids(_ beats: Set<StoryBeat>) -> [UUID] { placements.filter { beats.contains($0.beat) }.map(\.momentID) }
        var results = ids([.result])
        if let finale = results.max(by: { (byID[$0]?.potential ?? 0) < (byID[$1]?.potential ?? 0) }), results.count > 1 {
            results.removeAll { $0 == finale }
            results.append(finale)
        }
        let order = ids([.goal]) + ids([.obstacle, .attempt]) + results
        return NarrativeArc(placements: placements, order: order, missing: missing)
    }

    /// The words inside `range`, lower-cased and joined, with the punctuation gone.
    static func spoken(in range: TimeRange, transcript: Transcript?) -> String {
        guard let words = transcript?.words, !words.isEmpty else { return "" }
        return " " + words.filter { $0.start < range.end && $0.end > range.start }
            .map { TranscriptWord.normalize($0.text) }.filter { !$0.isEmpty }.joined(separator: " ") + " "
    }
}
