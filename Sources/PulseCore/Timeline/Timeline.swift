import Foundation

public enum TrackKind: String, Codable, CaseIterable, Sendable {
    case video
    case audio
    case text

    public var displayName: String {
        switch self {
        case .video: return "Video"
        case .audio: return "Audio"
        case .text: return "Text"
        }
    }

    public var shortPrefix: String {
        switch self {
        case .video: return "V"
        case .audio: return "A"
        case .text: return "T"
        }
    }

    /// Whether a clip with the given content may live on this track kind.
    public func accepts(_ content: ClipContent) -> Bool {
        switch (self, content) {
        case (.video, .media), (.video, .solid), (.video, .compound): return true
        case (.audio, .media), (.audio, .compound): return true
        case (.text, .text): return true
        default: return false
        }
    }
}

/// A clip placed on a track.
public struct TimelineClip: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var content: ClipContent
    /// Timeline position of the clip's first frame.
    public var start: Seconds
    /// First source frame used (media clips); 0 for generated content.
    public var sourceIn: Seconds
    /// Length of source consumed. Timeline duration is `sourceDuration / speed`.
    public var sourceDuration: Seconds
    public var speed: Double
    public var transform: VisualTransform
    public var style: LayerStyle
    /// Keyframed styles (layout morphs: a box rounding into a circle, borders fading in).
    public var styleKeyframes: [StyleKeyframe]
    public var color: ColorAdjustments
    public var effects: [EffectInstance]
    public var audio: AudioSettings
    public var transitionIn: ClipTransition?
    public var transitionOut: ClipTransition?
    /// Clips sharing a link group are edited together (e.g. gameplay + webcam + audio of one VOD).
    public var linkGroup: UUID?
    public var role: MediaRole?
    public var isEnabled: Bool
    /// True when this clip was placed by an AI pass (one-click short, auto edit, SFX…).
    public var aiGenerated: Bool
    public var labelColor: MarkerColor?

    public init(id: UUID = UUID(), name: String, content: ClipContent, start: Seconds, sourceIn: Seconds = 0,
                sourceDuration: Seconds, speed: Double = 1, transform: VisualTransform = .identity,
                style: LayerStyle = .plain, color: ColorAdjustments = .neutral, effects: [EffectInstance] = [],
                audio: AudioSettings = AudioSettings(), transitionIn: ClipTransition? = nil,
                transitionOut: ClipTransition? = nil, linkGroup: UUID? = nil, role: MediaRole? = nil,
                isEnabled: Bool = true, aiGenerated: Bool = false, labelColor: MarkerColor? = nil) {
        self.id = id
        self.name = name
        self.content = content
        self.start = start
        self.sourceIn = sourceIn
        self.sourceDuration = sourceDuration
        self.speed = speed
        self.transform = transform
        self.style = style
        self.styleKeyframes = []
        self.color = color
        self.effects = effects
        self.audio = audio
        self.transitionIn = transitionIn
        self.transitionOut = transitionOut
        self.linkGroup = linkGroup
        self.role = role
        self.isEnabled = isEnabled
        self.aiGenerated = aiGenerated
        self.labelColor = labelColor
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = c.decode(String.self, forKey: .name, default: "Clip")
        content = try c.decode(ClipContent.self, forKey: .content)
        start = c.decode(Seconds.self, forKey: .start, default: 0)
        sourceIn = c.decode(Seconds.self, forKey: .sourceIn, default: 0)
        sourceDuration = c.decode(Seconds.self, forKey: .sourceDuration, default: 1)
        speed = c.decode(Double.self, forKey: .speed, default: 1)
        transform = c.decode(VisualTransform.self, forKey: .transform, default: .identity)
        style = c.decode(LayerStyle.self, forKey: .style, default: .plain)
        styleKeyframes = c.decode([StyleKeyframe].self, forKey: .styleKeyframes, default: [])
        color = c.decode(ColorAdjustments.self, forKey: .color, default: .neutral)
        effects = c.decode([EffectInstance].self, forKey: .effects, default: [])
        audio = c.decode(AudioSettings.self, forKey: .audio, default: AudioSettings())
        transitionIn = c.decode(ClipTransition?.self, forKey: .transitionIn, default: nil)
        transitionOut = c.decode(ClipTransition?.self, forKey: .transitionOut, default: nil)
        linkGroup = c.decode(UUID?.self, forKey: .linkGroup, default: nil)
        role = c.decode(MediaRole?.self, forKey: .role, default: nil)
        isEnabled = c.decode(Bool.self, forKey: .isEnabled, default: true)
        aiGenerated = c.decode(Bool.self, forKey: .aiGenerated, default: false)
        labelColor = c.decode(MarkerColor?.self, forKey: .labelColor, default: nil)
    }

    public var duration: Seconds { sourceDuration / max(speed, 0.01) }
    public var end: Seconds { start + duration }
    public var sourceOut: Seconds { sourceIn + sourceDuration }
    public var timelineRange: TimeRange { TimeRange(start: start, end: end) }
    public var sourceRange: TimeRange { TimeRange(start: sourceIn, end: sourceOut) }
    public var assetID: UUID? { content.assetID }

    /// Maps a timeline time into this clip's source time.
    public func sourceTime(atTimeline t: Seconds) -> Seconds {
        sourceIn + (t - start) * speed
    }

    /// Maps a source time into timeline time.
    public func timelineTime(atSource s: Seconds) -> Seconds {
        start + (s - sourceIn) / max(speed, 0.01)
    }

    /// Clip-relative time for keyframe evaluation.
    public func localTime(atTimeline t: Seconds) -> Seconds {
        t - start
    }

    /// The layer style at clip time `t` (keyframed styles blend; otherwise `style`).
    public func style(at t: Seconds) -> LayerStyle {
        styleKeyframes.style(at: t) ?? style
    }

    public var isVisual: Bool {
        switch content {
        case .media, .solid, .text, .compound: return true
        }
    }
}

public struct Track: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: TrackKind
    public var name: String
    /// Clips sorted by `start`, never overlapping.
    public var clips: [TimelineClip]
    public var isMuted: Bool
    public var isLocked: Bool
    public var isHidden: Bool
    public var isSolo: Bool
    /// Linear track gain.
    public var volume: Double

    public init(id: UUID = UUID(), kind: TrackKind, name: String, clips: [TimelineClip] = [], isMuted: Bool = false,
                isLocked: Bool = false, isHidden: Bool = false, isSolo: Bool = false, volume: Double = 1) {
        self.id = id
        self.kind = kind
        self.name = name
        self.clips = clips.sorted { $0.start < $1.start }
        self.isMuted = isMuted
        self.isLocked = isLocked
        self.isHidden = isHidden
        self.isSolo = isSolo
        self.volume = volume
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = c.decode(TrackKind.self, forKey: .kind, default: .video)
        name = c.decode(String.self, forKey: .name, default: "Track")
        clips = c.decode([TimelineClip].self, forKey: .clips, default: []).sorted { $0.start < $1.start }
        isMuted = c.decode(Bool.self, forKey: .isMuted, default: false)
        isLocked = c.decode(Bool.self, forKey: .isLocked, default: false)
        isHidden = c.decode(Bool.self, forKey: .isHidden, default: false)
        isSolo = c.decode(Bool.self, forKey: .isSolo, default: false)
        volume = c.decode(Double.self, forKey: .volume, default: 1)
    }

    public var end: Seconds { clips.map(\.end).max() ?? 0 }

    public mutating func sortClips() {
        clips.sort { $0.start < $1.start }
    }
}

public enum MarkerColor: String, Codable, CaseIterable, Sendable {
    case red, orange, yellow, green, cyan, blue, purple, pink

    public var rgba: RGBAColor {
        switch self {
        case .red: return RGBAColor(hex: "#FF4D4F")!
        case .orange: return RGBAColor(hex: "#FF9F0A")!
        case .yellow: return RGBAColor(hex: "#FFD60A")!
        case .green: return RGBAColor(hex: "#32D74B")!
        case .cyan: return RGBAColor(hex: "#64D2FF")!
        case .blue: return RGBAColor(hex: "#0A84FF")!
        case .purple: return RGBAColor(hex: "#BF5AF2")!
        case .pink: return RGBAColor(hex: "#FF375F")!
        }
    }
}

public struct Marker: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var time: Seconds
    public var duration: Seconds
    public var name: String
    public var note: String
    public var color: MarkerColor
    public var aiGenerated: Bool

    public init(id: UUID = UUID(), time: Seconds, duration: Seconds = 0, name: String, note: String = "",
                color: MarkerColor = .blue, aiGenerated: Bool = false) {
        self.id = id
        self.time = time
        self.duration = duration
        self.name = name
        self.note = note
        self.color = color
        self.aiGenerated = aiGenerated
    }
}

/// Output frame of a timeline.
public struct CanvasSettings: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int
    public var frameRate: Double
    public var backgroundColor: RGBAColor
    /// Fill the background with a blurred, darkened copy of the main video instead of a flat color
    /// (shows wherever layers don't cover the frame, e.g. during layout morphs). Optional for old projects.
    public var backgroundBlur: Bool?

    public var blurFill: Bool { backgroundBlur ?? false }

    public init(width: Int, height: Int, frameRate: Double = 30, backgroundColor: RGBAColor = .black) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.backgroundColor = backgroundColor
    }

    public var size: Size2 { Size2(Double(width), Double(height)) }
    public var aspect: Double { size.aspect }
    public var frameDuration: Seconds { 1 / max(frameRate, 1) }

    public var aspectLabel: String {
        let ratio = aspect
        let known: [(Double, String)] = [(9.0 / 16.0, "9:16"), (1, "1:1"), (16.0 / 9.0, "16:9"), (4.0 / 5.0, "4:5"), (4.0 / 3.0, "4:3"), (21.0 / 9.0, "21:9")]
        if let match = known.first(where: { abs($0.0 - ratio) < 0.01 }) { return match.1 }
        return "\(width)×\(height)"
    }

    public static let vertical1080 = CanvasSettings(width: 1080, height: 1920, frameRate: 30)
    public static let landscape1080 = CanvasSettings(width: 1920, height: 1080, frameRate: 30)
    public static let square1080 = CanvasSettings(width: 1080, height: 1080, frameRate: 30)
    public static let portrait4x5 = CanvasSettings(width: 1080, height: 1350, frameRate: 30)
}

/// A section that an AI pass (or text-based edit) removed; kept so the user can restore it.
public struct RemovedSection: Codable, Hashable, Identifiable, Sendable {
    public enum Reason: String, Codable, Sendable {
        case silence
        case fillerWord
        case transcriptEdit
        case manual

        public var displayName: String {
            switch self {
            case .silence: return "Silence"
            case .fillerWord: return "Filler word"
            case .transcriptEdit: return "Transcript edit"
            case .manual: return "Manual"
            }
        }
    }

    public var id: UUID
    public var assetID: UUID
    public var sourceRange: TimeRange
    public var reason: Reason
    public var text: String?
    public var aiGenerated: Bool

    public init(id: UUID = UUID(), assetID: UUID, sourceRange: TimeRange, reason: Reason, text: String? = nil, aiGenerated: Bool = false) {
        self.id = id
        self.assetID = assetID
        self.sourceRange = sourceRange
        self.reason = reason
        self.text = text
        self.aiGenerated = aiGenerated
    }
}

/// Where a timeline came from (a clip candidate cut from a long recording).
public struct TimelineOrigin: Codable, Hashable, Sendable {
    public var candidateID: UUID?
    public var assetID: UUID
    public var sourceRange: TimeRange

    public init(candidateID: UUID?, assetID: UUID, sourceRange: TimeRange) {
        self.candidateID = candidateID
        self.assetID = assetID
        self.sourceRange = sourceRange
    }
}

/// A switch to another layout at a point of the timeline, animated over `duration`.
public struct LayoutChange: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// Timeline time the morph starts.
    public var time: Seconds
    public var preset: LayoutPreset
    /// Morph length (0 = hard cut).
    public var duration: Seconds
    public var aiGenerated: Bool

    public init(id: UUID = UUID(), time: Seconds, preset: LayoutPreset, duration: Seconds = 0.5, aiGenerated: Bool = false) {
        self.id = id
        self.time = time
        self.preset = preset
        self.duration = duration
        self.aiGenerated = aiGenerated
    }
}

/// An editable sequence (one short, or a long-form edit).
public struct Timeline: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var canvas: CanvasSettings
    public var tracks: [Track]
    public var captions: CaptionTrack?
    public var markers: [Marker]
    public var layout: LayoutPreset?
    /// Layout changes over time (each morphs smoothly from the layout before it). Empty = `layout` throughout.
    public var layoutChanges: [LayoutChange]
    public var origin: TimelineOrigin?
    public var removedSections: [RemovedSection]
    public var aiFramingEnabled: Bool
    public var createdAt: Date
    public var modifiedAt: Date
    public var notes: String
    /// Suggested titles/captions carried over from the candidate.
    public var copy: ClipCopy?

    public init(id: UUID = UUID(), name: String, canvas: CanvasSettings = .vertical1080, tracks: [Track] = [],
                captions: CaptionTrack? = nil, markers: [Marker] = [], layout: LayoutPreset? = nil,
                origin: TimelineOrigin? = nil, removedSections: [RemovedSection] = [], aiFramingEnabled: Bool = true,
                createdAt: Date = Date(), modifiedAt: Date = Date(), notes: String = "", copy: ClipCopy? = nil) {
        self.id = id
        self.name = name
        self.canvas = canvas
        self.tracks = tracks
        self.captions = captions
        self.markers = markers
        self.layout = layout
        self.layoutChanges = []
        self.origin = origin
        self.removedSections = removedSections
        self.aiFramingEnabled = aiFramingEnabled
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.notes = notes
        self.copy = copy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = c.decode(String.self, forKey: .name, default: "Timeline")
        canvas = c.decode(CanvasSettings.self, forKey: .canvas, default: .vertical1080)
        tracks = c.decode([Track].self, forKey: .tracks, default: [])
        captions = c.decode(CaptionTrack?.self, forKey: .captions, default: nil)
        markers = c.decode([Marker].self, forKey: .markers, default: [])
        layout = c.decode(LayoutPreset?.self, forKey: .layout, default: nil)
        layoutChanges = c.decode([LayoutChange].self, forKey: .layoutChanges, default: [])
        origin = c.decode(TimelineOrigin?.self, forKey: .origin, default: nil)
        removedSections = c.decode([RemovedSection].self, forKey: .removedSections, default: [])
        aiFramingEnabled = c.decode(Bool.self, forKey: .aiFramingEnabled, default: true)
        createdAt = c.decode(Date.self, forKey: .createdAt, default: Date())
        modifiedAt = c.decode(Date.self, forKey: .modifiedAt, default: Date())
        notes = c.decode(String.self, forKey: .notes, default: "")
        copy = c.decode(ClipCopy?.self, forKey: .copy, default: nil)
    }

    /// Standard empty editing timeline: V1, V2, T1, A1, A2.
    public static func empty(name: String, canvas: CanvasSettings) -> Timeline {
        Timeline(name: name, canvas: canvas, tracks: [
            Track(kind: .video, name: "V1"),
            Track(kind: .video, name: "V2"),
            Track(kind: .text, name: "T1"),
            Track(kind: .audio, name: "A1"),
            Track(kind: .audio, name: "A2"),
        ])
    }

    public var duration: Seconds {
        tracks.map(\.end).max() ?? 0
    }

    public var allClips: [TimelineClip] {
        tracks.flatMap(\.clips)
    }

    /// Video tracks bottom → top (first = V1 = bottom-most layer).
    public var videoTracks: [Track] { tracks.filter { $0.kind == .video } }
    public var audioTracks: [Track] { tracks.filter { $0.kind == .audio } }
    public var textTracks: [Track] { tracks.filter { $0.kind == .text } }

    public var assetIDs: Set<UUID> {
        Set(allClips.compactMap(\.assetID))
    }

    public var hasAIContent: Bool {
        allClips.contains { $0.aiGenerated || $0.transform.hasKeyframes && $0.transform.zoom.hasAIKeyframes }
            || captions?.aiGenerated == true
            || markers.contains { $0.aiGenerated }
            || removedSections.contains { $0.aiGenerated }
    }
}
