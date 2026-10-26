import Foundation

/// A banner the game drew on screen — "VICTORY ROYALE", "ELIMINATED", "DOUBLE KILL" — read off a sampled frame.
public struct HUDEvent: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case win, loss, kill, multiKill, death, objective, levelUp, achievement, clutch
        /// Not a banner: you pressed "clip it" while recording.
        case marked

        public var displayName: String {
            switch self {
            case .marked: return "Marked"
            case .win: return "Win"
            case .loss: return "Loss"
            case .kill: return "Kill"
            case .multiKill: return "Multi-kill"
            case .death: return "Death"
            case .objective: return "Objective"
            case .levelUp: return "Rank up"
            case .achievement: return "Achievement"
            case .clutch: return "Clutch"
            }
        }

        public var symbolName: String {
            switch self {
            case .marked: return "flag.fill"
            case .win: return "trophy"
            case .loss: return "xmark.octagon"
            case .kill: return "scope"
            case .multiKill: return "flame"
            case .death: return "heart.slash"
            case .objective: return "flag.checkered"
            case .levelUp: return "arrow.up.circle"
            case .achievement: return "star.circle"
            case .clutch: return "bolt"
            }
        }

        /// How much of a moment the banner is on its own (0…1).
        public var weight: Double {
            switch self {
            case .win, .marked: return 1
            case .multiKill, .clutch: return 0.9
            case .achievement: return 0.7
            case .loss: return 0.6
            case .objective: return 0.55
            case .levelUp: return 0.5
            case .death: return 0.45
            case .kill: return 0.4
            }
        }

        /// The clip tag a short built around this banner gets.
        public var tag: ClipTag {
            switch self {
            case .win, .multiKill, .clutch, .achievement, .levelUp, .objective, .marked: return .hype
            case .loss, .death: return .fail
            case .kill: return .gaming
            }
        }
    }

    public var id: String { "\(kind.rawValue)@\(Int((time * 10).rounded()))" }
    public var time: Seconds
    public var kind: Kind
    /// The phrase that matched, upper-cased ("DOUBLE KILL").
    public var text: String
    public var confidence: Double

    public init(time: Seconds, kind: Kind, text: String, confidence: Double = 1) {
        self.time = time
        self.kind = kind
        self.text = text
        self.confidence = confidence
    }
}

/// Maps on-screen text to game events. Phrases match on word boundaries, longest first, so
/// "DOUBLE KILL" is a multi-kill (never also a kill) and "WINDOW" is never a win.
public enum HUDCues {
    static let phrases: [(String, HUDEvent.Kind)] = [
        // Wins
        ("#1 VICTORY ROYALE", .win), ("VICTORY ROYALE", .win), ("WINNER WINNER CHICKEN DINNER", .win), ("CHICKEN DINNER", .win),
        ("VICTORY", .win), ("YOU WIN", .win), ("YOU WON", .win), ("ROUND WON", .win), ("MATCH WON", .win), ("BOOYAH", .win),
        ("WINNER", .win), ("CHAMPION", .win), ("MISSION ACCOMPLISHED", .win), ("STAGE CLEAR", .win), ("TEAM VICTORY", .win),
        // Losses
        ("DEFEAT", .loss), ("DEFEATED", .loss), ("YOU LOSE", .loss), ("YOU LOST", .loss), ("ROUND LOST", .loss), ("MATCH LOST", .loss),
        ("GAME OVER", .loss), ("MISSION FAILED", .loss), ("ELIMINATED FROM THE MATCH", .loss),
        // Deaths
        ("YOU DIED", .death), ("WASTED", .death), ("YOU WERE ELIMINATED", .death), ("YOU HAVE BEEN ELIMINATED", .death),
        ("YOU WERE KILLED", .death), ("KILLED BY", .death), ("ELIMINATED BY", .death), ("KNOCKED DOWN BY", .death),
        ("RESPAWNING", .death), ("RESPAWN IN", .death), ("SPECTATING", .death), ("YOU ARE DEAD", .death), ("YOU WERE KNOCKED", .death),
        // Multi-kills
        ("DOUBLE KILL", .multiKill), ("TRIPLE KILL", .multiKill), ("QUADRA KILL", .multiKill), ("QUAD KILL", .multiKill),
        ("PENTA KILL", .multiKill), ("PENTAKILL", .multiKill), ("MULTI KILL", .multiKill), ("MULTIKILL", .multiKill), ("ACE", .multiKill),
        ("TEAM WIPE", .multiKill), ("SQUAD WIPED", .multiKill), ("SQUAD WIPE", .multiKill), ("KILLING SPREE", .multiKill),
        ("RAMPAGE", .multiKill), ("UNSTOPPABLE", .multiKill), ("GODLIKE", .multiKill), ("COLLATERAL", .multiKill),
        ("DOMINATING", .multiKill), ("MEGA KILL", .multiKill), ("ULTRA KILL", .multiKill), ("MONSTER KILL", .multiKill),
        // Kills
        ("FINAL KILL", .kill), ("HEADSHOT", .kill), ("ENEMY ELIMINATED", .kill), ("ENEMY KNOCKED", .kill), ("ENEMY DOWN", .kill),
        ("ELIMINATED", .kill), ("KNOCKED", .kill), ("KILLED", .kill), ("KILL", .kill), ("FIRST BLOOD", .kill), ("TAKEDOWN", .kill),
        // Objectives
        ("BOSS DEFEATED", .objective), ("RAID COMPLETE", .objective), ("DUNGEON CLEARED", .objective), ("OBJECTIVE COMPLETE", .objective),
        ("OBJECTIVE CAPTURED", .objective), ("FLAG CAPTURED", .objective), ("BOMB DEFUSED", .objective), ("BOMB PLANTED", .objective),
        ("POINT CAPTURED", .objective), ("GOAL", .objective), ("TOUCHDOWN", .objective), ("MATCH POINT", .objective), ("OVERTIME", .objective),
        ("FINAL ROUND", .objective), ("LAST ROUND", .objective), ("FINAL CIRCLE", .objective), ("SUDDEN DEATH", .objective),
        ("QUEST COMPLETE", .objective), ("LEVEL COMPLETE", .objective),
        // Rank / level
        ("LEVEL UP", .levelUp), ("RANK UP", .levelUp), ("RANKED UP", .levelUp), ("PROMOTED", .levelUp), ("NEW RANK", .levelUp), ("TIER UP", .levelUp),
        // Achievements / records
        ("ACHIEVEMENT UNLOCKED", .achievement), ("TROPHY UNLOCKED", .achievement), ("NEW RECORD", .achievement), ("NEW HIGH SCORE", .achievement),
        ("NEW PERSONAL BEST", .achievement), ("PERSONAL BEST", .achievement), ("PLAY OF THE GAME", .achievement), ("MVP", .achievement),
        ("WORLD RECORD", .achievement), ("HIGH SCORE", .achievement),
        // Clutch
        ("CLUTCH", .clutch), ("1V3", .clutch), ("1V4", .clutch), ("1V5", .clutch), ("1 VS 3", .clutch), ("1 VS 4", .clutch), ("1 VS 5", .clutch),
    ]

    /// Longest phrases first so the most specific one wins.
    static let ordered: [(String, HUDEvent.Kind)] = phrases.sorted {
        let a = $0.0.split(separator: " ").count, b = $1.0.split(separator: " ").count
        return a != b ? a > b : $0.0.count > $1.0.count
    }

    /// Upper-case, punctuation to spaces (keeping # and apostrophes), single spaces.
    static func normalize(_ text: String) -> String {
        let upper = text.uppercased()
        var out = ""
        out.reserveCapacity(upper.count)
        for ch in upper {
            if ch.isLetter || ch.isNumber || ch == "#" || ch == "'" { out.append(ch) } else { out.append(" ") }
        }
        return out.split(separator: " ").joined(separator: " ")
    }

    /// The event one recognised string means, if any. Long strings (chat lines, menus) are ignored: a banner is short.
    public static func event(forText text: String, at time: Seconds, confidence: Double = 1) -> HUDEvent? {
        let normalized = normalize(text)
        guard !normalized.isEmpty, normalized.count <= 48, normalized.split(separator: " ").count <= 7 else { return nil }
        let padded = " " + normalized + " "
        for (phrase, kind) in ordered where padded.contains(" " + phrase + " ") {
            return HUDEvent(time: time, kind: kind, text: phrase, confidence: confidence)
        }
        return nil
    }

    /// One event per banner: the same phrase seen again within `window` seconds is the banner still on screen.
    public static func coalesce(_ events: [HUDEvent], window: Seconds = 4) -> [HUDEvent] {
        var out: [HUDEvent] = []
        var lastSeen: [String: Seconds] = [:]
        for e in events.sorted(by: { $0.time < $1.time }) {
            let key = e.kind.rawValue + "|" + e.text
            if let last = lastSeen[key], e.time - last <= window {
                lastSeen[key] = e.time
                continue
            }
            lastSeen[key] = e.time
            out.append(e)
        }
        return out
    }

    /// A 0…1 series: a bump around each banner, rising over the 2 s before it (the play happens before the
    /// banner) and fading over the 4 s after.
    public static func signal(events: [HUDEvent], duration: Seconds, step: Seconds) -> [Float] {
        let n = max(1, Int((duration / step).rounded(.up)))
        var out = [Float](repeating: 0, count: n)
        guard !events.isEmpty else { return out }
        let before: Seconds = 2.5, after: Seconds = 4.5
        for e in events {
            let weight = Float(e.kind.weight * e.confidence.clamped(0.3, 1))
            let lo = max(0, Int((e.time - before) / step)), hi = min(n - 1, Int((e.time + after) / step))
            guard hi >= lo else { continue }
            for i in lo...hi {
                let dt = Double(i) * step + step / 2 - e.time
                let shape = dt < 0 ? 1 - min(1, -dt / before) : 1 - min(1, dt / after)
                out[i] = max(out[i], weight * Float(shape))
            }
        }
        return out
    }
}
