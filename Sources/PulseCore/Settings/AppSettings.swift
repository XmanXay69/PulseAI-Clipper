import Foundation

public enum TranscriptionEngineChoice: String, Codable, CaseIterable, Sendable {
    /// whisper.cpp when its model covers the language (the release app ships one), else Apple Speech;
    /// each falls back to the other.
    case automatic
    case appleOnDevice
    case whisperCpp

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .appleOnDevice: return "Apple On-Device Speech"
        case .whisperCpp: return "Whisper (whisper.cpp)"
        }
    }
}

public enum CloudProviderKind: String, Codable, CaseIterable, Sendable {
    case none
    case anthropic
    case openAICompatible

    public var displayName: String {
        switch self {
        case .none: return "None (local only)"
        case .anthropic: return "Claude (Anthropic)"
        case .openAICompatible: return "OpenAI-compatible / local LLM server"
        }
    }
}

/// Settings → AI. Every AI feature is individually toggleable.
public struct AISettings: Codable, Hashable, Sendable {
    public var clipAggressiveness: Double = 0.5
    public var defaultClipLength: ClipLengthPreset = .medium30
    public var customClipLength: Seconds = 45
    public var entertainmentThreshold: Int = 25
    public var captionPresetName: String = "TikTok"
    public var autoZoom: Bool = true
    public var autoCrop: Bool = true
    public var silenceRemoval: Bool = true
    public var silencePreset: SilencePreset = .conservative
    public var fillerRemoval: Bool = false
    public var aiSoundEffects: Bool = false
    public var aiMusic: Bool = false
    /// Edit My VOD finds Creative Commons background music on YouTube (else the built-in calm beds).
    public var onlineMusic: Bool = true
    /// Fill each mood's shelf with five tracks while the Mac is idle, so an edit never waits on a download (#303).
    public var prefetchMusic: Bool = false
    /// Your last answers to Edit My VOD's "Extras" question (the starting ticks next time; the overnight
    /// batch uses them as they are).
    public var editExtras: EditExtras = EditExtras()
    /// Your own meme pop-up text per mood (tag raw value → text); empty = default.
    public var memeTexts: [String: String] = [:]
    /// Extra words to censor in captions, on top of the built-in list.
    public var extraProfanity: [String] = []
    /// A folder of your own meme / reaction clips for the B-roll extra (used before YouTube; empty = YouTube only).
    public var brollFolder: String = ""
    /// Read the game's banners (wins, kills, deaths) off the screen during analysis of gameplay.
    public var hudCues: Bool = true
    /// What AI-built edits do to the audio under swear words (the caption filter masks the text).
    public var censorAudio: CensorAudio = .off
    /// Game names, usernames and catchphrases speech-to-text should get right (#43).
    public var customVocabulary: [String] = []
    /// Creative Commons tracks you want again (#292) and never again.
    public var favoriteTrackIDs: [String] = []
    public var blockedTrackIDs: [String] = []
    /// A folder of your own licensed music the music picker uses first (#297); empty = online / built-in only.
    public var musicFolder: String = ""
    /// Threads for local transcription (0 = all but two cores) so the Mac stays usable during analysis (#378).
    public var analysisThreads: Int = 0
    /// Shorts get a 0.9× → 1.1× speed ramp on the payoff (#80).
    public var speedRamp: Bool = false
    /// Shorts open on a flash of the payoff before the story (#59).
    public var coldOpenShorts: Bool = false
    /// A whoosh under the first words of every short (#77).
    public var hookSting: Bool = false
    /// Which library sound to use per job (#105): "hit" and "whoosh" → a sound's name; empty = PULSE's pick.
    public var preferredEffects: [String: String] = [:]
    /// A thin bar along the bottom of YouTube edits that fills as the video plays (#92).
    public var longFormProgressBar: Bool = false
    /// Comment-bait or follow card over the last seconds of every short (#71, #76).
    public var shortsEndCTA: EndCTA = .none
    /// Ask the Extras question once per project, then reuse the answers (#128).
    public var askExtrasOncePerProject: Bool = false
    /// Your @handle for follow cards (#76).
    public var socialHandle: String = ""
    /// B-roll clips used in recent edits, newest last; the next edit avoids them (#133).
    public var recentBrollIDs: [String] = []
    /// Words you emphasised by hand (+) or un-emphasised (−) in captions; new captions learn from it (#238).
    public var emphasisLearned: [String: Int] = [:]
    /// Pitch of the bleep over swear words (#277).
    public var bleepTone: Double = 1000
    public var aiFraming: Bool = true
    /// Label who is talking after transcription (local diarization).
    public var detectSpeakers: Bool = true
    /// 0 = estimate the number of speakers.
    public var speakerCount: Int = 0
    public var processingPolicy: AIProcessingPolicy = .preferLocal
    public var transcriptionEngine: TranscriptionEngineChoice = .automatic
    public var transcriptionLanguage: String = "en-US"
    public var whisperModelPath: String = ""
    public var whisperExecutablePath: String = ""
    public var cloudProvider: CloudProviderKind = .none
    public var cloudModel: String = "claude-opus-5-5"
    public var openAIBaseURL: String = "http://localhost:1234/v1"
    public var openAIIsLocalServer: Bool = true
    /// Learned analysis speed of this Mac (for time estimates).
    public var analysisSpeed: AnalysisSpeedProfile = AnalysisSpeedProfile()
    /// What you find entertaining, learned from 👍 / 👎.
    public var taste: TasteProfile = TasteProfile()
    /// Coach weights fitted to your real analytics (nil = PULSE's defaults).
    public var coachCalibration: CoachCalibration?

    public init() {}

    /// `memeTexts` keyed by tag.
    public var memeTextsByTag: [ClipTag: String] {
        var out: [ClipTag: String] = [:]
        for (key, text) in memeTexts { if let tag = ClipTag(rawValue: key) { out[tag] = text } }
        return out
    }

    /// `extraProfanity` the way captions compare words (lower-cased, no punctuation).
    public var normalizedExtraProfanity: Set<String> {
        Set(extraProfanity.map { TranscriptWord.normalize($0) }.filter { !$0.isEmpty })
    }

    public var targetClipDuration: Seconds {
        defaultClipLength.seconds ?? customClipLength.clamped(10, 90)
    }

    public var generationSettings: ClipGenerationSettings {
        ClipGenerationSettings(targetDuration: targetClipDuration, aggressiveness: clipAggressiveness, minimumPotential: entertainmentThreshold)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AISettings()
        clipAggressiveness = c.decode(Double.self, forKey: .clipAggressiveness, default: d.clipAggressiveness)
        defaultClipLength = c.decode(ClipLengthPreset.self, forKey: .defaultClipLength, default: d.defaultClipLength)
        customClipLength = c.decode(Seconds.self, forKey: .customClipLength, default: d.customClipLength)
        entertainmentThreshold = c.decode(Int.self, forKey: .entertainmentThreshold, default: d.entertainmentThreshold)
        captionPresetName = c.decode(String.self, forKey: .captionPresetName, default: d.captionPresetName)
        autoZoom = c.decode(Bool.self, forKey: .autoZoom, default: d.autoZoom)
        autoCrop = c.decode(Bool.self, forKey: .autoCrop, default: d.autoCrop)
        silenceRemoval = c.decode(Bool.self, forKey: .silenceRemoval, default: d.silenceRemoval)
        silencePreset = c.decode(SilencePreset.self, forKey: .silencePreset, default: d.silencePreset)
        fillerRemoval = c.decode(Bool.self, forKey: .fillerRemoval, default: d.fillerRemoval)
        aiSoundEffects = c.decode(Bool.self, forKey: .aiSoundEffects, default: d.aiSoundEffects)
        aiMusic = c.decode(Bool.self, forKey: .aiMusic, default: d.aiMusic)
        onlineMusic = c.decode(Bool.self, forKey: .onlineMusic, default: d.onlineMusic)
        prefetchMusic = c.decode(Bool.self, forKey: .prefetchMusic, default: d.prefetchMusic)
        editExtras = c.decode(EditExtras.self, forKey: .editExtras, default: d.editExtras)
        memeTexts = c.decode([String: String].self, forKey: .memeTexts, default: d.memeTexts)
        extraProfanity = c.decode([String].self, forKey: .extraProfanity, default: d.extraProfanity)
        brollFolder = c.decode(String.self, forKey: .brollFolder, default: d.brollFolder)
        hudCues = c.decode(Bool.self, forKey: .hudCues, default: d.hudCues)
        censorAudio = c.decode(CensorAudio.self, forKey: .censorAudio, default: d.censorAudio)
        customVocabulary = c.decode([String].self, forKey: .customVocabulary, default: d.customVocabulary)
        favoriteTrackIDs = c.decode([String].self, forKey: .favoriteTrackIDs, default: d.favoriteTrackIDs)
        blockedTrackIDs = c.decode([String].self, forKey: .blockedTrackIDs, default: d.blockedTrackIDs)
        musicFolder = c.decode(String.self, forKey: .musicFolder, default: d.musicFolder)
        analysisThreads = c.decode(Int.self, forKey: .analysisThreads, default: d.analysisThreads)
        speedRamp = c.decode(Bool.self, forKey: .speedRamp, default: d.speedRamp)
        coldOpenShorts = c.decode(Bool.self, forKey: .coldOpenShorts, default: d.coldOpenShorts)
        hookSting = c.decode(Bool.self, forKey: .hookSting, default: d.hookSting)
        preferredEffects = c.decode([String: String].self, forKey: .preferredEffects, default: d.preferredEffects)
        longFormProgressBar = c.decode(Bool.self, forKey: .longFormProgressBar, default: d.longFormProgressBar)
        shortsEndCTA = c.decode(EndCTA.self, forKey: .shortsEndCTA, default: d.shortsEndCTA)
        askExtrasOncePerProject = c.decode(Bool.self, forKey: .askExtrasOncePerProject, default: d.askExtrasOncePerProject)
        socialHandle = c.decode(String.self, forKey: .socialHandle, default: d.socialHandle)
        recentBrollIDs = c.decode([String].self, forKey: .recentBrollIDs, default: d.recentBrollIDs)
        emphasisLearned = c.decode([String: Int].self, forKey: .emphasisLearned, default: d.emphasisLearned)
        bleepTone = c.decode(Double.self, forKey: .bleepTone, default: d.bleepTone).clamped(200, 4000)
        aiFraming = c.decode(Bool.self, forKey: .aiFraming, default: d.aiFraming)
        detectSpeakers = c.decode(Bool.self, forKey: .detectSpeakers, default: d.detectSpeakers)
        speakerCount = c.decode(Int.self, forKey: .speakerCount, default: d.speakerCount)
        processingPolicy = c.decode(AIProcessingPolicy.self, forKey: .processingPolicy, default: d.processingPolicy)
        transcriptionEngine = c.decode(TranscriptionEngineChoice.self, forKey: .transcriptionEngine, default: d.transcriptionEngine)
        transcriptionLanguage = c.decode(String.self, forKey: .transcriptionLanguage, default: d.transcriptionLanguage)
        whisperModelPath = c.decode(String.self, forKey: .whisperModelPath, default: d.whisperModelPath)
        whisperExecutablePath = c.decode(String.self, forKey: .whisperExecutablePath, default: d.whisperExecutablePath)
        cloudProvider = c.decode(CloudProviderKind.self, forKey: .cloudProvider, default: d.cloudProvider)
        cloudModel = c.decode(String.self, forKey: .cloudModel, default: d.cloudModel)
        openAIBaseURL = c.decode(String.self, forKey: .openAIBaseURL, default: d.openAIBaseURL)
        openAIIsLocalServer = c.decode(Bool.self, forKey: .openAIIsLocalServer, default: d.openAIIsLocalServer)
        analysisSpeed = c.decode(AnalysisSpeedProfile.self, forKey: .analysisSpeed, default: d.analysisSpeed)
        taste = c.decode(TasteProfile.self, forKey: .taste, default: d.taste)
        coachCalibration = c.decode(CoachCalibration?.self, forKey: .coachCalibration, default: nil)
    }
}

public enum ProxyQuality: String, Codable, CaseIterable, Sendable {
    case half
    case quarter
    case custom

    public var displayName: String {
        switch self {
        case .half: return "Half"
        case .quarter: return "Quarter"
        case .custom: return "Custom"
        }
    }
}

public struct ProxySettings: Codable, Hashable, Sendable {
    public var enabled: Bool = true
    public var quality: ProxyQuality = .half
    /// Custom proxy height in pixels.
    public var customHeight: Int = 540
    /// Proxies are generated automatically for sources taller than this.
    public var autoThresholdHeight: Int = 1440
    public var useProxiesForPlayback: Bool = true

    public init() {}

    public func proxyHeight(forSourceHeight h: Int) -> Int {
        switch quality {
        case .half: return max(360, h / 2)
        case .quarter: return max(270, h / 4)
        case .custom: return max(144, customHeight)
        }
    }

    public func shouldGenerateProxy(sourceHeight: Int, duration: Seconds) -> Bool {
        enabled && (sourceHeight > autoThresholdHeight || duration > 2 * 3600)
    }

    /// Codecs that decode frame by frame (ProRes, DNxHR, Motion JPEG, DV) play fine without a proxy up to 4K;
    /// long-GOP ones (H.264, HEVC, VP9, AV1) get one above the threshold (#16).
    public static let intraCodecs: Set<String> = ["apch", "apcn", "apcs", "apco", "ap4h", "ap4x", "AVdn", "AVdh", "jpeg", "mjpa", "mjpb", "dvc ", "dvcp", "dvpp", "dvh1", "dvhp"]

    public func shouldGenerateProxy(sourceHeight: Int, duration: Seconds, codec: String?) -> Bool {
        guard enabled else { return false }
        if let codec, ProxySettings.intraCodecs.contains(codec) { return sourceHeight > 2160 || duration > 2 * 3600 }
        return shouldGenerateProxy(sourceHeight: sourceHeight, duration: duration)
    }

    /// One line for the media panel saying why a proxy was or wasn't made (#16).
    public func proxyReason(sourceHeight: Int, duration: Seconds, codec: String?) -> String {
        guard enabled else { return "Proxies are off in Settings" }
        if let codec, ProxySettings.intraCodecs.contains(codec) {
            return sourceHeight > 2160 ? "Above 4K — a proxy keeps playback smooth" : "\(codec.trimmingCharacters(in: .whitespaces)) decodes frame by frame, so no proxy is needed"
        }
        if sourceHeight > autoThresholdHeight { return "Above \(autoThresholdHeight)p long-GOP video — a proxy keeps playback smooth" }
        if duration > 2 * 3600 { return "Over two hours — a proxy keeps scrubbing light" }
        return "\(sourceHeight)p plays fine without a proxy"
    }
}

/// Resizable panel layout. Stored per workspace preset.
public struct WorkspaceLayout: Codable, Hashable, Sendable {
    public var leftPanelWidth: Double = 280
    public var rightPanelWidth: Double = 320
    public var timelineHeight: Double = 280
    public var showLeftPanel: Bool = true
    public var showRightPanel: Bool = true
    public var showTimeline: Bool = true
    public var showTranscript: Bool = true

    public init() {}
}

public enum WorkspacePreset: String, Codable, CaseIterable, Sendable {
    case editing, aiClips, captions, color, audio, export

    public var displayName: String {
        switch self {
        case .editing: return "Editing"
        case .aiClips: return "AI Clips"
        case .captions: return "Captions"
        case .color: return "Color"
        case .audio: return "Audio"
        case .export: return "Export"
        }
    }

    public var defaultLayout: WorkspaceLayout {
        var l = WorkspaceLayout()
        switch self {
        case .editing: break
        case .aiClips: l.showTimeline = false; l.leftPanelWidth = 340
        case .captions: l.showTranscript = true; l.rightPanelWidth = 360
        case .color: l.showTranscript = false; l.rightPanelWidth = 360
        case .audio: l.timelineHeight = 380; l.showTranscript = false
        case .export: l.showLeftPanel = false; l.timelineHeight = 200
        }
        return l
    }
}

/// App-wide preferences (persisted as JSON in Application Support).
public struct AppSettings: Codable, Hashable, Sendable {
    public var ai: AISettings = AISettings()
    public var proxy: ProxySettings = ProxySettings()
    public var mediaFolder: String = ""
    public var projectFolder: String = ""
    public var cacheFolder: String = ""
    public var exportFolder: String = ""
    public var autosaveInterval: TimeInterval = 30
    public var recoverySnapshotInterval: TimeInterval = 8
    public var backupsToKeep: Int = 10
    public var hasCompletedOnboarding: Bool = false
    public var workspaces: [String: WorkspaceLayout] = [:]
    public var currentWorkspace: WorkspacePreset = .editing
    public var sidebarCollapsed: Bool = false
    public var magneticTimeline: Bool = true
    public var snapping: Bool = true
    public var showSafeAreas: Bool = true
    public var safeAreaPlatform: SafeAreaPlatform = .tiktok
    /// Draw the platform's own buttons and caption block over the viewer, not just the safe-area frame (#67).
    public var showPlatformChrome: Bool = false
    public var defaultExportPresetID: String = ExportPreset.tiktok.id
    /// How the viewer shows time (#180).
    public var timecodeStyle: TimecodeStyle = .timecode
    /// ⌘T adds this at the selected clips' edges (#168).
    public var defaultTransitionKind: TransitionKind = .crossDissolve
    public var defaultTransitionDuration: Seconds = 0.4
    public var recentProjectPaths: [String] = []
    /// The answers from "Set up for my stream" (nil = never run).
    public var streamSetup: StreamSetup?
    /// Logo, intro/outro and caption look applied to new edits.
    public var brandKit: BrandKit = BrandKit()
    /// Editing styles measured from reference videos, newest first (reusable on any VOD).
    public var referenceStyles: [ReferenceStyle] = []
    /// The fingerprints of your last exports (#489), newest first — averaged into "my style".
    public var ownStyleSamples: [ReferenceStyle] = []
    /// AI multicam switching (#327): 0 = patient, 1 = eager; and whether cuts snap to the music's beats.
    public var multicamSensitivity: Double = 0.5
    public var multicamOnBeat: Bool = false
    /// Saved Ask PULSE sequences (#479).
    public var macros: [EditorMacro] = []
    /// Grades you saved from the inspector (#317).
    public var gradePresets: [GradePreset] = []
    /// What PULSE has done for you so far (#478).
    public var stats: LifetimeStats = LifetimeStats()
    /// A folder PULSE watches: anything dropped in is imported (#3).
    public var watchFolder: String = ""
    /// Tighter track heights (#182); timelines over 300 clips use them regardless.
    public var compactTimeline: Bool = false
    /// The timeline scrolls to keep the playhead in view while playing (#176).
    public var timelineFollowsPlayhead: Bool = true
    /// Batches wait while the Mac is on battery below 20 % (#389).
    public var batchPausesOnLowBattery: Bool = true
    /// Analyze what the watch folder brings in, straight away (#3).
    public var watchFolderAnalyzes: Bool = true
    /// Split recordings into files of at most this many gigabytes (#322); 0 = never.
    public var recordingSplitGB: Double = 0
    /// Hour (0–23) at which the batch runs on what the watch folder gathered that day; nil = never (#461).
    public var nightlyBatchHour: Int?
    /// Stable releases only, or betas too (#454).
    public var updateChannel: UpdateChannel = .stable
    /// The accent colour (#425).
    public var accent: AccentChoice = .pulse
    /// Dark, light or match macOS (#424).
    public var appearance: AppAppearance = .dark
    /// Viewer render size (#187); with `autoPlaybackQuality` PULSE drops a step on its own when playback can't keep up.
    public var playbackQuality: PlaybackQuality = .full
    public var autoPlaybackQuality: Bool = true
    /// A soft tick on every frame step (#198).
    public var scrubTick: Bool = false
    /// Ceiling for decoded thumbnails and filmstrip frames kept in memory (#377).
    public var thumbnailCacheMB: Int = 200
    /// Roles and sync behaviour applied to imports (#25).
    public var importPreset: ImportPreset = .auto
    /// After every finished export, write a thumbnail design for the edit to Thumbnail Studio (#357).
    public var thumbnailAfterExport: Bool = false
    /// Hear a blip of audio while dragging the playhead (#156).
    public var audioScrub: Bool = false
    /// How tall timeline tracks are (#148).
    public var trackHeight: TrackHeightPreset = .medium
    /// Custom menu shortcuts (#431).
    public var shortcuts: ShortcutMap = ShortcutMap()
    /// Fonts picked for text lately, newest first (#215).
    public var recentFonts: [String] = []
    /// Text looks saved from the inspector (#217).
    public var textTemplates: [TextTemplate] = []

    public init() {}

    /// Keeps a measured style (replacing an older one with the same name), newest first, at most 12.
    /// Saves a macro, replacing one with the same name (#479).
    public mutating func rememberMacro(_ macro: EditorMacro) {
        macros.removeAll { $0.id == macro.id || $0.name.caseInsensitiveCompare(macro.name) == .orderedSame }
        macros.insert(macro, at: 0)
        if macros.count > 40 { macros.removeLast(macros.count - 40) }
    }

    /// Keeps the fingerprint of a finished edit (#489): the last ten exports make up "my style".
    public mutating func noteOwnEdit(_ style: ReferenceStyle) {
        ownStyleSamples.insert(style, at: 0)
        if ownStyleSamples.count > 10 { ownStyleSamples.removeLast(ownStyleSamples.count - 10) }
    }

    /// The editing style of your own recent exports (#489), or nil before the first one.
    public var ownStyle: ReferenceStyle? {
        guard !ownStyleSamples.isEmpty else { return nil }
        let n = ownStyleSamples.count
        return ReferenceStyle.average(of: ownStyleSamples, name: n == 1 ? "My last video" : "My last \(n) videos")
    }

    public mutating func rememberStyle(_ style: ReferenceStyle) {
        referenceStyles.removeAll { $0.id == style.id || $0.name == style.name }
        referenceStyles.insert(style, at: 0)
        if referenceStyles.count > 12 { referenceStyles.removeLast(referenceStyles.count - 12) }
    }

    public func layout(for preset: WorkspacePreset) -> WorkspaceLayout {
        workspaces[preset.rawValue] ?? preset.defaultLayout
    }

    /// Keeps a font at the front of the recent list (#215), at most six.
    public mutating func noteRecentFont(_ name: String) {
        guard !name.isEmpty else { return }
        recentFonts.removeAll { $0 == name }
        recentFonts.insert(name, at: 0)
        if recentFonts.count > 6 { recentFonts.removeLast(recentFonts.count - 6) }
    }

    public mutating func noteRecentProject(_ path: String) {
        recentProjectPaths.removeAll { $0 == path }
        recentProjectPaths.insert(path, at: 0)
        if recentProjectPaths.count > 20 { recentProjectPaths.removeLast(recentProjectPaths.count - 20) }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        ai = c.decode(AISettings.self, forKey: .ai, default: d.ai)
        proxy = c.decode(ProxySettings.self, forKey: .proxy, default: d.proxy)
        mediaFolder = c.decode(String.self, forKey: .mediaFolder, default: d.mediaFolder)
        projectFolder = c.decode(String.self, forKey: .projectFolder, default: d.projectFolder)
        cacheFolder = c.decode(String.self, forKey: .cacheFolder, default: d.cacheFolder)
        exportFolder = c.decode(String.self, forKey: .exportFolder, default: d.exportFolder)
        autosaveInterval = c.decode(TimeInterval.self, forKey: .autosaveInterval, default: d.autosaveInterval)
        recoverySnapshotInterval = c.decode(TimeInterval.self, forKey: .recoverySnapshotInterval, default: d.recoverySnapshotInterval)
        backupsToKeep = c.decode(Int.self, forKey: .backupsToKeep, default: d.backupsToKeep)
        hasCompletedOnboarding = c.decode(Bool.self, forKey: .hasCompletedOnboarding, default: d.hasCompletedOnboarding)
        workspaces = c.decode([String: WorkspaceLayout].self, forKey: .workspaces, default: d.workspaces)
        currentWorkspace = c.decode(WorkspacePreset.self, forKey: .currentWorkspace, default: d.currentWorkspace)
        sidebarCollapsed = c.decode(Bool.self, forKey: .sidebarCollapsed, default: d.sidebarCollapsed)
        magneticTimeline = c.decode(Bool.self, forKey: .magneticTimeline, default: d.magneticTimeline)
        snapping = c.decode(Bool.self, forKey: .snapping, default: d.snapping)
        showSafeAreas = c.decode(Bool.self, forKey: .showSafeAreas, default: d.showSafeAreas)
        safeAreaPlatform = c.decode(SafeAreaPlatform.self, forKey: .safeAreaPlatform, default: d.safeAreaPlatform)
        brandKit = c.decode(BrandKit.self, forKey: .brandKit, default: d.brandKit)
        referenceStyles = c.decode([ReferenceStyle].self, forKey: .referenceStyles, default: d.referenceStyles)
        ownStyleSamples = c.decode([ReferenceStyle].self, forKey: .ownStyleSamples, default: d.ownStyleSamples)
        multicamSensitivity = c.decode(Double.self, forKey: .multicamSensitivity, default: d.multicamSensitivity)
        multicamOnBeat = c.decode(Bool.self, forKey: .multicamOnBeat, default: d.multicamOnBeat)
        macros = c.decode([EditorMacro].self, forKey: .macros, default: d.macros)
        gradePresets = c.decode([GradePreset].self, forKey: .gradePresets, default: d.gradePresets)
        stats = c.decode(LifetimeStats.self, forKey: .stats, default: d.stats)
        watchFolder = c.decode(String.self, forKey: .watchFolder, default: d.watchFolder)
        recordingSplitGB = c.decode(Double.self, forKey: .recordingSplitGB, default: d.recordingSplitGB)
        compactTimeline = c.decode(Bool.self, forKey: .compactTimeline, default: d.compactTimeline)
        timelineFollowsPlayhead = c.decode(Bool.self, forKey: .timelineFollowsPlayhead, default: d.timelineFollowsPlayhead)
        batchPausesOnLowBattery = c.decode(Bool.self, forKey: .batchPausesOnLowBattery, default: d.batchPausesOnLowBattery)
        updateChannel = c.decode(UpdateChannel.self, forKey: .updateChannel, default: d.updateChannel)
        accent = c.decode(AccentChoice.self, forKey: .accent, default: d.accent)
        appearance = c.decode(AppAppearance.self, forKey: .appearance, default: d.appearance)
        playbackQuality = c.decode(PlaybackQuality.self, forKey: .playbackQuality, default: d.playbackQuality)
        autoPlaybackQuality = c.decode(Bool.self, forKey: .autoPlaybackQuality, default: d.autoPlaybackQuality)
        scrubTick = c.decode(Bool.self, forKey: .scrubTick, default: d.scrubTick)
        thumbnailCacheMB = c.decode(Int.self, forKey: .thumbnailCacheMB, default: d.thumbnailCacheMB).clamped(50, 2000)
        importPreset = c.decode(ImportPreset.self, forKey: .importPreset, default: d.importPreset)
        thumbnailAfterExport = c.decode(Bool.self, forKey: .thumbnailAfterExport, default: d.thumbnailAfterExport)
        audioScrub = c.decode(Bool.self, forKey: .audioScrub, default: d.audioScrub)
        trackHeight = c.decode(TrackHeightPreset.self, forKey: .trackHeight, default: d.trackHeight)
        shortcuts = c.decode(ShortcutMap.self, forKey: .shortcuts, default: d.shortcuts)
        recentFonts = c.decode([String].self, forKey: .recentFonts, default: d.recentFonts)
        textTemplates = c.decode([TextTemplate].self, forKey: .textTemplates, default: d.textTemplates)
        showPlatformChrome = c.decode(Bool.self, forKey: .showPlatformChrome, default: d.showPlatformChrome)
        watchFolderAnalyzes = c.decode(Bool.self, forKey: .watchFolderAnalyzes, default: d.watchFolderAnalyzes)
        nightlyBatchHour = c.decode(Int?.self, forKey: .nightlyBatchHour, default: nil)
        defaultExportPresetID = c.decode(String.self, forKey: .defaultExportPresetID, default: d.defaultExportPresetID)
        recentProjectPaths = c.decode([String].self, forKey: .recentProjectPaths, default: d.recentProjectPaths)
        timecodeStyle = c.decode(TimecodeStyle.self, forKey: .timecodeStyle, default: d.timecodeStyle)
        defaultTransitionKind = c.decode(TransitionKind.self, forKey: .defaultTransitionKind, default: d.defaultTransitionKind)
        defaultTransitionDuration = c.decode(Seconds.self, forKey: .defaultTransitionDuration, default: d.defaultTransitionDuration)
        streamSetup = c.decode(StreamSetup?.self, forKey: .streamSetup, default: nil)
    }
}

/// Timeline track height (#148), as a multiplier on the standard lane sizes.
public enum TrackHeightPreset: String, Codable, CaseIterable, Sendable {
    case small, medium, large

    public var scale: Double {
        switch self {
        case .small: return 0.75
        case .medium: return 1
        case .large: return 1.45
        }
    }

    public var displayName: String { rawValue.capitalized }
}
