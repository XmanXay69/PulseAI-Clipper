import Foundation

/// Your channel's look, applied to every new short and YouTube edit: a logo watermark, an intro and
/// outro (long-form only — intros hurt shorts), and a caption style + highlight color.
public struct BrandKit: Codable, Hashable, Sendable {
    public enum Corner: String, Codable, CaseIterable, Sendable {
        case topLeft, topRight, bottomLeft, bottomRight

        public var displayName: String {
            switch self {
            case .topLeft: return "Top Left"
            case .topRight: return "Top Right"
            case .bottomLeft: return "Bottom Left"
            case .bottomRight: return "Bottom Right"
            }
        }
    }

    public var enabled: Bool
    public var logoPath: String
    public var logoCorner: Corner
    /// Logo width as a fraction of the canvas width.
    public var logoSize: Double
    public var logoOpacity: Double
    public var introPath: String
    public var outroPath: String
    /// Caption preset for new edits ("" = keep the AI setting).
    public var captionPresetName: String
    public var highlightColor: RGBAColor?
    public var logoOnShorts: Bool
    public var logoOnLongForm: Bool

    public init() {
        enabled = false
        logoPath = ""
        logoCorner = .topRight
        logoSize = 0.14
        logoOpacity = 0.85
        introPath = ""
        outroPath = ""
        captionPresetName = ""
        highlightColor = nil
        logoOnShorts = true
        logoOnLongForm = true
    }

    public var hasAnything: Bool {
        !logoPath.isEmpty || !introPath.isEmpty || !outroPath.isEmpty || !captionPresetName.isEmpty || highlightColor != nil
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BrandKit()
        enabled = c.decode(Bool.self, forKey: .enabled, default: d.enabled)
        logoPath = c.decode(String.self, forKey: .logoPath, default: d.logoPath)
        logoCorner = c.decode(Corner.self, forKey: .logoCorner, default: d.logoCorner)
        logoSize = c.decode(Double.self, forKey: .logoSize, default: d.logoSize)
        logoOpacity = c.decode(Double.self, forKey: .logoOpacity, default: d.logoOpacity)
        introPath = c.decode(String.self, forKey: .introPath, default: d.introPath)
        outroPath = c.decode(String.self, forKey: .outroPath, default: d.outroPath)
        captionPresetName = c.decode(String.self, forKey: .captionPresetName, default: d.captionPresetName)
        highlightColor = c.decode(RGBAColor?.self, forKey: .highlightColor, default: nil)
        logoOnShorts = c.decode(Bool.self, forKey: .logoOnShorts, default: d.logoOnShorts)
        logoOnLongForm = c.decode(Bool.self, forKey: .logoOnLongForm, default: d.logoOnLongForm)
    }
}

/// The brand kit's media, already in the project.
public struct BrandKitAssets: Sendable {
    public var logo: MediaAsset?
    public var intro: MediaAsset?
    public var outro: MediaAsset?

    public init(logo: MediaAsset? = nil, intro: MediaAsset? = nil, outro: MediaAsset? = nil) {
        self.logo = logo
        self.intro = intro
        self.outro = outro
    }
}

public enum BrandKitApplier {
    static let brandTrackName = "V Brand"
    static let margin = 0.035

    /// Applies the kit to a timeline. Re-applying replaces the previous logo / intro / outro instead of stacking.
    public static func apply(_ kit: BrandKit, assets: BrandKitAssets, to timeline: inout Timeline, longForm: Bool) {
        removeBrand(from: &timeline)

        // Captions.
        if var captions = timeline.captions {
            if !kit.captionPresetName.isEmpty, var preset = CaptionStyle.preset(named: kit.captionPresetName) {
                preset.positionY = captions.style.positionY
                captions.style = preset
            }
            if let color = kit.highlightColor { captions.style.highlightColor = color }
            timeline.captions = captions
        }

        // Intro / outro on YouTube edits.
        if longForm, let intro = assets.intro, intro.metadata.duration > 0.2 {
            insertBumper(intro, at: 0, name: "Intro", into: &timeline)
        }
        if longForm, let outro = assets.outro, outro.metadata.duration > 0.2 {
            insertBumper(outro, at: timeline.duration, name: "Outro", into: &timeline)
        }

        // Logo watermark over everything.
        if let logo = assets.logo, longForm ? kit.logoOnLongForm : kit.logoOnShorts, timeline.duration > 0 {
            let canvas = timeline.canvas.size
            let imageAspect = logo.metadata.size.isEmpty ? 1 : logo.metadata.size.aspect
            let w = kit.logoSize.clamped(0.04, 0.4)
            let h = w * canvas.width / canvas.height / imageAspect
            let x: Double = (kit.logoCorner == .topLeft || kit.logoCorner == .bottomLeft) ? margin : 1 - margin - w
            // Shorts keep the logo clear of the platform's top bar and bottom captions.
            let topInset = longForm ? margin : 0.09
            let bottomInset = longForm ? margin : 0.2
            let y: Double = (kit.logoCorner == .topLeft || kit.logoCorner == .topRight) ? topInset : 1 - bottomInset - h
            let slot = NormRect(x: x, y: y, width: w, height: h)
            let p = LayerGeometry.placement(fillingSlot: slot, cropAspect: imageAspect, canvasSize: canvas)
            var clip = TimelineClip(name: "Logo", content: .media(assetID: logo.id), start: 0, sourceDuration: timeline.duration, role: .graphic)
            clip.transform.positionX = AnimatedDouble(p.positionX)
            clip.transform.positionY = AnimatedDouble(p.positionY)
            clip.transform.scale = AnimatedDouble(p.scale)
            clip.transform.opacity = AnimatedDouble(kit.logoOpacity.clamped(0.1, 1))
            clip.transform.fit = .fit
            var track = Track(kind: .video, name: brandTrackName)
            track.clips = [clip]
            let lastVideo = timeline.tracks.lastIndex { $0.kind == .video } ?? -1
            timeline.tracks.insert(track, at: lastVideo + 1)
        }
        timeline.modifiedAt = Date()
    }

    /// Takes a previous kit back out (logo track, intro and outro bumpers).
    public static func removeBrand(from timeline: inout Timeline) {
        timeline.tracks.removeAll { $0.name == brandTrackName }
        for name in ["Intro", "Outro"] {
            let bumpers = timeline.allClips.filter { $0.name == name && $0.role == .graphic }
            guard let first = bumpers.first else { continue }
            let range = first.timelineRange
            timeline.rippleDelete(range: range)
        }
    }

    /// Ripple-inserts a bumper video (and its sound) at `time`.
    static func insertBumper(_ asset: MediaAsset, at time: Seconds, name: String, into timeline: inout Timeline) {
        let length = asset.metadata.duration
        for ti in timeline.tracks.indices {
            for ci in timeline.tracks[ti].clips.indices where timeline.tracks[ti].clips[ci].start >= time - TimeRange.epsilon {
                timeline.tracks[ti].clips[ci].start += length
            }
        }
        for i in timeline.markers.indices where timeline.markers[i].time >= time { timeline.markers[i].time += length }
        for i in timeline.layoutChanges.indices where timeline.layoutChanges[i].time >= time { timeline.layoutChanges[i].time += length }
        let group = UUID()
        if asset.metadata.hasVideo || asset.kind == .video, let v = timeline.tracks.firstIndex(where: { $0.kind == .video }) {
            var clip = TimelineClip(name: name, content: .media(assetID: asset.id), start: time, sourceDuration: length, linkGroup: group, role: .graphic)
            clip.transform.fit = .fit
            timeline.tracks[v].clips.append(clip)
            timeline.tracks[v].sortClips()
        }
        if asset.metadata.hasAudio, let a = timeline.tracks.firstIndex(where: { $0.kind == .audio }) {
            let clip = TimelineClip(name: name, content: .media(assetID: asset.id), start: time, sourceDuration: length, linkGroup: group, role: .graphic)
            timeline.tracks[a].clips.append(clip)
            timeline.tracks[a].sortClips()
        }
    }
}
