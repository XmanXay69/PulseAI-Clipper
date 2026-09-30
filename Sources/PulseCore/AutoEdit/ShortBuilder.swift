import Foundation

/// Options for "Create Short" (one click) and "Auto Edit" (more aggressive).
public struct ShortBuildOptions: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case oneClick
        case autoEdit
    }

    public var mode: Mode
    public var canvasPresetID: String
    /// nil = source frame rate (capped at 60).
    public var frameRate: Double?
    /// nil = recommended for the detected content.
    public var layout: LayoutPreset?
    public var captionStyle: CaptionStyle
    public var captionsEnabled: Bool
    public var emphasizeWords: Bool
    public var aiFraming: Bool
    public var punchIns: Bool
    public var punchInSettings: PunchInSettings
    public var silence: SilencePreset?
    public var removeFillers: Bool
    public var normalizeAudio: Bool
    public var voiceEnhance: Bool
    public var soundEffects: Bool
    public var musicAssetID: UUID?
    public var profanity: ProfanityMode

    public init(mode: Mode = .oneClick, canvasPresetID: String = CanvasPreset.tiktok.id, frameRate: Double? = nil, layout: LayoutPreset? = nil,
                captionStyle: CaptionStyle = .bold, captionsEnabled: Bool = true, emphasizeWords: Bool = true, aiFraming: Bool = true,
                punchIns: Bool = true, punchInSettings: PunchInSettings = PunchInSettings(), silence: SilencePreset? = .conservative,
                removeFillers: Bool = false, normalizeAudio: Bool = true, voiceEnhance: Bool = false, soundEffects: Bool = false,
                musicAssetID: UUID? = nil, profanity: ProfanityMode = .off) {
        self.mode = mode
        self.canvasPresetID = canvasPresetID
        self.frameRate = frameRate
        self.layout = layout
        self.captionStyle = captionStyle
        self.captionsEnabled = captionsEnabled
        self.emphasizeWords = emphasizeWords
        self.aiFraming = aiFraming
        self.punchIns = punchIns
        self.punchInSettings = punchInSettings
        self.silence = silence
        self.removeFillers = removeFillers
        self.normalizeAudio = normalizeAudio
        self.voiceEnhance = voiceEnhance
        self.soundEffects = soundEffects
        self.musicAssetID = musicAssetID
        self.profanity = profanity
    }

    public static let oneClick = ShortBuildOptions()

    public static var autoEdit: ShortBuildOptions {
        var o = ShortBuildOptions(mode: .autoEdit)
        o.silence = .balanced
        o.removeFillers = true
        o.voiceEnhance = true
        o.soundEffects = true
        o.captionStyle = .highEnergy
        o.punchInSettings.minimumSpacing = 3
        return o
    }

    /// Derives options from the user's AI settings.
    public init(settings: AISettings, mode: Mode = .oneClick) {
        self.init(mode: mode)
        captionStyle = CaptionStyle.preset(named: settings.captionPresetName) ?? .bold
        aiFraming = settings.aiFraming
        punchIns = settings.autoZoom
        silence = settings.silenceRemoval ? settings.silencePreset : nil
        removeFillers = settings.fillerRemoval
        soundEffects = settings.aiSoundEffects
        if mode == .autoEdit {
            silence = settings.silenceRemoval ? .balanced : nil
            removeFillers = true
            voiceEnhance = true
            punchInSettings.minimumSpacing = 3
        }
    }
}

/// Everything needed to build a short from a candidate.
public struct ShortBuildInput: Sendable {
    public var candidate: ClipCandidate
    public var asset: MediaAsset
    public var analysis: MediaAnalysis?
    /// User SFX library (role .soundEffect) — used only when options.soundEffects is on.
    public var soundEffects: [MediaAsset]
    public var music: MediaAsset?
    /// Separate facecam recording of the same session (screen recording + webcam file).
    public var companionWebcam: MediaAsset?
    /// Separate microphone (or webcam-with-mic) recording that carries the voice.
    public var companionVoice: MediaAsset?
    /// Face position inside the companion webcam, when analyzed.
    public var companionFaceCenter: Vec2?

    public init(candidate: ClipCandidate, asset: MediaAsset, analysis: MediaAnalysis?, soundEffects: [MediaAsset] = [], music: MediaAsset? = nil,
                companionWebcam: MediaAsset? = nil, companionVoice: MediaAsset? = nil, companionFaceCenter: Vec2? = nil) {
        self.candidate = candidate
        self.asset = asset
        self.analysis = analysis
        self.soundEffects = soundEffects
        self.music = music
        self.companionWebcam = companionWebcam
        self.companionVoice = companionVoice
        self.companionFaceCenter = companionFaceCenter
    }

    /// Source time in `companion` that matches `time` in the main asset (both synced to one session clock).
    func companionTime(_ time: Seconds, _ companion: MediaAsset) -> Seconds {
        time + asset.syncOffset - companion.syncOffset
    }
}

/// Builds a fully editable short timeline from a clip candidate. The AI never renders anything:
/// it only arranges clips, crops, keyframes, captions and markers that the user can change.
public enum ShortBuilder {
    public static func build(_ input: ShortBuildInput, options: ShortBuildOptions) -> Timeline {
        let candidate = input.candidate
        let asset = input.asset
        let analysis = input.analysis
        let preset = CanvasPreset.preset(id: options.canvasPresetID) ?? .tiktok
        let sourceFPS = asset.metadata.frameRate > 1 ? asset.metadata.frameRate : 30
        let fps = options.frameRate ?? min(sourceFPS.rounded(), 60)
        var timeline = Timeline(name: candidate.title.isEmpty ? "Short" : candidate.title, canvas: preset.canvas(frameRate: fps))
        timeline.origin = TimelineOrigin(candidateID: candidate.id, assetID: asset.id, sourceRange: candidate.range)
        timeline.copy = candidate.copy
        timeline.aiFramingEnabled = options.aiFraming

        let profile = analysis?.profile ?? .unknown
        let isGameplay = profile == .gameplay || profile == .gameplayWithFacecam
        let group = UUID()
        let videoTrack = Track(kind: .video, name: isGameplay ? "V1 Gameplay" : "V1 Video")
        let textTrack = Track(kind: .text, name: "T1 Titles")
        let dialogueTrack = Track(kind: .audio, name: "A1 Dialogue")
        let musicTrack = Track(kind: .audio, name: "A2 Music")
        let sfxTrack = Track(kind: .audio, name: "A3 SFX")
        timeline.tracks = [videoTrack, textTrack, dialogueTrack, musicTrack, sfxTrack]

        if asset.metadata.hasVideo || asset.kind == .video {
            let video = TimelineClip(name: asset.name, content: .media(assetID: asset.id), start: 0, sourceIn: candidate.range.start,
                                     sourceDuration: candidate.range.duration, linkGroup: group, role: isGameplay ? .gameplay : .main, aiGenerated: true)
            timeline.tracks[0].clips = [video]
        }
        var audio = TimelineClip(name: asset.name, content: .media(assetID: asset.id), start: 0, sourceIn: candidate.range.start,
                                 sourceDuration: candidate.range.duration, linkGroup: group, role: .microphone, aiGenerated: true)
        audio.audio.normalize = options.normalizeAudio
        audio.audio.voiceEnhance = options.voiceEnhance
        if options.voiceEnhance { audio.audio.noiseReduction = 0.4 }
        let mainHasAudio = asset.metadata.hasAudio || asset.kind == .audio || asset.metadata.audioTrackCount > 0
        if let voice = input.companionVoice, voice.metadata.hasAudio,
           let voiceClip = companionClip(voice, input: input, candidate: candidate, group: group, role: .microphone) {
            // The voice comes from its own recording; the main file's sound (game audio) sits underneath.
            var dialogue = voiceClip
            dialogue.name = "\(voice.name) (voice)"
            dialogue.audio.normalize = options.normalizeAudio
            dialogue.audio.voiceEnhance = options.voiceEnhance
            if options.voiceEnhance { dialogue.audio.noiseReduction = 0.4 }
            timeline.tracks[2].clips = [dialogue]
            if mainHasAudio {
                var game = audio
                game.name = "\(asset.name) (game audio)"
                game.role = .gameplay
                game.audio.normalize = false
                game.audio.voiceEnhance = false
                game.audio.noiseReduction = 0
                game.audio.volume = AnimatedDouble(0.5)
                game.audio.duckUnderDialogue = true
                var gameTrack = Track(kind: .audio, name: "A4 Game Audio")
                gameTrack.clips = [game]
                timeline.tracks.append(gameTrack)
            }
        } else if mainHasAudio {
            timeline.tracks[2].clips = [audio]
        }

        // Layout.
        var context = LayoutContext(analysis: analysis, sourceSize: asset.metadata.size.isEmpty ? Size2(1920, 1080) : asset.metadata.size)
        var companionCam: TimelineClip?
        if let cam = input.companionWebcam, cam.metadata.hasVideo,
           let clip = companionClip(cam, input: input, candidate: candidate, group: group, role: .webcam) {
            companionCam = clip
            context.webcamSourceSize = cam.metadata.size.isEmpty ? Size2(1280, 720) : cam.metadata.size
            context.webcamFaceCenter = input.companionFaceCenter
            context.webcamRegion = .full
        }
        let hasWebcam = context.webcamRegion != nil
        var layout = options.layout ?? LayoutEngine.recommendedLayout(for: companionCam != nil ? .gameplayWithFacecam : profile, hasWebcam: hasWebcam)
        if companionCam != nil && layout == .dynamic { layout = .splitScreen }
        if let companionCam, layout.usesWebcam {
            var camTrack = Track(kind: .video, name: "V2 Facecam")
            var cam = companionCam
            cam.name = "Facecam"
            camTrack.clips = [cam]
            timeline.tracks.insert(camTrack, at: 1)
        } else if layout.usesWebcam && hasWebcam {
            LayoutEngine.ensureWebcamLayer(in: &timeline, assetID: asset.id)
        }
        LayoutEngine.apply(layout == .dynamic ? .splitScreen : layout, to: &timeline, context: context)
        timeline.layout = layout

        let signals: EngagementSignals? = analysis.map {
            EngagementModel.compute(duration: $0.duration, audio: $0.audio, transcript: $0.transcript, visual: $0.visual)
        }
        if layout == .dynamic, hasWebcam, let signals {
            applyDynamicLayout(to: &timeline, assetID: asset.id, range: candidate.range, signals: signals, context: context)
        }

        // Dead air & fillers — recorded as restorable removed sections.
        if let silencePreset = options.silence {
            let silences = SilenceDetector.detect(audio: analysis?.audio, transcript: analysis?.transcript, in: candidate.range, preset: silencePreset)
            if !silences.isEmpty {
                timeline.removeSourceRanges(silences, assetID: asset.id, reason: .silence, aiGenerated: true)
            }
        }
        if options.removeFillers, let transcript = analysis?.transcript {
            let fillers = FillerWordDetector.detect(in: transcript, range: candidate.range, minimumConfidence: 0.75)
                .filter { $0.kind == .hesitation || $0.kind == .repetition }
            if !fillers.isEmpty {
                let ranges = FillerWordDetector.cutRanges(for: fillers, in: transcript)
                timeline.removeSourceRanges(ranges, assetID: asset.id, reason: .fillerWord, texts: fillers.map(\.text), aiGenerated: true)
            }
        }

        // Captions.
        if options.captionsEnabled, let transcript = analysis?.transcript, !transcript.isEmpty {
            var style = options.captionStyle
            if style.safeArea != nil { style.safeArea = preset.safeArea ?? style.safeArea }
            if layout == .splitScreen || layout == .dynamic, timeline.canvas.aspect < 1 {
                // Sit on the seam between gameplay and facecam — the classic streamer-short look.
                style.positionY = 0.58
            }
            var track = CaptionTrack.make(from: transcript, range: candidate.range, assetID: asset.id, style: style, emphasize: options.emphasizeWords)
            track.profanity = options.profanity
            timeline.captions = track
        }

        // AI framing (full-frame only: layouts with slots are already framed).
        if options.aiFraming, layout == .fullFrame, let faces = analysis?.visual?.faces, !faces.isEmpty {
            for ci in timeline.tracks[0].clips.indices {
                AutoReframer.applyFaceTracking(to: &timeline.tracks[0].clips[ci], faces: faces)
            }
        }

        // Punch-ins on the face panel when present, else the main picture.
        let payoffTimeline = timeline.timelineRanges(forSource: TimeRange(start: candidate.payoffTime, duration: 0.05), assetID: asset.id).first?.start
        if options.punchIns {
            var moments: [PunchInGenerator.Moment] = []
            if let payoffTimeline { moments.append(.reaction(payoffTimeline)) }
            if let captions = timeline.captions {
                for w in CaptionLayoutEngine.timelineWords(captions, in: timeline) where w.isEmphasized {
                    moments.append(.punchline(w.start))
                }
            }
            let faceTrack = timeline.tracks.first { t in t.kind == .video && t.clips.contains { $0.role == .webcam && $0.isEnabled } }
            let target = faceTrack?.id ?? timeline.tracks[0].id
            PunchInGenerator.apply(moments: moments, to: &timeline, trackID: target, settings: options.punchInSettings)
        }

        // Markers.
        timeline.markers.append(Marker(time: 0, name: "Hook", note: candidate.hook?.message ?? "", color: .green, aiGenerated: true))
        if let payoffTimeline {
            timeline.markers.append(Marker(time: payoffTimeline, name: "Payoff", note: "Peak moment detected by PULSE", color: .pink, aiGenerated: true))
        }

        // Sound effects (only from the user's own library).
        if options.soundEffects, let payoffTimeline, let sfx = pickSoundEffect(input.soundEffects, preferring: ["impact", "boom", "hit", "pop", "whoosh"]) {
            let duration = min(max(sfx.metadata.duration, 0.3), 2.5)
            var clip = TimelineClip(name: sfx.name, content: .media(assetID: sfx.id), start: max(0, payoffTimeline - 0.05), sourceDuration: duration,
                                    role: .soundEffect, aiGenerated: true)
            clip.audio.volume = AnimatedDouble(0.6)
            if let ti = timeline.tracks.firstIndex(where: { $0.name.hasPrefix("A3") }) {
                timeline.tracks[ti].clips.append(clip)
            }
        }

        // Music bed with ducking.
        if let music = input.music, let ti = timeline.tracks.firstIndex(where: { $0.name.hasPrefix("A2") }) {
            let total = timeline.duration
            let length = music.metadata.duration > 0 ? min(music.metadata.duration, total) : total
            var clip = TimelineClip(name: music.name, content: .media(assetID: music.id), start: 0, sourceDuration: length, role: .music, aiGenerated: true)
            clip.audio.volume = AnimatedDouble(0.35)
            clip.audio.duckUnderDialogue = true
            clip.audio.fadeIn = 0.6
            clip.audio.fadeOut = 1.2
            timeline.tracks[ti].clips = [clip]
        }

        timeline.modifiedAt = Date()
        return timeline
    }

    /// A clip of a companion recording covering the candidate, linked to the main clips.
    static func companionClip(_ companion: MediaAsset, input: ShortBuildInput, candidate: ClipCandidate, group: UUID, role: MediaRole) -> TimelineClip? {
        let start = input.companionTime(candidate.range.start, companion)
        let end = input.companionTime(candidate.range.end, companion)
        let clippedStart = max(0, start)
        let clippedEnd = companion.metadata.duration > 0 ? min(end, companion.metadata.duration) : end
        guard clippedEnd - clippedStart > 0.1 else { return nil }
        return TimelineClip(name: companion.name, content: .media(assetID: companion.id), start: clippedStart - start,
                            sourceIn: clippedStart, sourceDuration: clippedEnd - clippedStart, linkGroup: group, role: role, aiGenerated: true)
    }

    static func pickSoundEffect(_ library: [MediaAsset], preferring keywords: [String]) -> MediaAsset? {
        let sfx = library.filter { $0.role == .soundEffect || $0.category == .sfx }
        for k in keywords {
            if let match = sfx.first(where: { $0.name.lowercased().contains(k) || $0.tags.contains(k) }) { return match }
        }
        return sfx.first
    }

    /// Splits the main/webcam clips at AI layout switch points and lays out each segment.
    static func applyDynamicLayout(to timeline: inout Timeline, assetID: UUID, range: TimeRange, signals: EngagementSignals, context: LayoutContext) {
        let segments = DynamicLayoutPlanner.plan(range: range, signals: signals)
        guard segments.count > 1 else { return }
        // Cut at each boundary (source → timeline time through the first video clip).
        for seg in segments.dropFirst() {
            if let t = timeline.timelineRanges(forSource: TimeRange(start: seg.range.start, duration: 0.01), assetID: assetID).first?.start {
                let ids = timeline.allClips.filter { $0.assetID == assetID && $0.timelineRange.contains(t) }.map(\.id)
                _ = try? timeline.split(at: t, clipIDs: ids)
            }
        }
        for seg in segments {
            let ids = Set(timeline.allClips.filter { $0.assetID == assetID && seg.range.contains(($0.sourceIn + $0.sourceOut) / 2) }.map(\.id))
            LayoutEngine.apply(seg.layout, to: &timeline, context: context, onlyClips: ids)
        }
        timeline.layout = .dynamic
    }
}

/// Volume envelopes that lower music/game audio under dialogue.
public enum DuckingPlanner {
    public struct Ramp: Hashable, Sendable {
        public var time: Seconds
        public var gain: Double
    }

    /// Returns gain points (timeline time) for a ducked clip given dialogue ranges (timeline time).
    public static func envelope(for clip: TimelineClip, dialogue: [TimeRange], attack: Seconds = 0.15, release: Seconds = 0.4) -> [Ramp] {
        let duck = pow(10, clip.audio.duckAmountDB / 20)
        let ranges = dialogue.map { $0.expanded(by: 0.1) }.merged(gap: 0.35)
        var ramps: [Ramp] = [Ramp(time: clip.start, gain: 1)]
        for r in ranges where r.overlaps(clip.timelineRange) {
            let s = max(r.start, clip.start)
            let e = min(r.end, clip.end)
            ramps.append(Ramp(time: max(clip.start, s - attack), gain: 1))
            ramps.append(Ramp(time: s, gain: duck))
            ramps.append(Ramp(time: e, gain: duck))
            ramps.append(Ramp(time: min(clip.end, e + release), gain: 1))
        }
        ramps.append(Ramp(time: clip.end, gain: 1))
        // Collapse duplicates / out-of-order points.
        var result: [Ramp] = []
        for ramp in ramps.sorted(by: { $0.time < $1.time }) {
            if let last = result.last, abs(last.time - ramp.time) < 0.001 {
                result[result.count - 1] = Ramp(time: ramp.time, gain: min(last.gain, ramp.gain))
            } else {
                result.append(ramp)
            }
        }
        return result
    }

    /// Dialogue ranges on the timeline from caption words (or clips with microphone role).
    public static func dialogueRanges(in timeline: Timeline) -> [TimeRange] {
        if let captions = timeline.captions {
            return CaptionLayoutEngine.timelineWords(captions, in: timeline).map { TimeRange(start: $0.start, end: $0.end) }.merged(gap: 0.3)
        }
        return timeline.allClips.filter { $0.role == .microphone }.map(\.timelineRange).merged()
    }
}
