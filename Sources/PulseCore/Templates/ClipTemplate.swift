import Foundation

/// A reusable look: caption style, facecam layout & framing, colors, intro/outro text, SFX & music settings.
public struct ClipTemplate: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var captionStyle: CaptionStyle
    public var layout: LayoutPreset
    public var webcamStyle: LayerStyle
    public var canvasPresetID: String
    public var colorGrade: ColorAdjustments
    public var introText: String?
    public var outroText: String?
    public var titleStyle: TextStyle
    public var punchIns: Bool
    public var silencePreset: SilencePreset?
    public var musicVolume: Double
    public var duckMusic: Bool
    public var soundEffectsOnCuts: Bool
    public var isBuiltIn: Bool
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, captionStyle: CaptionStyle = .bold, layout: LayoutPreset = .splitScreen,
                webcamStyle: LayerStyle = .plain, canvasPresetID: String = CanvasPreset.tiktok.id, colorGrade: ColorAdjustments = .neutral,
                introText: String? = nil, outroText: String? = nil, titleStyle: TextStyle = TextStyle(fontSize: 80, weight: .black, textCase: .uppercase, strokeWidth: 8),
                punchIns: Bool = true, silencePreset: SilencePreset? = .conservative, musicVolume: Double = 0.3, duckMusic: Bool = true,
                soundEffectsOnCuts: Bool = false, isBuiltIn: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.captionStyle = captionStyle
        self.layout = layout
        self.webcamStyle = webcamStyle
        self.canvasPresetID = canvasPresetID
        self.colorGrade = colorGrade
        self.introText = introText
        self.outroText = outroText
        self.titleStyle = titleStyle
        self.punchIns = punchIns
        self.silencePreset = silencePreset
        self.musicVolume = musicVolume
        self.duckMusic = duckMusic
        self.soundEffectsOnCuts = soundEffectsOnCuts
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
    }

    public static let builtIns: [ClipTemplate] = [
        ClipTemplate(id: UUID(uuidString: "6B1B7A55-0000-4000-8000-000000000006")!, name: "TikTok Native", captionStyle: .tiktok, layout: .splitScreen, isBuiltIn: true),
        ClipTemplate(id: UUID(uuidString: "6B1B7A55-0000-4000-8000-000000000001")!, name: "Gaming Split", captionStyle: .gaming, layout: .splitScreen, isBuiltIn: true),
        ClipTemplate(id: UUID(uuidString: "6B1B7A55-0000-4000-8000-000000000002")!, name: "Facecam Corner", captionStyle: .bold, layout: .facecamCorner,
                     webcamStyle: LayerStyle(mask: .roundedRectangle, cornerRadius: 0.12, borderWidth: 6, borderColor: .white, shadowRadius: 18, shadowOpacity: 0.45, shadowOffsetY: 6), isBuiltIn: true),
        ClipTemplate(id: UUID(uuidString: "6B1B7A55-0000-4000-8000-000000000003")!, name: "Podcast Clean", captionStyle: .podcast, layout: .fullFrame, silencePreset: .balanced, isBuiltIn: true),
        ClipTemplate(id: UUID(uuidString: "6B1B7A55-0000-4000-8000-000000000004")!, name: "High Energy", captionStyle: .highEnergy, layout: .dynamic, silencePreset: .aggressive, soundEffectsOnCuts: true, isBuiltIn: true),
        ClipTemplate(id: UUID(uuidString: "6B1B7A55-0000-4000-8000-000000000005")!, name: "Cinematic", captionStyle: .cinematic, layout: .fullFrame,
                     colorGrade: { var c = ColorAdjustments(); c.contrast = 0.15; c.saturation = -0.1; c.vignette = 0.4; return c }(), punchIns: false, isBuiltIn: true),
    ]

    /// Applies the template to a timeline (every change is a normal, undoable edit).
    public func apply(to timeline: inout Timeline, context: LayoutContext?) {
        if var captions = timeline.captions {
            let keepPosition = captions.style.presetName == "Custom"
            let oldY = captions.style.positionY
            captions.style = captionStyle
            if keepPosition { captions.style.positionY = oldY }
            timeline.captions = captions
        }
        if let context {
            if layout.usesWebcam, context.webcamRegion != nil, let assetID = timeline.origin?.assetID {
                LayoutEngine.ensureWebcamLayer(in: &timeline, assetID: assetID)
            }
            LayoutEngine.apply(layout == .dynamic ? .splitScreen : layout, to: &timeline, context: context)
            timeline.layout = layout
            if layout == .facecamCorner || layout == .circleFacecam {
                for ti in timeline.tracks.indices {
                    for ci in timeline.tracks[ti].clips.indices where timeline.tracks[ti].clips[ci].role == .webcam {
                        var style = webcamStyle
                        if layout == .circleFacecam { style.mask = .circle }
                        if !style.isPlain { timeline.tracks[ti].clips[ci].style = style }
                    }
                }
            }
        }
        if !colorGrade.isIdentity {
            for ti in timeline.tracks.indices where timeline.tracks[ti].kind == .video {
                for ci in timeline.tracks[ti].clips.indices where timeline.tracks[ti].clips[ci].role != .webcam {
                    timeline.tracks[ti].clips[ci].color = colorGrade
                }
            }
        }
        if let introText, !introText.isEmpty, let ti = timeline.tracks.firstIndex(where: { $0.kind == .text }) {
            timeline.tracks[ti].clips.removeAll { $0.name == "Intro Title" }
            let element = TextElement(text: introText, style: titleStyle, animationIn: .pop, animationOut: .fadeIn)
            var clip = TimelineClip(name: "Intro Title", content: .text(element), start: 0, sourceDuration: min(2.5, max(timeline.duration, 0.5)))
            clip.transform.positionY = AnimatedDouble(0.18)
            timeline.tracks[ti].clips.append(clip)
            timeline.tracks[ti].sortClips()
        }
        if let outroText, !outroText.isEmpty, let ti = timeline.tracks.firstIndex(where: { $0.kind == .text }) {
            timeline.tracks[ti].clips.removeAll { $0.name == "Outro Title" }
            let d = timeline.duration
            let element = TextElement(text: outroText, style: titleStyle, animationIn: .fadeIn)
            var clip = TimelineClip(name: "Outro Title", content: .text(element), start: max(0, d - 2), sourceDuration: min(2, max(d, 0.5)))
            clip.transform.positionY = AnimatedDouble(0.45)
            timeline.tracks[ti].clips.append(clip)
            timeline.tracks[ti].sortClips()
        }
        for ti in timeline.tracks.indices where timeline.tracks[ti].kind == .audio {
            for ci in timeline.tracks[ti].clips.indices where timeline.tracks[ti].clips[ci].role == .music {
                timeline.tracks[ti].clips[ci].audio.volume = AnimatedDouble(musicVolume)
                timeline.tracks[ti].clips[ci].audio.duckUnderDialogue = duckMusic
            }
        }
        timeline.modifiedAt = Date()
    }

    /// Captures the look of an existing timeline as a new template ("Save as Template").
    public static func capture(from timeline: Timeline, name: String) -> ClipTemplate {
        let webcam = timeline.allClips.first { $0.role == .webcam }
        let main = timeline.allClips.first { $0.role == .gameplay || $0.role == .main }
        let music = timeline.allClips.first { $0.role == .music }
        let preset = CanvasPreset.all.first { $0.width == timeline.canvas.width && $0.height == timeline.canvas.height } ?? .tiktok
        let hasPunchIns = timeline.allClips.contains { $0.transform.zoom.isAnimated }
        var template = ClipTemplate(name: name, captionStyle: timeline.captions?.style ?? .bold, layout: timeline.layout ?? .fullFrame,
                                    webcamStyle: webcam?.style ?? .plain, canvasPresetID: preset.id, colorGrade: main?.color ?? .neutral,
                                    punchIns: hasPunchIns)
        if let music {
            template.musicVolume = music.audio.volume.value
            template.duckMusic = music.audio.duckUnderDialogue
        }
        return template
    }
}
