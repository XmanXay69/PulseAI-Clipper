import Foundation

/// A shareable sound pack (#496): which library sound does each job, plus the stars you gave sounds. One JSON
/// file to hand to another streamer; importing applies the choices and merges the ratings.
public struct SoundPackManifest: Codable, Hashable, Sendable {
    public static let fileExtension = "pulsepack"

    public var name: String
    public var author: String
    public var version: Int
    public var notes: String
    /// Job ("hit", "whoosh") → a library sound's name.
    public var preferences: [String: String]
    /// Library sound id → 1…5.
    public var ratings: [String: Int]

    public init(name: String, author: String = "", version: Int = 1, notes: String = "", preferences: [String: String], ratings: [String: Int]) {
        self.name = name
        self.author = author
        self.version = version
        self.notes = notes
        self.preferences = preferences
        self.ratings = ratings.filter { (1...5).contains($0.value) }
    }

    public static func parse(_ data: Data) -> SoundPackManifest? {
        try? JSONDecoder().decode(SoundPackManifest.self, from: data)
    }

    public func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Applies the pack: the job choices replace yours; ratings fill in where you haven't rated (or replace
    /// when `replaceRatings`). Returns how many ratings were taken.
    @discardableResult
    public func apply(to settings: inout AISettings, replaceRatings: Bool = false) -> Int {
        settings.preferredEffects = preferences
        var taken = 0
        for (id, stars) in ratings where replaceRatings || settings.soundRatings[id] == nil {
            settings.soundRatings[id] = stars
            taken += 1
        }
        return taken
    }

    /// Your current choices and stars as a pack.
    public static func current(_ settings: AISettings, name: String, author: String = "") -> SoundPackManifest {
        SoundPackManifest(name: name, author: author, preferences: settings.preferredEffects, ratings: settings.soundRatings)
    }
}

extension SoundLibrary {
    /// Sounds in rating order (#496): 4–5 stars first, then unrated and 3-star ones, then 1–2 stars; the given
    /// order is kept inside each group.
    public static func sorted(_ sounds: [LibrarySound], ratings: [String: Int]) -> [LibrarySound] {
        func rank(_ s: LibrarySound) -> Int {
            switch ratings[s.id] ?? 0 {
            case 4...: return 0
            case 1...2: return 2
            default: return 1
            }
        }
        return sounds.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }
}
