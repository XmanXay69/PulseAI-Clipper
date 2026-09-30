import Foundation

public enum MediaKind: String, Codable, CaseIterable, Sendable {
    case video
    case audio
    case image

    public var displayName: String {
        switch self {
        case .video: return "Video"
        case .audio: return "Audio"
        case .image: return "Image"
        }
    }
}

/// Semantic role of a piece of media inside a short. Roles drive auto-layout.
public enum MediaRole: String, Codable, CaseIterable, Sendable {
    /// A single recording containing everything (e.g. a Twitch VOD with an embedded facecam).
    case main
    case gameplay
    case webcam
    case microphone
    case music
    case soundEffect
    case graphic
    case camera

    public var displayName: String {
        switch self {
        case .main: return "Main"
        case .gameplay: return "Gameplay"
        case .webcam: return "Webcam"
        case .microphone: return "Microphone"
        case .music: return "Music"
        case .soundEffect: return "Sound Effect"
        case .graphic: return "Graphic"
        case .camera: return "Camera"
        }
    }

    public var symbolName: String {
        switch self {
        case .main: return "film"
        case .gameplay: return "gamecontroller"
        case .webcam: return "web.camera"
        case .microphone: return "mic"
        case .music: return "music.note"
        case .soundEffect: return "speaker.wave.2"
        case .graphic: return "photo"
        case .camera: return "video"
        }
    }
}

/// Library bins used to organise media ("Videos", "Music", "SFX"…).
public enum MediaCategory: String, Codable, CaseIterable, Sendable {
    case videos, audio, images, music, sfx, graphics

    public var displayName: String {
        switch self {
        case .videos: return "Videos"
        case .audio: return "Audio"
        case .images: return "Images"
        case .music: return "Music"
        case .sfx: return "SFX"
        case .graphics: return "Graphics"
        }
    }
}

public struct MediaMetadata: Codable, Hashable, Sendable {
    public var duration: Seconds
    public var width: Int
    public var height: Int
    public var frameRate: Double
    public var hasVideo: Bool
    public var hasAudio: Bool
    public var audioTrackCount: Int
    public var audioChannels: Int
    public var audioSampleRate: Double
    public var videoCodec: String?
    public var audioCodec: String?
    public var fileSize: Int64
    public var creationDate: Date?

    public init(duration: Seconds = 0, width: Int = 0, height: Int = 0, frameRate: Double = 0,
                hasVideo: Bool = false, hasAudio: Bool = false, audioTrackCount: Int = 0,
                audioChannels: Int = 0, audioSampleRate: Double = 0, videoCodec: String? = nil,
                audioCodec: String? = nil, fileSize: Int64 = 0, creationDate: Date? = nil) {
        self.duration = duration
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.hasVideo = hasVideo
        self.hasAudio = hasAudio
        self.audioTrackCount = audioTrackCount
        self.audioChannels = audioChannels
        self.audioSampleRate = audioSampleRate
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.fileSize = fileSize
        self.creationDate = creationDate
    }

    public var size: Size2 { Size2(Double(width), Double(height)) }

    public var resolutionLabel: String {
        guard width > 0, height > 0 else { return "—" }
        let shortSide = min(width, height)
        switch shortSide {
        case 2160...: return "4K"
        case 1440..<2160: return "1440p"
        case 1080..<1440: return "1080p"
        case 720..<1080: return "720p"
        default: return "\(width)×\(height)"
        }
    }

    public var frameRateLabel: String {
        guard frameRate > 0 else { return "—" }
        if abs(frameRate - frameRate.rounded()) < 0.01 { return "\(Int(frameRate.rounded())) fps" }
        return String(format: "%.2f fps", frameRate)
    }
}

/// Status of the imported file on disk.
public enum MediaAvailability: String, Codable, Sendable {
    case online
    case missing
    case unsupported
    case corrupted
}

/// Status of background preparation for an asset.
public struct MediaPreparation: Codable, Hashable, Sendable {
    public var hasThumbnail: Bool = false
    public var hasWaveform: Bool = false
    public var proxyPath: String?
    public var analysisState: AnalysisState = .notStarted

    public init() {}

    public enum AnalysisState: String, Codable, Sendable {
        case notStarted
        case running
        case complete
        case failed
    }
}

/// A piece of media referenced by a project. Binaries are never copied into the database;
/// the asset stores a path (plus a security-scoped bookmark on macOS) to the original file.
public struct MediaAsset: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var path: String
    public var bookmark: Data?
    public var kind: MediaKind
    public var role: MediaRole
    public var category: MediaCategory
    public var metadata: MediaMetadata
    public var availability: MediaAvailability
    public var preparation: MediaPreparation
    public var tags: [String]
    public var isFavorite: Bool
    public var folderID: UUID?
    public var importedAt: Date
    /// Offset (seconds) applied when this asset is synchronised against another recording.
    public var syncOffset: Seconds
    /// Groups recordings of the same session (gameplay + webcam + mic).
    public var syncGroupID: UUID?
    /// Where this asset came from when it is a generated derivative (demo media, rendered audio…).
    public var generatedBy: String?

    public init(id: UUID = UUID(), name: String, path: String, bookmark: Data? = nil, kind: MediaKind,
                role: MediaRole = .main, category: MediaCategory? = nil, metadata: MediaMetadata = MediaMetadata(),
                availability: MediaAvailability = .online, tags: [String] = [], isFavorite: Bool = false,
                folderID: UUID? = nil, importedAt: Date = Date(), syncOffset: Seconds = 0, syncGroupID: UUID? = nil,
                generatedBy: String? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmark = bookmark
        self.kind = kind
        self.role = role
        self.category = category ?? MediaAsset.defaultCategory(kind: kind, role: role)
        self.metadata = metadata
        self.availability = availability
        self.preparation = MediaPreparation()
        self.tags = tags
        self.isFavorite = isFavorite
        self.folderID = folderID
        self.importedAt = importedAt
        self.syncOffset = syncOffset
        self.syncGroupID = syncGroupID
        self.generatedBy = generatedBy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = c.decode(String.self, forKey: .name, default: "Untitled")
        path = try c.decode(String.self, forKey: .path)
        bookmark = c.decode(Data?.self, forKey: .bookmark, default: nil)
        kind = c.decode(MediaKind.self, forKey: .kind, default: .video)
        role = c.decode(MediaRole.self, forKey: .role, default: .main)
        category = c.decode(MediaCategory.self, forKey: .category, default: MediaAsset.defaultCategory(kind: kind, role: role))
        metadata = c.decode(MediaMetadata.self, forKey: .metadata, default: MediaMetadata())
        availability = c.decode(MediaAvailability.self, forKey: .availability, default: .online)
        preparation = c.decode(MediaPreparation.self, forKey: .preparation, default: MediaPreparation())
        tags = c.decode([String].self, forKey: .tags, default: [])
        isFavorite = c.decode(Bool.self, forKey: .isFavorite, default: false)
        folderID = c.decode(UUID?.self, forKey: .folderID, default: nil)
        importedAt = c.decode(Date.self, forKey: .importedAt, default: Date())
        syncOffset = c.decode(Seconds.self, forKey: .syncOffset, default: 0)
        syncGroupID = c.decode(UUID?.self, forKey: .syncGroupID, default: nil)
        generatedBy = c.decode(String?.self, forKey: .generatedBy, default: nil)
    }

    public var url: URL { URL(fileURLWithPath: path) }
    public var fileExtension: String { (path as NSString).pathExtension.lowercased() }

    public static func defaultCategory(kind: MediaKind, role: MediaRole) -> MediaCategory {
        switch role {
        case .music: return .music
        case .soundEffect: return .sfx
        case .graphic: return .graphics
        default:
            switch kind {
            case .video: return .videos
            case .audio: return .audio
            case .image: return .images
            }
        }
    }
}

/// User-created folder in the media bin.
public struct MediaFolder: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var parentID: UUID?

    public init(id: UUID = UUID(), name: String, parentID: UUID? = nil) {
        self.id = id
        self.name = name
        self.parentID = parentID
    }
}
