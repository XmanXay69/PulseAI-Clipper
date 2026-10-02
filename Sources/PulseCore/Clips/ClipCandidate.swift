import Foundation

public enum ClipTag: String, Codable, CaseIterable, Sendable {
    case gaming
    case reaction
    case funny
    case highEnergy
    case story
    case question
    case rage
    case hype
    case fail
    case conversation
    case emotional

    public var displayName: String {
        switch self {
        case .gaming: return "Gaming"
        case .reaction: return "Reaction"
        case .funny: return "Funny"
        case .highEnergy: return "High Energy"
        case .story: return "Story"
        case .question: return "Question"
        case .rage: return "Rage"
        case .hype: return "Hype"
        case .fail: return "Fail"
        case .conversation: return "Conversation"
        case .emotional: return "Emotional"
        }
    }

    public var emoji: String {
        switch self {
        case .gaming: return "🎮"
        case .reaction: return "😳"
        case .funny: return "😭"
        case .highEnergy: return "🔥"
        case .story: return "👀"
        case .question: return "🤔"
        case .rage: return "😤"
        case .hype: return "🔥"
        case .fail: return "💀"
        case .conversation: return "💬"
        case .emotional: return "🥹"
        }
    }

    public var hashtag: String {
        switch self {
        case .gaming: return "#gaming"
        case .reaction: return "#reaction"
        case .funny: return "#funny"
        case .highEnergy: return "#hype"
        case .story: return "#storytime"
        case .question: return "#question"
        case .rage: return "#rage"
        case .hype: return "#hype"
        case .fail: return "#fail"
        case .conversation: return "#podcast"
        case .emotional: return "#wholesome"
        }
    }
}

/// Sub-scores behind the single "AI Potential" number (all 0…1).
public struct ClipScores: Codable, Hashable, Sendable {
    public var hook: Double
    public var emotion: Double
    public var story: Double
    public var entertainment: Double
    public var audio: Double
    public var visual: Double
    public var reaction: Double
    public var context: Double
    public var ending: Double

    public init(hook: Double = 0, emotion: Double = 0, story: Double = 0, entertainment: Double = 0, audio: Double = 0,
                visual: Double = 0, reaction: Double = 0, context: Double = 0, ending: Double = 0) {
        self.hook = hook
        self.emotion = emotion
        self.story = story
        self.entertainment = entertainment
        self.audio = audio
        self.visual = visual
        self.reaction = reaction
        self.context = context
        self.ending = ending
    }

    /// Named breakdown for the UI.
    public var breakdown: [(name: String, value: Double)] {
        [("Hook", hook), ("Emotion", emotion), ("Story", story), ("Entertainment", entertainment), ("Audio", audio),
         ("Visual", visual), ("Reaction", reaction), ("Context", context), ("Ending", ending)]
    }

    public var weighted: Double {
        let raw = 0.18 * hook + 0.18 * emotion + 0.11 * story + 0.13 * entertainment + 0.09 * audio +
            0.06 * visual + 0.11 * reaction + 0.07 * context + 0.07 * ending
        return raw.clamped(0, 1)
    }
}

/// Titles and platform copy generated for a clip. Nothing is ever posted automatically.
public struct ClipCopy: Codable, Hashable, Sendable {
    public var titles: [String]
    public var shortsTitle: String
    public var tiktokCaption: String
    public var instagramCaption: String
    public var hashtags: [String]
    public var generatedBy: String

    public init(titles: [String], shortsTitle: String, tiktokCaption: String, instagramCaption: String, hashtags: [String], generatedBy: String = "PULSE Local") {
        self.titles = titles
        self.shortsTitle = shortsTitle
        self.tiktokCaption = tiktokCaption
        self.instagramCaption = instagramCaption
        self.hashtags = hashtags
        self.generatedBy = generatedBy
    }

    public static let empty = ClipCopy(titles: [], shortsTitle: "", tiktokCaption: "", instagramCaption: "", hashtags: [])
}

public struct HookAdvice: Codable, Hashable, Sendable {
    public enum Recommendation: Codable, Hashable, Sendable {
        case keep
        case startEarlier(Seconds)
        case startLater(Seconds)
        /// Open with a short flash-forward of the payoff ("cold open").
        case coldOpen(payoffAt: Seconds)
    }

    public var strength: Double
    public var recommendation: Recommendation
    public var message: String
}

public enum CandidateStatus: String, Codable, Sendable {
    case new
    case opened
    case exported
    case dismissed
}

/// A proposed short cut from a long recording.
public struct ClipCandidate: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var assetID: UUID
    public var range: TimeRange
    /// Where the payoff / peak moment is (source time).
    public var payoffTime: Seconds
    public var targetDuration: Seconds
    /// 0…100 "AI Potential".
    public var potential: Int
    public var scores: ClipScores
    public var tags: [ClipTag]
    public var title: String
    public var copy: ClipCopy
    public var transcriptSnippet: String
    public var hook: HookAdvice?
    public var status: CandidateStatus
    public var timelineID: UUID?
    public var isFavorite: Bool
    public var createdAt: Date
    /// Bumped on every regenerate so title picks vary.
    public var generation: Int
    /// True after the user manually changed the range.
    public var userAdjusted: Bool
    /// The AI's own score before your taste profile adjusted `potential`.
    public var basePotential: Int?
    /// Your rating: +1 👍, -1 👎, nil = not rated.
    public var feedback: Int?

    public init(id: UUID = UUID(), assetID: UUID, range: TimeRange, payoffTime: Seconds, targetDuration: Seconds, potential: Int,
                scores: ClipScores, tags: [ClipTag], title: String, copy: ClipCopy, transcriptSnippet: String,
                hook: HookAdvice? = nil, status: CandidateStatus = .new, timelineID: UUID? = nil, isFavorite: Bool = false,
                createdAt: Date = Date(), generation: Int = 0, userAdjusted: Bool = false) {
        self.id = id
        self.assetID = assetID
        self.range = range
        self.payoffTime = payoffTime
        self.targetDuration = targetDuration
        self.potential = potential
        self.scores = scores
        self.tags = tags
        self.title = title
        self.copy = copy
        self.transcriptSnippet = transcriptSnippet
        self.hook = hook
        self.status = status
        self.timelineID = timelineID
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.generation = generation
        self.userAdjusted = userAdjusted
    }

    public var duration: Seconds { range.duration }

    public var potentialBand: PotentialBand { PotentialBand(potential) }
}

public enum PotentialBand: String, Sendable {
    case high, good, fair, low

    public init(_ potential: Int) {
        switch potential {
        case 80...: self = .high
        case 60..<80: self = .good
        case 40..<60: self = .fair
        default: self = .low
        }
    }

    public var displayName: String {
        switch self {
        case .high: return "High"
        case .good: return "Good"
        case .fair: return "Fair"
        case .low: return "Low"
        }
    }
}

public enum CandidateSort: String, CaseIterable, Sendable {
    case potential, duration, timestamp, newest, category

    public var displayName: String {
        switch self {
        case .potential: return "AI Potential"
        case .duration: return "Duration"
        case .timestamp: return "Timestamp"
        case .newest: return "Newest"
        case .category: return "Category"
        }
    }

    public func sort(_ candidates: [ClipCandidate]) -> [ClipCandidate] {
        switch self {
        case .potential: return candidates.sorted { $0.potential != $1.potential ? $0.potential > $1.potential : $0.range.start < $1.range.start }
        case .duration: return candidates.sorted { $0.duration < $1.duration }
        case .timestamp: return candidates.sorted { $0.range.start < $1.range.start }
        case .newest: return candidates.sorted { $0.createdAt > $1.createdAt }
        case .category:
            return candidates.sorted {
                let a = $0.tags.first?.rawValue ?? "zzz"
                let b = $1.tags.first?.rawValue ?? "zzz"
                return a != b ? a < b : $0.potential > $1.potential
            }
        }
    }
}
