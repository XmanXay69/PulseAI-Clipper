import Foundation

/// Families of sound effects you can switch wholesale (#298): one choice sets the hit and the whoosh PULSE
/// reaches for, instead of picking each job by hand. "PULSE's pick" clears the choices.
public enum SoundPack: String, CaseIterable, Codable, Sendable {
    case pulse, cinematic, punchy, soft, retro

    public var displayName: String {
        switch self {
        case .pulse: return "PULSE's pick"
        case .cinematic: return "Cinematic"
        case .punchy: return "Punchy"
        case .soft: return "Soft"
        case .retro: return "Retro"
        }
    }

    public var detail: String {
        switch self {
        case .pulse: return "Whatever fits each moment"
        case .cinematic: return "Deep impact and an airy whoosh — trailers and big reveals"
        case .punchy: return "Bass drop and a fast swoosh — gaming and hype"
        case .soft: return "Pop and bubble — talking, cosy and comedy"
        case .retro: return "Coin and glitch — 8-bit and nostalgia"
        }
    }

    /// Settings → AI Features choices per job ("hit", "whoosh" → a library sound's name).
    public var preferences: [String: String] {
        switch self {
        case .pulse: return [:]
        case .cinematic: return ["hit": "Impact", "whoosh": "Whoosh"]
        case .punchy: return ["hit": "Bass Drop", "whoosh": "Swoosh"]
        case .soft: return ["hit": "Pop", "whoosh": "Bubble"]
        case .retro: return ["hit": "Coin", "whoosh": "Glitch"]
        }
    }

    /// The pack a set of choices came from, or nil for a hand-picked mix.
    public static func matching(_ preferences: [String: String]) -> SoundPack? {
        let hit = preferences["hit"] ?? ""
        let whoosh = preferences["whoosh"] ?? ""
        if hit.isEmpty && whoosh.isEmpty { return .pulse }
        return allCases.first { $0 != .pulse && $0.preferences["hit"] == hit && $0.preferences["whoosh"] == whoosh }
    }
}
