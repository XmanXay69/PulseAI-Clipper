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
    public var captionPresetName: String = "Bold"
    public var autoZoom: Bool = true
    public var autoCrop: Bool = true
    public var silenceRemoval: Bool = true
    public var silencePreset: SilencePreset = .conservative
    public var fillerRemoval: Bool = false
    public var aiSoundEffects: Bool = false
    public var aiMusic: Bool = false
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

    public init() {}

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
    public var defaultExportPresetID: String = ExportPreset.tiktok.id
    public var recentProjectPaths: [String] = []

    public init() {}

    public func layout(for preset: WorkspacePreset) -> WorkspaceLayout {
        workspaces[preset.rawValue] ?? preset.defaultLayout
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
        defaultExportPresetID = c.decode(String.self, forKey: .defaultExportPresetID, default: d.defaultExportPresetID)
        recentProjectPaths = c.decode([String].self, forKey: .recentProjectPaths, default: d.recentProjectPaths)
    }
}
