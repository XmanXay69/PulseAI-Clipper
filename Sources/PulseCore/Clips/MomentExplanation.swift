import Foundation

/// "Why this moment?": the signals behind a clip's score, as numbers for a popover and as a plain-words line
/// for the card ("big laugh + chat spike") (#49, #50).
public struct MomentExplanation: Hashable, Sendable {
    public struct Signal: Hashable, Sendable, Identifiable {
        public var id: String { name }
        public var name: String
        /// 0…1
        public var value: Double
        public var detail: String
    }

    public var signals: [Signal]
    public var summary: String

    public static func explain(candidate: ClipCandidate, analysis: MediaAnalysis) -> MomentExplanation {
        explain(candidate: candidate, signals: EngagementModel.compute(analysis: analysis), banners: analysis.hudEvents ?? [])
    }

    public static func explain(candidate: ClipCandidate, signals s: EngagementSignals, banners: [HUDEvent]) -> MomentExplanation {
        let range = candidate.range
        let near = TimeRange(start: max(range.start, candidate.payoffTime - 4), end: min(range.end, candidate.payoffTime + 4))
        guard s.count > 0 else { return MomentExplanation(signals: [], summary: "steady energy") }

        var out: [(Signal, String)] = []   // signal + the plain words for the summary
        func add(_ name: String, _ value: Double, _ detail: String, _ words: String) {
            let v = value.clamped(0, 1)
            if v >= 0.2 { out.append((Signal(name: name, value: v, detail: detail), words)) }
        }
        let laughs = Double(s.sum(s.laughter, in: range))
        add("Laughter", laughs / 3, laughs >= 1 ? String(format: "%.0f laugh%@ in the clip", laughs, laughs >= 2 ? "s" : "") : "a chuckle",
            laughs >= 2.5 ? "big laugh" : "a laugh")
        let chat = s.chat.count == s.count ? Double(s.max(s.chat, in: range)) : 0   // empty when no chat replay was imported
        add("Chat", chat, "chat burst at the payoff", chat >= 0.7 ? "chat went off" : "chat spike")
        let loud = Double(s.max(s.loudness, in: near)) / 4
        add("Loudness", loud, "voice well above its usual level", loud >= 0.75 ? "a shout" : "raised voice")
        let surprise = Double(s.max(s.surprise, in: near)) / 12
        add("Surprise", surprise, "a sudden jump in volume", "a sudden spike")
        let scream = s.shouts.count == s.count ? Double(s.max(s.shouts, in: near)) : 0
        add("Scream", scream, "a scream or shout while talking", "a scream")
        let keywords = Double(s.sum(s.keywords, in: range)) / 2.5
        add("Hype words", keywords, "words like insane, no way, let's go", "hype words")
        let motion = Double(s.max(s.motion, in: near)) / 3
        add("Action", motion, "a lot happening on screen", "action on screen")
        let rate = Double(s.max(s.speechRate, in: range)) / 3
        add("Fast talking", rate * 0.8, "words tumbling out", "fast talking")
        let rage = Double(s.sum(s.profanity, in: range))
        add("Rage", rage / 3, "swearing under pressure", "rage")
        if let banner = banners.filter({ $0.kind.weight > 0 && range.contains($0.time) }).max(by: { $0.kind.weight < $1.kind.weight }) {
            add("Game banner", banner.kind.weight, banner.text.capitalized, banner.kind == .marked ? "you marked it" : "a \(banner.kind.displayName.lowercased()) banner")
        }
        if candidate.scores.story >= 0.7 { add("Story", candidate.scores.story, "a story with a beginning and an end", "a story beat") }
        if candidate.scores.ending >= 0.7 { add("Ending", candidate.scores.ending, "lands cleanly after the payoff", "a clean ending") }

        // Strongest first; on a tie the game's own banner beats inferred signals, and laughter beats the rest.
        func priority(_ name: String) -> Int { name == "Game banner" ? 2 : name == "Laughter" ? 1 : 0 }
        let sorted = out.sorted { a, b in
            abs(a.0.value - b.0.value) > 1e-9 ? a.0.value > b.0.value : priority(a.0.name) > priority(b.0.name)
        }
        let top = sorted.prefix(3).filter { $0.0.value >= 0.3 }
        let summary = top.isEmpty ? "steady energy" : top.map(\.1).joined(separator: " + ")
        return MomentExplanation(signals: sorted.map(\.0), summary: summary)
    }
}
