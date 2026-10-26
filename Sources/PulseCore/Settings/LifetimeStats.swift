import Foundation

/// What PULSE has done for you so far (#478). Counted as things finish; never sent anywhere.
public struct LifetimeStats: Codable, Hashable, Sendable {
    public var shortsBuilt = 0
    public var longEditsBuilt = 0
    public var exportsFinished = 0
    public var deadAirRemoved: Seconds = 0
    public var secondsAnalyzed: Seconds = 0
    public var momentsRated = 0
    public var since: Date?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shortsBuilt = c.decode(Int.self, forKey: .shortsBuilt, default: 0)
        longEditsBuilt = c.decode(Int.self, forKey: .longEditsBuilt, default: 0)
        exportsFinished = c.decode(Int.self, forKey: .exportsFinished, default: 0)
        deadAirRemoved = c.decode(Seconds.self, forKey: .deadAirRemoved, default: 0)
        secondsAnalyzed = c.decode(Seconds.self, forKey: .secondsAnalyzed, default: 0)
        momentsRated = c.decode(Int.self, forKey: .momentsRated, default: 0)
        since = c.decode(Date?.self, forKey: .since, default: nil)
    }

    public var isEmpty: Bool { shortsBuilt == 0 && longEditsBuilt == 0 && exportsFinished == 0 && deadAirRemoved == 0 && secondsAnalyzed == 0 }

    /// A rough, honest estimate: ~12 minutes per short, ~90 per YouTube edit, twice real time for cutting dead
    /// air by hand, half real time for scrubbing a VOD for moments.
    public var hoursSaved: Double {
        (Double(shortsBuilt) * 12 + Double(longEditsBuilt) * 90 + deadAirRemoved / 60 * 2 + secondsAnalyzed / 60 * 0.5) / 60
    }

    public var lines: [(label: String, value: String)] {
        [("Shorts built", "\(shortsBuilt)"),
         ("YouTube edits", "\(longEditsBuilt)"),
         ("Exports finished", "\(exportsFinished)"),
         ("Dead air removed", Timecode.duration(deadAirRemoved)),
         ("Footage analyzed", Timecode.duration(secondsAnalyzed)),
         ("Moments rated", "\(momentsRated)"),
         ("Hours saved (estimate)", String(format: "%.1f", hoursSaved))]
    }

    public mutating func note(_ change: (inout LifetimeStats) -> Void) {
        if since == nil { since = Date() }
        change(&self)
    }
}
