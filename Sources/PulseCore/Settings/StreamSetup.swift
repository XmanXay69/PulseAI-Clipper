import Foundation

/// "Set up for my stream": a handful of answers about how you stream, turned into the twenty-odd settings
/// that depend on them. Applying it twice changes nothing the second time.
public struct StreamSetup: Codable, Hashable, Sendable {
    public enum Platform: String, Codable, CaseIterable, Sendable {
        case twitch, youtube, kick, tiktokLive

        public var displayName: String {
            switch self {
            case .twitch: return "Twitch"
            case .youtube: return "YouTube"
            case .kick: return "Kick"
            case .tiktokLive: return "TikTok LIVE"
            }
        }
    }

    public enum Content: String, Codable, CaseIterable, Sendable {
        case shooter, battleRoyale, moba, sports, horror, variety, justChatting, podcast, irl

        public var displayName: String {
            switch self {
            case .shooter: return "Shooter"
            case .battleRoyale: return "Battle royale"
            case .moba: return "MOBA / strategy"
            case .sports: return "Sports / racing"
            case .horror: return "Horror / story games"
            case .variety: return "Variety"
            case .justChatting: return "Just Chatting"
            case .podcast: return "Podcast / interview"
            case .irl: return "IRL"
            }
        }

        /// The game draws banners (wins, kills, deaths) PULSE can read off the screen.
        public var isGameplay: Bool {
            switch self {
            case .shooter, .battleRoyale, .moba, .sports, .horror, .variety: return true
            case .justChatting, .podcast, .irl: return false
            }
        }

        /// Fast games get replays and shorter shorts; talk gets longer ones.
        public var isFastAction: Bool {
            switch self {
            case .shooter, .battleRoyale, .moba, .sports: return true
            default: return false
            }
        }

        public var isConversation: Bool { self == .podcast || self == .justChatting }
    }

    public enum Mic: String, Codable, CaseIterable, Sendable {
        /// Game and voice in one mix (most recordings).
        case mixed
        /// A second audio track in the same file (OBS multi-track).
        case separateTrack
        /// A separate recording (mic or webcam file) next to the video.
        case separateFile

        public var displayName: String {
            switch self {
            case .mixed: return "Mixed with the game"
            case .separateTrack: return "Own track in the file"
            case .separateFile: return "Separate recording"
            }
        }
    }

    public enum ShortsTarget: String, Codable, CaseIterable, Sendable {
        case tiktok, shorts, reels

        public var displayName: String {
            switch self {
            case .tiktok: return "TikTok"
            case .shorts: return "YouTube Shorts"
            case .reels: return "Instagram Reels"
            }
        }

        public var exportPresetID: String {
            switch self {
            case .tiktok: return ExportPreset.tiktok.id
            case .shorts: return ExportPreset.shorts.id
            case .reels: return ExportPreset.reels.id
            }
        }

        public var safeArea: SafeAreaPlatform {
            switch self {
            case .tiktok: return .tiktok
            case .shorts: return .youtubeShorts
            case .reels: return .instagramReels
            }
        }
    }

    public enum Pace: String, Codable, CaseIterable, Sendable {
        case calm, normal, hype

        public var displayName: String { rawValue.capitalized }
    }

    public var platform: Platform = .twitch
    public var content: Content = .shooter
    public var facecam: Bool = true
    public var mic: Mic = .mixed
    public var shortsTarget: ShortsTarget = .tiktok
    public var pace: Pace = .normal
    /// A caption preset name (`CaptionStyle.presets`); empty = pick one for the content.
    public var captionPreset: String = ""

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StreamSetup()
        platform = c.decode(Platform.self, forKey: .platform, default: d.platform)
        content = c.decode(Content.self, forKey: .content, default: d.content)
        facecam = c.decode(Bool.self, forKey: .facecam, default: d.facecam)
        mic = c.decode(Mic.self, forKey: .mic, default: d.mic)
        shortsTarget = c.decode(ShortsTarget.self, forKey: .shortsTarget, default: d.shortsTarget)
        pace = c.decode(Pace.self, forKey: .pace, default: d.pace)
        captionPreset = c.decode(String.self, forKey: .captionPreset, default: d.captionPreset)
    }

    /// The caption look that suits the content when none was chosen.
    public var effectiveCaptionPreset: String {
        if !captionPreset.isEmpty, CaptionStyle.presets.contains(where: { $0.presetName == captionPreset }) { return captionPreset }
        switch content {
        case .podcast: return "Podcast"
        case .shooter, .battleRoyale, .moba, .sports: return "Gaming"
        case .horror: return "Cinematic"
        case .justChatting, .irl, .variety: return "TikTok"
        }
    }

    /// What `apply` will do to these settings, as short "Setting: value" lines (empty when nothing would change).
    public func changes(to settings: AppSettings) -> [String] {
        var copy = settings
        return apply(to: &copy)
    }

    /// Applies the answers and returns what changed. Settings the answers don't speak to are left alone.
    @discardableResult
    public func apply(to settings: inout AppSettings) -> [String] {
        var changes: [String] = []
        func set<T: Equatable>(_ keyPath: WritableKeyPath<AppSettings, T>, _ value: T, _ label: String, _ display: String) {
            guard settings[keyPath: keyPath] != value else { return }
            settings[keyPath: keyPath] = value
            changes.append("\(label): \(display)")
        }
        let gameplay = content.isGameplay
        let fast = content.isFastAction
        let talk = content.isConversation

        let aggressiveness: Double = pace == .calm ? 0.35 : pace == .hype ? 0.65 : 0.5
        set(\.ai.clipAggressiveness, aggressiveness, "Clip sensitivity", pace.displayName)
        let length: ClipLengthPreset = fast ? .medium30 : .long60
        set(\.ai.defaultClipLength, length, "Short length", fast ? "30 s" : "60 s")
        let preset = effectiveCaptionPreset
        set(\.ai.captionPresetName, preset, "Captions", preset)
        set(\.ai.autoZoom, true, "Auto zoom", "on")
        set(\.ai.autoCrop, true, "Auto crop", "on")
        set(\.ai.aiFraming, true, "AI framing", "on")
        set(\.ai.silenceRemoval, true, "Silence removal", "on")
        let silence: SilencePreset = talk ? .conservative : .balanced
        set(\.ai.silencePreset, silence, "Dead air", talk ? "light" : "normal")
        set(\.ai.fillerRemoval, content == .podcast, "Filler words", content == .podcast ? "removed" : "kept")
        set(\.ai.aiSoundEffects, gameplay, "Sound effects", gameplay ? "on" : "off")
        set(\.ai.detectSpeakers, talk, "Speaker detection", talk ? "on" : "off")
        set(\.ai.speakerCount, content == .podcast ? 2 : 0, "Speakers", content == .podcast ? "2" : "auto")
        set(\.ai.hudCues, gameplay, "Game banners", gameplay ? "read from the screen" : "off")

        var extras = settings.ai.editExtras
        extras.facecamPunchIns = facecam && gameplay
        extras.instantReplays = fast
        extras.beatSync = pace == .hype
        extras.speakerAware = talk
        extras.titleCards = content == .variety || content == .justChatting || content == .irl
        extras.brollClips = talk || content == .irl
        extras.loudnessCheck = true
        let on = [extras.facecamPunchIns ? "facecam punch-ins" : nil, extras.instantReplays ? "instant replays" : nil,
                  extras.beatSync ? "beat sync" : nil, extras.speakerAware ? "speaker-aware" : nil,
                  extras.titleCards ? "title cards" : nil, extras.brollClips ? "B-roll" : nil, "loudness check"].compactMap { $0 }
        set(\.ai.editExtras, extras, "Edit My VOD extras", on.joined(separator: ", "))

        set(\.safeAreaPlatform, shortsTarget.safeArea, "Safe areas", shortsTarget.displayName)
        set(\.showSafeAreas, true, "Show safe areas", "on")
        set(\.defaultExportPresetID, shortsTarget.exportPresetID, "Export preset", shortsTarget.displayName)
        set(\.hasCompletedOnboarding, true, "Onboarding", "done")
        set(\.streamSetup, self, "Stream setup", "saved")
        return changes
    }

    /// A line of advice for the mic answer (PULSE pairs a separate recording itself; a second track isn't read yet).
    public var micAdvice: String {
        switch mic {
        case .mixed: return "PULSE separates the voice from the game where it needs to (captions, leveling, speaker detection)."
        case .separateTrack: return "PULSE reads the first track of a file. Export the mic track to its own file from OBS (or remux with the mic first) and import it next to the video — PULSE pairs them."
        case .separateFile: return "Import the mic or webcam recording into the same project; PULSE pairs it with the video by name and sound and uses it for speech."
        }
    }
}
