import Foundation

/// One item of the built-in sound library.
public struct LibrarySound: Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case music, soundEffect }
    public enum Source: Hashable, Sendable {
        case music(MusicPreset)
        case effect(SoundEffectKind)
    }

    public var id: String
    public var name: String
    public var kind: Kind
    public var category: String
    public var tags: [String]
    public var summary: String
    public var source: Source

    public var bpm: Int? {
        if case .music(let preset) = source { return Int(preset.bpm.rounded()) }
        return nil
    }

    /// Asset tags that let PULSE recognise (and re-render) a library file.
    public func assetTags(duration: Seconds?) -> [String] {
        var t = ["pulse-library", "library:\(id)"] + tags
        if let duration { t.append(String(format: "library-length:%.1f", duration)) }
        return t
    }
}

/// Royalty-free music and sound effects generated on this Mac by `MusicComposer` and `SoundEffectSynth`.
/// Nothing is downloaded and nothing is licensed from anyone, so everything can be used in monetized videos.
public enum SoundLibrary {
    /// Bump when synthesis changes so cached renders are replaced.
    public static let version = 1
    /// Length of music previews and of music added without a target length.
    public static let defaultMusicLength: Seconds = 30

    public static let catalog: [LibrarySound] = music + effects

    static func track(_ id: String, _ name: String, _ style: MusicStyle, bpm: Double, root: Int, minor: Bool, seed: UInt64,
                      tags: [String], _ summary: String) -> LibrarySound {
        LibrarySound(id: "music.\(id)", name: name, kind: .music, category: style.displayName, tags: tags, summary: summary,
                     source: .music(MusicPreset(style: style, bpm: bpm, root: root, minor: minor, seed: seed)))
    }

    public static let music: [LibrarySound] = [
        track("lofi.sunday", "Sunday Morning", .lofi, bpm: 82, root: 60, minor: false, seed: 101,
              tags: ["chill", "calm", "study", "cozy", "podcast", "talking"], "Dusty electric piano, lazy swing and vinyl crackle."),
        track("lofi.midnight", "Midnight Study", .lofi, bpm: 74, root: 55, minor: false, seed: 102,
              tags: ["chill", "night", "study", "calm", "talking"], "Slow, warm late-night beat."),
        track("trap.clutch", "Clutch Moment", .trap, bpm: 140, root: 61, minor: true, seed: 103,
              tags: ["hype", "gaming", "intense", "dark", "energy"], "Gliding 808s, rolling hats and a dark bell hook."),
        track("trap.victory", "Victory Lap", .trap, bpm: 150, root: 53, minor: true, seed: 104,
              tags: ["hype", "win", "flex", "gaming", "energy"], "Hard-hitting celebration beat."),
        track("upbeat.goodvibes", "Good Vibes", .upbeat, bpm: 122, root: 60, minor: false, seed: 105,
              tags: ["happy", "upbeat", "vlog", "energy", "dance"], "Four-on-the-floor pop with pumping chords."),
        track("upbeat.weekend", "Weekend Plans", .upbeat, bpm: 118, root: 62, minor: false, seed: 106,
              tags: ["happy", "bright", "vlog", "travel", "summer"], "Bright, bouncy and positive."),
        track("acoustic.sunny", "Sunny Side", .acoustic, bpm: 104, root: 55, minor: false, seed: 107,
              tags: ["happy", "acoustic", "lifestyle", "cooking", "warm"], "Strummed guitar, claps and shaker."),
        track("acoustic.roadtrip", "Road Trip", .acoustic, bpm: 96, root: 57, minor: false, seed: 108,
              tags: ["travel", "acoustic", "warm", "story"], "Easy-going strums for stories and travel."),
        track("synthwave.neon", "Neon Drive", .synthwave, bpm: 100, root: 57, minor: true, seed: 109,
              tags: ["retro", "gaming", "night", "80s", "cool"], "Arpeggios, big gated snare and analog pads."),
        track("cinematic.rise", "Epic Rise", .cinematic, bpm: 90, root: 52, minor: true, seed: 110,
              tags: ["epic", "dramatic", "trailer", "build", "story"], "Strings and taiko drums that build to the end."),
        track("chiptune.quest", "Pixel Quest", .chiptune, bpm: 150, root: 60, minor: false, seed: 111,
              tags: ["gaming", "retro", "fun", "8-bit", "energy"], "8-bit square leads and triangle bass."),
        track("suspense.tension", "Tension", .suspense, bpm: 70, root: 52, minor: true, seed: 112,
              tags: ["suspense", "mystery", "dark", "tense", "reveal"], "Ticking clock, drone and heartbeat pulses."),
        track("quirky.oops", "Oops!", .quirky, bpm: 118, root: 60, minor: false, seed: 113,
              tags: ["funny", "comedy", "fail", "silly", "playful"], "Bouncy pizzicato and mallets for comedy."),
        track("ambient.calm", "Calm Waters", .ambient, bpm: 64, root: 60, minor: false, seed: 114,
              tags: ["calm", "emotional", "ambient", "background", "story"], "Soft pads and bells, no drums."),
    ]

    static func effect(_ kind: SoundEffectKind, _ name: String, _ category: String, _ tags: [String], _ summary: String) -> LibrarySound {
        LibrarySound(id: "sfx.\(kind.rawValue)", name: name, kind: .soundEffect, category: category, tags: tags, summary: summary, source: .effect(kind))
    }

    public static let effects: [LibrarySound] = [
        effect(.whoosh, "Whoosh", "Transitions", ["whoosh", "transition", "swipe"], "Airy pass from left to right."),
        effect(.swoosh, "Swoosh", "Transitions", ["swoosh", "whoosh", "transition", "fast"], "Quick, bright swipe."),
        effect(.riser, "Riser", "Transitions", ["riser", "build", "tension", "transition"], "Three-second build-up into a drop."),
        effect(.downlifter, "Downlifter", "Transitions", ["downlifter", "fall", "transition"], "Falling sweep after a big moment."),
        effect(.impact, "Impact", "Impacts", ["impact", "hit", "boom", "cinematic"], "Cinematic hit with a deep tail."),
        effect(.bassDrop, "Bass Drop", "Impacts", ["drop", "bass", "hit", "impact"], "Sub sweep that hits hard."),
        effect(.boom, "Deep Boom", "Impacts", ["boom", "meme", "impact", "reveal"], "Huge echoing boom for reveals."),
        effect(.pop, "Pop", "UI & Pops", ["pop", "text", "appear"], "Short pop for text and emojis."),
        effect(.bubble, "Bubble", "UI & Pops", ["bubble", "pop", "cute"], "Soft bubbly blip."),
        effect(.click, "Click", "UI & Pops", ["click", "ui", "tap"], "Crisp mouse click."),
        effect(.ding, "Ding", "UI & Pops", ["ding", "bell", "correct", "idea"], "Clean bell — right answer, idea."),
        effect(.notification, "Notification", "UI & Pops", ["notification", "message", "alert"], "Two-tone phone alert."),
        effect(.success, "Success", "UI & Pops", ["success", "win", "chime", "achievement"], "Rising chime."),
        effect(.error, "Error", "UI & Pops", ["error", "wrong", "buzzer", "fail"], "Wrong-answer buzzer."),
        effect(.boing, "Boing", "Comedy", ["boing", "funny", "spring", "cartoon"], "Cartoon spring."),
        effect(.rimshot, "Ba Dum Tss", "Comedy", ["rimshot", "joke", "funny", "punchline"], "Drum sting after a joke."),
        effect(.sadTrombone, "Sad Trombone", "Comedy", ["fail", "sad", "funny", "trombone"], "Wah wah wah waaah."),
        effect(.scratch, "Record Scratch", "Comedy", ["scratch", "stop", "freeze", "funny"], "Record stop — \"yep, that's me\"."),
        effect(.applause, "Applause", "Comedy", ["applause", "clap", "crowd", "win"], "Small crowd clapping."),
        effect(.coin, "Coin", "Gaming", ["coin", "gaming", "8-bit", "money"], "8-bit coin pickup."),
        effect(.levelUp, "Level Up", "Gaming", ["level", "gaming", "8-bit", "win"], "8-bit level-up fanfare."),
        effect(.laser, "Laser", "Gaming", ["laser", "zap", "gaming", "sci-fi"], "Zap!"),
        effect(.glitch, "Glitch", "Gaming", ["glitch", "digital", "error", "transition"], "Digital stutter."),
        effect(.typing, "Keyboard Typing", "Foley & Tension", ["typing", "keyboard", "computer"], "Mechanical keyboard typing."),
        effect(.shutter, "Camera Shutter", "Foley & Tension", ["camera", "photo", "shutter", "snap"], "Photo snap."),
        effect(.heartbeat, "Heartbeat", "Foley & Tension", ["heartbeat", "tension", "suspense"], "Two slow heartbeats."),
        effect(.countdown, "Countdown", "Foley & Tension", ["countdown", "timer", "start", "beep"], "3, 2, 1, go!"),
        effect(.drumroll, "Drum Roll", "Foley & Tension", ["drumroll", "reveal", "suspense"], "Roll into a crash for reveals."),
    ]

    public static var musicCategories: [String] { unique(music.map(\.category)) }
    public static var effectCategories: [String] { unique(effects.map(\.category)) }

    static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    public static func sound(id: String) -> LibrarySound? { catalog.first { $0.id == id } }

    /// Matches name, category, tags and description; every word of the query must match.
    public static func search(_ query: String, kind: LibrarySound.Kind? = nil, category: String? = nil) -> [LibrarySound] {
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return catalog.filter { sound in
            if let kind, sound.kind != kind { return false }
            if let category, sound.category != category { return false }
            let haystack = ([sound.name, sound.category, sound.summary] + sound.tags).joined(separator: " ").lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    /// Renders a sound. Music is exactly `duration` long (default 30 s); effects have their natural length.
    public static func render(_ sound: LibrarySound, duration: Seconds? = nil) -> [[Float]] {
        switch sound.source {
        case .music(let preset): return MusicComposer.render(preset, duration: max(2, duration ?? defaultMusicLength))
        case .effect(let kind): return SoundEffectSynth.render(kind)
        }
    }

    /// Music that suits a clip's tags (deterministic for a given `seed`).
    public static func recommendedMusic(for tags: [ClipTag], seed: Int = 0) -> LibrarySound {
        let ids: [String]
        let set = Set(tags)
        if !set.isDisjoint(with: [.funny, .fail]) {
            ids = ["music.quirky.oops"]
        } else if !set.isDisjoint(with: [.hype, .highEnergy, .rage]) {
            ids = set.contains(.gaming) ? ["music.trap.clutch", "music.trap.victory", "music.chiptune.quest"] : ["music.trap.victory", "music.upbeat.goodvibes"]
        } else if set.contains(.gaming) {
            ids = ["music.synthwave.neon", "music.chiptune.quest", "music.trap.clutch"]
        } else if !set.isDisjoint(with: [.emotional, .story]) {
            ids = ["music.ambient.calm", "music.cinematic.rise", "music.acoustic.roadtrip"]
        } else if set.contains(.reaction) {
            ids = ["music.upbeat.goodvibes", "music.upbeat.weekend"]
        } else {
            ids = ["music.lofi.sunday", "music.lofi.midnight", "music.acoustic.sunny"]
        }
        let id = ids[abs(seed) % ids.count]
        return sound(id: id) ?? music[0]
    }

    /// The effects AI edits use when the project has none of its own.
    public static let aiEffectIDs = ["sfx.whoosh", "sfx.impact", "sfx.pop"]
}
