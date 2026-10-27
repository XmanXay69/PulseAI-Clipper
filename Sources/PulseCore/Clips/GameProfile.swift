import Foundation

/// Which engagement signals matter for a kind of game (#34). A shooter's best moments are on screen (kills,
/// banners, chaos); a sandbox stream's are in the voice; a horror game's are the jump scares. The profile
/// scales the clip scorer's signals and the taste profile still learns on top of it.
public struct GameProfile: Codable, Hashable, Sendable, Identifiable {
    /// Multipliers (1 = the default scorer) for each signal of `EngagementModel`.
    public struct Weights: Codable, Hashable, Sendable {
        public var loudness: Float = 1
        public var surprise: Float = 1
        public var flux: Float = 1
        public var speechRate: Float = 1
        public var keywords: Float = 1
        public var laughter: Float = 1
        public var motion: Float = 1
        public var cuts: Float = 1
        public var hud: Float = 1
        public var chat: Float = 1

        public static let neutral = Weights()

        public init(loudness: Float = 1, surprise: Float = 1, flux: Float = 1, speechRate: Float = 1, keywords: Float = 1,
                    laughter: Float = 1, motion: Float = 1, cuts: Float = 1, hud: Float = 1, chat: Float = 1) {
            self.loudness = loudness
            self.surprise = surprise
            self.flux = flux
            self.speechRate = speechRate
            self.keywords = keywords
            self.laughter = laughter
            self.motion = motion
            self.cuts = cuts
            self.hud = hud
            self.chat = chat
        }

        public var isNeutral: Bool { self == .neutral }

        private enum CodingKeys: String, CodingKey { case loudness, surprise, flux, speechRate, keywords, laughter, motion, cuts, hud, chat }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            loudness = try c.decodeIfPresent(Float.self, forKey: .loudness) ?? 1
            surprise = try c.decodeIfPresent(Float.self, forKey: .surprise) ?? 1
            flux = try c.decodeIfPresent(Float.self, forKey: .flux) ?? 1
            speechRate = try c.decodeIfPresent(Float.self, forKey: .speechRate) ?? 1
            keywords = try c.decodeIfPresent(Float.self, forKey: .keywords) ?? 1
            laughter = try c.decodeIfPresent(Float.self, forKey: .laughter) ?? 1
            motion = try c.decodeIfPresent(Float.self, forKey: .motion) ?? 1
            cuts = try c.decodeIfPresent(Float.self, forKey: .cuts) ?? 1
            hud = try c.decodeIfPresent(Float.self, forKey: .hud) ?? 1
            chat = try c.decodeIfPresent(Float.self, forKey: .chat) ?? 1
        }
    }

    public var id: String
    public var name: String
    /// One line for the settings sheet: what this profile listens for.
    public var summary: String
    /// Lower-cased words or phrases found in game titles, file names and the transcript.
    public var keywords: [String]
    public var weights: Weights

    public init(id: String, name: String, summary: String, keywords: [String], weights: Weights) {
        self.id = id
        self.name = name
        self.summary = summary
        self.keywords = keywords
        self.weights = weights
    }

    // MARK: Built-in profiles

    public static let shooter = GameProfile(
        id: "shooter", name: "Shooter", summary: "Kills, banners and on-screen chaos count most; the voice a little less.",
        keywords: ["valorant", "apex", "fortnite", "warzone", "call of duty", "cod", "cs2", "csgo", "counter strike", "overwatch", "pubg",
                   "rainbow six", "siege", "halo", "marvel rivals", "battlefield", "the finals", "xdefiant", "destiny", "escape from tarkov"],
        weights: Weights(surprise: 1.2, speechRate: 0.9, laughter: 0.9, motion: 1.3, cuts: 1.2, hud: 1.4))

    public static let sandbox = GameProfile(
        id: "sandbox", name: "Sandbox / Cozy", summary: "Laughs, reactions and fast talking carry the stream; the screen rarely does.",
        keywords: ["minecraft", "terraria", "stardew", "roblox", "the sims", "sims 4", "animal crossing", "valheim", "satisfactory",
                   "palworld", "core keeper", "slime rancher", "powerwash", "cozy"],
        weights: Weights(surprise: 0.8, speechRate: 1.1, keywords: 1.2, laughter: 1.3, motion: 0.6, cuts: 0.7, hud: 0.5))

    public static let justChatting = GameProfile(
        id: "justChatting", name: "Just Chatting", summary: "All voice: laughter, hot takes and chat reacting. Motion on screen is ignored.",
        keywords: ["just chatting", "chatting", "react", "reacting", "irl", "talk show", "q&a", "qna", "ama"],
        weights: Weights(surprise: 0.9, speechRate: 1.2, keywords: 1.3, laughter: 1.4, motion: 0.3, cuts: 0.5, hud: 0, chat: 1.2))

    public static let horror = GameProfile(
        id: "horror", name: "Horror", summary: "Jump scares: sudden loud bursts and screams over a quiet build-up.",
        keywords: ["phasmophobia", "resident evil", "outlast", "fnaf", "five nights", "dead by daylight", "dbd", "lethal company",
                   "silent hill", "amnesia", "poppy playtime", "horror", "scary", "the mortuary", "visage", "content warning"],
        weights: Weights(loudness: 1.3, surprise: 1.6, speechRate: 0.9, keywords: 1.1, laughter: 1.1, motion: 0.8, hud: 0.7))

    public static let sports = GameProfile(
        id: "sports", name: "Sports", summary: "Goals, buzzer-beaters and the shout that follows them.",
        keywords: ["fifa", "fc 24", "fc 25", "fc 26", "ea fc", "nba 2k", "2k", "madden", "rocket league", "mlb the show", "nhl", "pes", "efootball"],
        weights: Weights(loudness: 1.2, surprise: 1.2, keywords: 1.1, hud: 1.3))

    public static let racing = GameProfile(
        id: "racing", name: "Racing", summary: "Crashes, overtakes and near misses: motion on screen leads.",
        keywords: ["forza", "gran turismo", "mario kart", "f1", "formula 1", "assetto", "iracing", "need for speed", "beamng", "dirt rally", "wreckfest"],
        weights: Weights(surprise: 1.1, keywords: 0.9, motion: 1.3, cuts: 1.1, hud: 1.1))

    public static let fighting = GameProfile(
        id: "fighting", name: "Fighting", summary: "Round wins, combos and the pop-off: banners and loudness lead.",
        keywords: ["street fighter", "tekken", "mortal kombat", "smash", "smash bros", "guilty gear", "king of fighters", "dragon ball fighterz", "fighterz", "multiversus"],
        weights: Weights(loudness: 1.3, surprise: 1.2, motion: 1.1, cuts: 0.8, hud: 1.4))

    public static let strategy = GameProfile(
        id: "strategy", name: "Strategy / MOBA", summary: "Team fights and big calls: the commentary and banners matter, idle motion doesn't.",
        keywords: ["league of legends", "league", "lol", "dota", "starcraft", "age of empires", "aoe", "civilization", "civ", "hearthstone",
                   "teamfight tactics", "tft", "chess", "total war", "warcraft", "clash royale", "slay the spire", "balatro"],
        weights: Weights(surprise: 0.9, speechRate: 1.1, keywords: 1.2, laughter: 1.1, motion: 0.7, hud: 1.1))

    /// Specific titles first so "Just Chatting with Minecraft in the background" lands on the game it names.
    public static let builtIn: [GameProfile] = [shooter, horror, sports, racing, fighting, strategy, sandbox, justChatting]

    public static func profile(id: String) -> GameProfile? { builtIn.first { $0.id == id } }

    // MARK: Detection

    /// Lower-cased, punctuation turned into spaces, padded so whole-word matches are " word ".
    static func normalized(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count + 2)
        out.append(" ")
        var lastSpace = true
        for scalar in text.lowercased().unicodeScalars {
            let isWord = CharacterSet.alphanumerics.contains(scalar) || scalar == "&"
            if isWord {
                out.unicodeScalars.append(scalar)
                lastSpace = false
            } else if !lastSpace {
                out.append(" ")
                lastSpace = true
            }
        }
        if !lastSpace { out.append(" ") }
        return out
    }

    /// The profile a recording belongs to, from its project and file names (one mention is enough) or from the
    /// transcript's normalized words (a game has to be named at least twice). Nil when nothing matches.
    public static func detect(in names: [String], spoken: [String] = []) -> GameProfile? {
        let haystacks = names.map(normalized)
        for profile in builtIn {
            for keyword in profile.keywords where haystacks.contains(where: { $0.contains(" \(keyword) ") }) {
                return profile
            }
        }
        guard !spoken.isEmpty else { return nil }
        let joined = " " + spoken.joined(separator: " ") + " "
        var best: (profile: GameProfile, hits: Int)?
        for profile in builtIn {
            var hits = 0
            for keyword in profile.keywords where keyword.count >= 3 {
                hits += joined.components(separatedBy: " \(keyword) ").count - 1
            }
            if hits >= 2, hits > (best?.hits ?? 0) { best = (profile, hits) }
        }
        return best?.profile
    }
}
