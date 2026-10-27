import Foundation

/// Progress status shown on project cards.
/// Where a project is on the way out the door (#474): the status board's columns. Set by hand on the board;
/// until then it follows what the project contains (exported → Exported, anything with an edit → Editing).
public enum WorkflowStage: String, Codable, CaseIterable, Sendable {
    case editing, ready, exported, posted

    public var displayName: String {
        switch self {
        case .editing: return "Editing"
        case .ready: return "Ready"
        case .exported: return "Exported"
        case .posted: return "Posted"
        }
    }

    public var symbol: String {
        switch self {
        case .editing: return "scissors"
        case .ready: return "checkmark.seal"
        case .exported: return "square.and.arrow.up"
        case .posted: return "paperplane"
        }
    }

    /// The column a project lands in when nobody has placed it (#474).
    public static func derived(from status: ProjectStatus) -> WorkflowStage {
        status == .exported ? .exported : .editing
    }
}

public enum ProjectStatus: String, Codable, Sendable {
    case empty
    case imported
    case analyzing
    case clipsReady
    case editing
    case exported

    public var displayName: String {
        switch self {
        case .empty: return "Empty"
        case .imported: return "Imported"
        case .analyzing: return "Analyzing"
        case .clipsReady: return "Clips ready"
        case .editing: return "Editing"
        case .exported: return "Exported"
        }
    }
}

/// The whole editable state of a project. Stored as `project.json` inside a `.pulse` package.
/// Large per-asset analysis (transcripts, feature series) lives in separate files.
public struct ProjectDocument: Codable, Hashable, Identifiable, Sendable {
    /// 1 = 1.0–1.5, 2 = 1.6 (snapshots, merged cards, import folder, extras answers).
    public static let schemaVersion = 2

    public var id: UUID
    public var schemaVersion: Int
    public var name: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var media: [MediaAsset]
    public var folders: [MediaFolder]
    public var timelines: [Timeline]
    /// Nested timelines referenced by compound clips (not listed as shorts).
    public var compounds: [Timeline]
    public var candidates: [ClipCandidate]
    public var templates: [ClipTemplate]
    public var exportSettings: ExportSettings
    public var generation: ClipGenerationSettings
    /// Which asset was analysed as the main long-form recording.
    public var primaryAssetID: UUID?
    public var activeTimelineID: UUID?
    /// Relative path of the thumbnail inside the package.
    public var thumbnailPath: String?
    public var isFavorite: Bool
    public var isTrashed: Bool
    public var notes: String
    public var exportCount: Int
    /// Named copies of timelines to go back to (#185).
    public var snapshots: [TimelineSnapshot] = []
    /// Where you last imported from for this project (#8).
    public var lastImportFolder: String = ""
    /// The Extras question was answered for this project (#128).
    public var extrasAnswered: Bool = false
    /// When this needs to be posted (#475).
    public var deadline: Date?
    /// Time spent with this project open and the app in front (#477).
    public var editingSeconds: Seconds = 0
    /// What to do when the loudness check finds a problem, remembered per project (#358): "fix" or "asIs".
    public var loudnessChoice: String?
    /// The status-board column you put this in (#474); nil = wherever its contents say.
    public var workflowStage: WorkflowStage?
    /// Settings this project pins instead of the app-wide ones (#445).
    public var overrides: ProjectOverrides = ProjectOverrides()

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.schemaVersion = ProjectDocument.schemaVersion
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.media = []
        self.folders = []
        self.timelines = []
        self.compounds = []
        self.candidates = []
        self.templates = []
        self.exportSettings = ExportSettings()
        self.generation = ClipGenerationSettings()
        self.primaryAssetID = nil
        self.activeTimelineID = nil
        self.thumbnailPath = nil
        self.isFavorite = false
        self.isTrashed = false
        self.notes = ""
        self.exportCount = 0
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        schemaVersion = c.decode(Int.self, forKey: .schemaVersion, default: ProjectDocument.schemaVersion)
        name = c.decode(String.self, forKey: .name, default: "Untitled Project")
        createdAt = c.decode(Date.self, forKey: .createdAt, default: Date())
        modifiedAt = c.decode(Date.self, forKey: .modifiedAt, default: Date())
        media = c.decode([MediaAsset].self, forKey: .media, default: [])
        folders = c.decode([MediaFolder].self, forKey: .folders, default: [])
        timelines = c.decode([Timeline].self, forKey: .timelines, default: [])
        compounds = c.decode([Timeline].self, forKey: .compounds, default: [])
        candidates = c.decode([ClipCandidate].self, forKey: .candidates, default: [])
        templates = c.decode([ClipTemplate].self, forKey: .templates, default: [])
        exportSettings = c.decode(ExportSettings.self, forKey: .exportSettings, default: ExportSettings())
        generation = c.decode(ClipGenerationSettings.self, forKey: .generation, default: ClipGenerationSettings())
        primaryAssetID = c.decode(UUID?.self, forKey: .primaryAssetID, default: nil)
        activeTimelineID = c.decode(UUID?.self, forKey: .activeTimelineID, default: nil)
        thumbnailPath = c.decode(String?.self, forKey: .thumbnailPath, default: nil)
        isFavorite = c.decode(Bool.self, forKey: .isFavorite, default: false)
        isTrashed = c.decode(Bool.self, forKey: .isTrashed, default: false)
        notes = c.decode(String.self, forKey: .notes, default: "")
        exportCount = c.decode(Int.self, forKey: .exportCount, default: 0)
        snapshots = c.decode([TimelineSnapshot].self, forKey: .snapshots, default: [])
        lastImportFolder = c.decode(String.self, forKey: .lastImportFolder, default: "")
        extrasAnswered = c.decode(Bool.self, forKey: .extrasAnswered, default: false)
        deadline = c.decode(Date?.self, forKey: .deadline, default: nil)
        workflowStage = c.decode(WorkflowStage?.self, forKey: .workflowStage, default: nil)
        overrides = c.decode(ProjectOverrides.self, forKey: .overrides, default: ProjectOverrides())
        editingSeconds = c.decode(Seconds.self, forKey: .editingSeconds, default: 0)
        loudnessChoice = c.decode(String?.self, forKey: .loudnessChoice, default: nil)
    }

    // MARK: Convenience

    public func asset(id: UUID) -> MediaAsset? { media.first { $0.id == id } }

    /// A short/edit or a compound clip's nested timeline.
    public func timeline(id: UUID) -> Timeline? { timelines.first { $0.id == id } ?? compounds.first { $0.id == id } }

    public func isCompound(_ id: UUID) -> Bool { compounds.contains { $0.id == id } }

    public var compoundsByID: [UUID: Timeline] { Dictionary(compounds.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }

    public var primaryAsset: MediaAsset? {
        primaryAssetID.flatMap { asset(id: $0) } ?? media.first { $0.kind == .video } ?? media.first
    }

    public var visibleCandidates: [ClipCandidate] { candidates.filter { $0.status != .dismissed } }

    public var status: ProjectStatus {
        if exportCount > 0 { return .exported }
        if !timelines.isEmpty { return .editing }
        if !candidates.isEmpty { return .clipsReady }
        if media.contains(where: { $0.preparation.analysisState == .running }) { return .analyzing }
        if !media.isEmpty { return .imported }
        return .empty
    }

    /// Summary used by the library/home screen without loading heavy files.
    public var summary: ProjectSummary {
        let main = primaryAsset
        return ProjectSummary(id: id, name: name, path: "", modifiedAt: modifiedAt, createdAt: createdAt,
                              duration: main?.metadata.duration ?? 0, resolution: main?.metadata.resolutionLabel ?? "—",
                              clipCount: visibleCandidates.count, timelineCount: timelines.count, status: status,
                              thumbnailPath: thumbnailPath, isFavorite: isFavorite, isTrashed: isTrashed,
                              deadline: deadline, editingSeconds: editingSeconds > 0 ? editingSeconds : nil, workflowStage: workflowStage)
    }

    public mutating func touch() {
        modifiedAt = Date()
    }

    public mutating func updateTimeline(id: UUID, _ body: (inout Timeline) -> Void) {
        if let i = timelines.firstIndex(where: { $0.id == id }) {
            body(&timelines[i])
            timelines[i].modifiedAt = Date()
        } else if let i = compounds.firstIndex(where: { $0.id == id }) {
            body(&compounds[i])
            compounds[i].modifiedAt = Date()
        } else {
            return
        }
        touch()
    }

    /// Throwing variant used by the editor for undoable edits of any timeline, nested or not.
    public mutating func editTimeline(id: UUID, _ body: (inout Timeline) throws -> Void) rethrows {
        if let i = timelines.firstIndex(where: { $0.id == id }) {
            try body(&timelines[i])
            timelines[i].modifiedAt = Date()
        } else if let i = compounds.firstIndex(where: { $0.id == id }) {
            try body(&compounds[i])
            compounds[i].modifiedAt = Date()
        }
    }

    public mutating func updateAsset(id: UUID, _ body: (inout MediaAsset) -> Void) {
        guard let i = media.firstIndex(where: { $0.id == id }) else { return }
        body(&media[i])
        touch()
    }
}

/// Lightweight project info for Home/Projects views and the library index.
public struct ProjectSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var path: String
    public var modifiedAt: Date
    public var createdAt: Date
    public var duration: Seconds
    public var resolution: String
    public var clipCount: Int
    public var timelineCount: Int
    public var status: ProjectStatus
    public var thumbnailPath: String?
    public var isFavorite: Bool
    public var isTrashed: Bool
    /// When this needs to be posted (#475).
    public var deadline: Date?
    /// Time spent editing (#477).
    public var editingSeconds: Seconds?
    /// The status-board column (#474), when placed by hand.
    public var workflowStage: WorkflowStage?

    /// The board column this project shows in (#474).
    public var boardStage: WorkflowStage { workflowStage ?? WorkflowStage.derived(from: status) }

    public init(id: UUID, name: String, path: String, modifiedAt: Date, createdAt: Date, duration: Seconds, resolution: String,
                clipCount: Int, timelineCount: Int, status: ProjectStatus, thumbnailPath: String?, isFavorite: Bool, isTrashed: Bool,
                deadline: Date? = nil, editingSeconds: Seconds? = nil, workflowStage: WorkflowStage? = nil) {
        self.deadline = deadline
        self.editingSeconds = editingSeconds
        self.workflowStage = workflowStage
        self.id = id
        self.name = name
        self.path = path
        self.modifiedAt = modifiedAt
        self.createdAt = createdAt
        self.duration = duration
        self.resolution = resolution
        self.clipCount = clipCount
        self.timelineCount = timelineCount
        self.status = status
        self.thumbnailPath = thumbnailPath
        self.isFavorite = isFavorite
        self.isTrashed = isTrashed
    }
}

/// Per-project settings (#445): each is nil to follow the app setting, or a value this project keeps whatever
/// Settings says — the export preset, the target platform's safe area, the loudness target and the caption look.
public struct ProjectOverrides: Codable, Hashable, Sendable {
    public var exportPresetID: String?
    public var safeAreaPlatform: SafeAreaPlatform?
    public var loudnessTarget: Double?
    public var captionPresetName: String?

    public init(exportPresetID: String? = nil, safeAreaPlatform: SafeAreaPlatform? = nil, loudnessTarget: Double? = nil, captionPresetName: String? = nil) {
        self.exportPresetID = exportPresetID
        self.safeAreaPlatform = safeAreaPlatform
        self.loudnessTarget = loudnessTarget
        self.captionPresetName = captionPresetName
    }

    public var isEmpty: Bool { exportPresetID == nil && safeAreaPlatform == nil && loudnessTarget == nil && captionPresetName == nil }

    /// How many settings this project pins.
    public var count: Int { [exportPresetID != nil, safeAreaPlatform != nil, loudnessTarget != nil, captionPresetName != nil].filter { $0 }.count }
}
