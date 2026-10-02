import Foundation

/// What *you* find entertaining, learned from 👍 / 👎 on clips and moments. A small logistic model on
/// top of PULSE's own scores: each rating nudges how much the hook, energy, laughs, reactions, story…
/// and each tag (Funny, Hype, Rage…) count for you. It never replaces the base score — it shifts it by up
/// to ±25 points, and only after a few ratings.
public struct TasteProfile: Codable, Hashable, Sendable {
    /// Weight per ClipScores dimension (same order as `ClipScores.breakdown`).
    public var dimensionWeights: [String: Double]
    public var tagWeights: [String: Double]
    public var bias: Double
    public var likes: Int
    public var dislikes: Int

    public init() {
        dimensionWeights = [:]
        tagWeights = [:]
        bias = 0
        likes = 0
        dislikes = 0
    }

    public var ratings: Int { likes + dislikes }
    /// Grows from 0 to 1 over the first ~12 ratings so one rating can't swing everything.
    public var confidence: Double { min(1, Double(ratings) / 12) }
    public var isEmpty: Bool { ratings == 0 }

    static let learningRate = 0.6
    static let decay = 0.01

    func logit(scores: ClipScores, tags: [ClipTag]) -> Double {
        var z = bias
        for (name, value) in scores.breakdown { z += (dimensionWeights[name] ?? 0) * (value - 0.5) }
        for tag in tags { z += tagWeights[tag.rawValue] ?? 0 }
        return z
    }

    /// Learns from one rating.
    public mutating func learn(scores: ClipScores, tags: [ClipTag], liked: Bool) {
        let p = 1 / (1 + exp(-logit(scores: scores, tags: tags)))
        let error = (liked ? 1.0 : 0.0) - p
        let lr = Self.learningRate
        for (name, value) in scores.breakdown {
            let w = dimensionWeights[name] ?? 0
            dimensionWeights[name] = (w + lr * error * (value - 0.5) * 2) * (1 - Self.decay)
        }
        for tag in tags {
            let w = tagWeights[tag.rawValue] ?? 0
            tagWeights[tag.rawValue] = (w + lr * error * 0.8) * (1 - Self.decay)
        }
        bias = (bias + lr * error * 0.1) * (1 - Self.decay)
        if liked { likes += 1 } else { dislikes += 1 }
    }

    /// Undoes the counting of a rating that's being changed (weights keep their learning; it's a nudge).
    public mutating func forget(liked: Bool) {
        if liked { likes = max(0, likes - 1) } else { dislikes = max(0, dislikes - 1) }
    }

    /// The base AI Potential shifted toward your taste (±25 at full confidence).
    public func adjusted(_ potential: Int, scores: ClipScores, tags: [ClipTag]) -> Int {
        guard !isEmpty else { return potential }
        let shift = tanh(logit(scores: scores, tags: tags) - bias) * 25 * confidence
        return Int((Double(potential) + shift).rounded()).clamped(1, 99)
    }

    public func adjusted(_ candidate: ClipCandidate) -> Int {
        adjusted(candidate.basePotential ?? candidate.potential, scores: candidate.scores, tags: candidate.tags)
    }

    /// Plain-language summary of what it has learned ("You like: Funny, Reaction · Less: Story").
    public var summary: String {
        guard ratings >= 3 else { return ratings == 0 ? "Rate clips 👍 / 👎 and PULSE learns what you like." : "Learning — rate a few more clips." }
        var items: [(String, Double)] = tagWeights.compactMap { key, w in ClipTag(rawValue: key).map { ($0.displayName, w) } }
        items += dimensionWeights.map { ($0.key, $0.value) }
        let likesList = items.filter { $0.1 > 0.25 }.sorted { $0.1 > $1.1 }.prefix(3).map(\.0)
        let lessList = items.filter { $0.1 < -0.25 }.sorted { $0.1 < $1.1 }.prefix(2).map(\.0)
        var parts: [String] = []
        if !likesList.isEmpty { parts.append("You like: " + likesList.joined(separator: ", ")) }
        if !lessList.isEmpty { parts.append("Less: " + lessList.joined(separator: ", ")) }
        return parts.isEmpty ? "Learned from \(ratings) ratings." : parts.joined(separator: " · ")
    }
}

extension Array where Element == ClipCandidate {
    /// Re-scores candidates with a taste profile (keeping the original AI score in `basePotential`).
    public func applyingTaste(_ taste: TasteProfile) -> [ClipCandidate] {
        map { c in
            var copy = c
            if copy.basePotential == nil { copy.basePotential = c.potential }
            copy.potential = taste.adjusted(copy)
            return copy
        }
    }
}
