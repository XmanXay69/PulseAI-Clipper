import Foundation

/// Gameplay + webcam compositions for short-form canvases.
public enum LayoutPreset: String, Codable, CaseIterable, Sendable {
    /// One source fills the frame, AI-reframed.
    case fullFrame
    /// Gameplay fills the frame, small facecam in a corner.
    case facecamCorner
    /// Gameplay top, facecam bottom.
    case splitScreen
    /// Facecam large on top, gameplay below.
    case facecamDominant
    /// Gameplay background with a circular facecam bubble.
    case circleFacecam
    /// AI switches between layouts depending on what's happening.
    case dynamic

    public var displayName: String {
        switch self {
        case .fullFrame: return "Full Frame"
        case .facecamCorner: return "Gameplay + Facecam"
        case .splitScreen: return "Split Screen"
        case .facecamDominant: return "Facecam Dominant"
        case .circleFacecam: return "Circle Facecam"
        case .dynamic: return "Dynamic (AI)"
        }
    }

    public var symbolName: String {
        switch self {
        case .fullFrame: return "rectangle"
        case .facecamCorner: return "rectangle.inset.bottomleft.filled"
        case .splitScreen: return "rectangle.split.1x2"
        case .facecamDominant: return "rectangle.tophalf.inset.filled"
        case .circleFacecam: return "circle.rectangle.filled"
        case .dynamic: return "sparkles.rectangle.stack"
        }
    }

    public var usesWebcam: Bool { self != .fullFrame }
}

/// What the layout engine knows about the sources.
public struct LayoutContext: Sendable {
    public var sourceSize: Size2
    /// Webcam overlay region inside the main source (single-file VOD) — nil when unknown.
    public var webcamRegion: NormRect?
    /// Face inside the webcam/main source for centering.
    public var faceCenter: Vec2?
    /// Separate webcam recording size, when the webcam is its own file.
    public var webcamSourceSize: Size2?
    /// Face position inside the separate webcam recording.
    public var webcamFaceCenter: Vec2?
    public var profile: ContentProfile

    public init(sourceSize: Size2, webcamRegion: NormRect? = nil, faceCenter: Vec2? = nil, webcamSourceSize: Size2? = nil,
                webcamFaceCenter: Vec2? = nil, profile: ContentProfile = .unknown) {
        self.sourceSize = sourceSize
        self.webcamRegion = webcamRegion
        self.faceCenter = faceCenter
        self.webcamSourceSize = webcamSourceSize
        self.webcamFaceCenter = webcamFaceCenter
        self.profile = profile
    }

    public init(analysis: MediaAnalysis?, sourceSize: Size2) {
        self.init(sourceSize: sourceSize,
                  webcamRegion: analysis?.webcam?.profile == .gameplayWithFacecam ? analysis?.webcam?.region : nil,
                  faceCenter: analysis?.webcam?.face.center,
                  profile: analysis?.profile ?? .unknown)
    }
}

/// Where a layout places one clip.
public struct LayoutTarget: Hashable, Sendable {
    public var positionX: Double
    public var positionY: Double
    public var scale: Double
    public var crop: NormRect
    public var style: LayerStyle
    public var visible: Bool

    /// Writes the target as constant values (clearing layout animation).
    func write(to clip: inout TimelineClip) {
        clip.transform.crop = crop
        clip.transform.cropAnimation = nil
        clip.transform.fit = .fit
        clip.transform.positionX = AnimatedDouble(positionX)
        clip.transform.positionY = AnimatedDouble(positionY)
        clip.transform.scale = AnimatedDouble(scale)
        clip.style = style
        clip.styleKeyframes = []
    }

    /// This target's geometry, invisible and slightly smaller (how a facecam leaves or enters).
    func hidden(like other: LayoutTarget) -> LayoutTarget {
        var t = other
        t.scale *= 0.9
        t.visible = false
        return t
    }
}

/// Slots (normalized canvas rects) for each layout.
public struct LayoutSlots: Sendable {
    public var gameplay: NormRect
    public var webcam: NormRect?
    public var webcamMask: MaskShape
    public var webcamStyle: LayerStyle
}

public enum LayoutEngine {
    /// Recommended layout for detected content.
    public static func recommendedLayout(for profile: ContentProfile, hasWebcam: Bool) -> LayoutPreset {
        switch profile {
        case .gameplayWithFacecam: return .splitScreen
        case .talkingHead, .podcast: return .fullFrame
        case .gameplay: return hasWebcam ? .splitScreen : .fullFrame
        case .unknown: return hasWebcam ? .splitScreen : .fullFrame
        }
    }

    public static func slots(for preset: LayoutPreset, canvas: CanvasSettings, webcamAspect: Double = 16.0 / 9.0) -> LayoutSlots {
        let portrait = canvas.aspect < 1
        let cw = Double(canvas.width)
        let ch = Double(canvas.height)
        let framed = LayerStyle(mask: .roundedRectangle, cornerRadius: 0.1, borderWidth: 6, borderColor: .white, shadowRadius: 18, shadowOpacity: 0.45, shadowOffsetY: 6)
        switch preset {
        case .fullFrame:
            return LayoutSlots(gameplay: .full, webcam: nil, webcamMask: .rectangle, webcamStyle: .plain)
        case .splitScreen, .dynamic:
            if portrait {
                return LayoutSlots(gameplay: NormRect(x: 0, y: 0, width: 1, height: 0.58),
                                   webcam: NormRect(x: 0, y: 0.58, width: 1, height: 0.42), webcamMask: .rectangle, webcamStyle: .plain)
            }
            return LayoutSlots(gameplay: NormRect(x: 0, y: 0, width: 0.64, height: 1),
                               webcam: NormRect(x: 0.64, y: 0, width: 0.36, height: 1), webcamMask: .rectangle, webcamStyle: .plain)
        case .facecamDominant:
            if portrait {
                return LayoutSlots(gameplay: NormRect(x: 0, y: 0.6, width: 1, height: 0.4),
                                   webcam: NormRect(x: 0, y: 0, width: 1, height: 0.6), webcamMask: .rectangle, webcamStyle: .plain)
            }
            return LayoutSlots(gameplay: NormRect(x: 0.6, y: 0.5, width: 0.4, height: 0.5),
                               webcam: NormRect(x: 0, y: 0, width: 1, height: 1), webcamMask: .rectangle, webcamStyle: .plain)
        case .facecamCorner:
            // Webcam box ~44% of width (portrait) keeping the webcam's own aspect.
            let wFrac = portrait ? 0.44 : 0.26
            let wPx = wFrac * cw
            let hPx = wPx / max(webcamAspect, 0.5)
            let hFrac = hPx / ch
            let x = portrait ? 0.05 : 0.72
            let y = portrait ? 0.62 : 0.66
            return LayoutSlots(gameplay: .full, webcam: NormRect(x: x, y: min(y, 1 - hFrac - 0.02), width: wFrac, height: hFrac),
                               webcamMask: .roundedRectangle, webcamStyle: framed)
        case .circleFacecam:
            let dPx = (portrait ? 0.4 : 0.22) * cw
            let wFrac = dPx / cw
            let hFrac = dPx / ch
            let x = portrait ? 0.07 : 0.74
            let y = portrait ? 0.6 : 0.62
            var style = framed
            style.mask = .circle
            return LayoutSlots(gameplay: .full, webcam: NormRect(x: x, y: y, width: wFrac, height: hFrac), webcamMask: .circle, webcamStyle: style)
        }
    }

    /// Crop (normalized source) with the given pixel aspect, as large as possible inside `region`,
    /// centred near `focus`.
    public static func crop(aspect: Double, inside region: NormRect, frameSize: Size2, focus: Vec2? = nil) -> NormRect {
        let rw = region.width * frameSize.width
        let rh = region.height * frameSize.height
        var w: Double
        var h: Double
        if rw / max(rh, 1) > aspect {
            h = region.height
            w = (rh * aspect) / frameSize.width
        } else {
            w = region.width
            h = (rw / aspect) / frameSize.height
        }
        let center = focus ?? region.center
        var r = NormRect(center: center, width: w, height: h)
        // Keep inside region.
        r.x = r.x.clamped(region.minX, max(region.minX, region.maxX - w))
        r.y = r.y.clamped(region.minY, max(region.minY, region.maxY - h))
        return r.clampedToUnit()
    }

    /// Where one layout puts a clip of the given role. Nil = the clip isn't laid out (overlays, text…);
    /// `visible == false` = the layout has no place for it (e.g. the facecam in Full Frame).
    public static func target(role: MediaRole, preset: LayoutPreset, context: LayoutContext, canvas: CanvasSettings) -> LayoutTarget? {
        let webcamSource = context.webcamSourceSize ?? context.sourceSize
        let webcamRegion = context.webcamSourceSize != nil ? NormRect.full : context.webcamRegion
        let webcamAspect = webcamRegion.map { $0.pixelAspect(in: webcamSource) } ?? (16.0 / 9.0)
        let effectivePreset: LayoutPreset = (preset.usesWebcam && webcamRegion == nil) ? .fullFrame : preset
        let layoutSlots = Self.slots(for: effectivePreset == .dynamic ? .splitScreen : effectivePreset, canvas: canvas, webcamAspect: webcamAspect)
        if role == .webcam {
            guard let slot = layoutSlots.webcam, let region = webcamRegion else {
                return LayoutTarget(positionX: 0.5, positionY: 0.5, scale: 1, crop: .full, style: .plain, visible: false)
            }
            let slotAspect = slot.pixelAspect(in: canvas.size)
            let face = context.webcamSourceSize == nil ? context.faceCenter : context.webcamFaceCenter
            let crop = Self.crop(aspect: slotAspect, inside: region.insetBy(dx: region.width * 0.02, dy: region.height * 0.02), frameSize: webcamSource, focus: face)
            let placement = LayerGeometry.placement(fillingSlot: slot, cropAspect: slotAspect, canvasSize: canvas.size)
            return LayoutTarget(positionX: placement.positionX, positionY: placement.positionY, scale: placement.scale, crop: crop, style: layoutSlots.webcamStyle, visible: true)
        } else if role == .gameplay || role == .main || role == .camera {
            let slot = layoutSlots.gameplay
            let slotAspect = slot.pixelAspect(in: canvas.size)
            let crop: NormRect
            if effectivePreset == .fullFrame, context.profile == .talkingHead || context.profile == .podcast, let face = context.faceCenter {
                crop = NormRect.crop(aspect: slotAspect, frameSize: context.sourceSize, focus: Vec2(face.x, 0.5))
            } else {
                // Only carve the facecam out of the gameplay when it's inside the same file.
                let inFrameWebcam = context.webcamSourceSize == nil ? webcamRegion : nil
                crop = WebcamEstimator.gameplayRegion(frameSize: context.sourceSize, webcam: effectivePreset == .splitScreen || effectivePreset == .facecamDominant ? inFrameWebcam : nil, targetAspect: slotAspect)
            }
            let placement = LayerGeometry.placement(fillingSlot: slot, cropAspect: slotAspect, canvasSize: canvas.size)
            return LayoutTarget(positionX: placement.positionX, positionY: placement.positionY, scale: placement.scale, crop: crop, style: .plain, visible: true)
        }
        return nil
    }

    /// Applies a layout to every gameplay/main and webcam clip of the timeline (or only `clipIDs`).
    /// Applied to the whole timeline it replaces any layout changes over time.
    public static func apply(_ preset: LayoutPreset, to timeline: inout Timeline, context: LayoutContext, onlyClips clipIDs: Set<UUID>? = nil) {
        let canvas = timeline.canvas
        for ti in timeline.tracks.indices where timeline.tracks[ti].kind == .video {
            for ci in timeline.tracks[ti].clips.indices {
                var clip = timeline.tracks[ti].clips[ci]
                guard clip.assetID != nil else { continue }
                if let clipIDs, !clipIDs.contains(clip.id) { continue }
                guard let target = target(role: clip.role ?? .main, preset: preset, context: context, canvas: canvas) else { continue }
                if target.visible {
                    target.write(to: &clip)
                    clip.isEnabled = true
                } else {
                    clip.isEnabled = false
                }
                if clipIDs == nil, clip.role == .webcam { clip.transform.opacity = AnimatedDouble(1) }
                timeline.tracks[ti].clips[ci] = clip
            }
        }
        if clipIDs == nil {
            timeline.layout = preset
            timeline.layoutChanges = []
        }
        timeline.modifiedAt = Date()
    }

    /// Creates the extra webcam clip for a single-file VOD so gameplay and facecam can be laid out
    /// separately. Mirrors every gameplay clip of `assetID` onto a webcam track, linked.
    public static func ensureWebcamLayer(in timeline: inout Timeline, assetID: UUID) {
        let hasWebcam = timeline.allClips.contains { $0.assetID == assetID && $0.role == .webcam }
        guard !hasWebcam else { return }
        guard let source = timeline.tracks.first(where: { $0.kind == .video && $0.clips.contains { $0.assetID == assetID } }) else { return }
        var webcamTrack = Track(kind: .video, name: "V\(timeline.videoTracks.count + 1) Facecam")
        for (i, clip) in source.clips.enumerated() where clip.assetID == assetID {
            let group = clip.linkGroup ?? UUID()
            if clip.linkGroup == nil, let si = timeline.trackIndex(id: source.id) {
                timeline.tracks[si].clips[i].linkGroup = group
                // Link the matching audio clip too.
                for ti in timeline.tracks.indices where timeline.tracks[ti].kind == .audio {
                    for ci in timeline.tracks[ti].clips.indices where timeline.tracks[ti].clips[ci].assetID == assetID &&
                        abs(timeline.tracks[ti].clips[ci].start - clip.start) < 0.001 && timeline.tracks[ti].clips[ci].linkGroup == nil {
                        timeline.tracks[ti].clips[ci].linkGroup = group
                    }
                }
            }
            var cam = clip
            cam.id = UUID()
            cam.name = "Facecam"
            cam.role = .webcam
            cam.linkGroup = group
            cam.effects = []
            cam.transform = VisualTransform()
            webcamTrack.clips.append(cam)
        }
        // Insert right above the source track.
        let insertAt = (timeline.trackIndex(id: source.id) ?? 0) + 1
        timeline.tracks.insert(webcamTrack, at: insertAt)
    }
}

/// Smooth layout changes over time. A timeline's `layout` is the starting layout and `layoutChanges`
/// switch to others; `rebuild` turns that schedule into eased keyframes (position, scale, crop, style,
/// opacity) on the gameplay and facecam clips — no clip splitting, so the edit stays as it was.
public enum LayoutMorpher {
    public static let defaultDuration: Seconds = 0.5
    static let minimumDuration: Seconds = 1.0 / 60

    /// The layout a timeline starts in.
    public static func basePreset(of timeline: Timeline) -> LayoutPreset {
        switch timeline.layout {
        case .none: return .fullFrame
        case .some(.dynamic): return .splitScreen
        case .some(let preset): return preset
        }
    }

    /// Layout in effect at timeline time `t` (the target of a morph that has started).
    public static func preset(at t: Seconds, in timeline: Timeline) -> LayoutPreset {
        timeline.layoutChanges.sorted { $0.time < $1.time }.last { $0.time <= t + TimeRange.epsilon }?.preset ?? basePreset(of: timeline)
    }

    /// Adds (or replaces, if one starts within 50 ms) a change and rebuilds the animation.
    @discardableResult
    public static func addChange(_ preset: LayoutPreset, at time: Seconds, duration: Seconds = defaultDuration, aiGenerated: Bool = false,
                                 to timeline: inout Timeline, context: LayoutContext) -> UUID {
        timeline.layoutChanges.removeAll { abs($0.time - time) < 0.05 }
        let change = LayoutChange(time: max(0, time), preset: preset, duration: max(0, duration), aiGenerated: aiGenerated)
        timeline.layoutChanges.append(change)
        timeline.layoutChanges.sort { $0.time < $1.time }
        if timeline.layout == nil { timeline.layout = .fullFrame }
        rebuild(&timeline, context: context)
        return change.id
    }

    public static func removeChange(id: UUID, from timeline: inout Timeline, context: LayoutContext) {
        timeline.layoutChanges.removeAll { $0.id == id }
        rebuild(&timeline, context: context)
    }

    /// Rewrites the layout animation of every laid-out clip from the schedule.
    public static func rebuild(_ timeline: inout Timeline, context: LayoutContext) {
        let changes = timeline.layoutChanges.sorted { $0.time < $1.time }
        let base = basePreset(of: timeline)
        let canvas = timeline.canvas
        // presets[i] is in effect after change i-1 (presets[0] = base).
        let presets = [base] + changes.map(\.preset)
        for ti in timeline.tracks.indices where timeline.tracks[ti].kind == .video {
            for ci in timeline.tracks[ti].clips.indices {
                var clip = timeline.tracks[ti].clips[ci]
                guard clip.assetID != nil else { continue }
                let role = clip.role ?? .main
                var targets: [LayoutTarget] = []
                for p in presets {
                    guard let t = LayoutEngine.target(role: role, preset: p, context: context, canvas: canvas) else { break }
                    targets.append(t)
                }
                guard targets.count == presets.count else { continue }
                // Changes that animate during this clip, and the layout at its start.
                let active = changes.indices.filter { i in
                    let d = max(changes[i].duration, minimumDuration)
                    return changes[i].time < clip.end && changes[i].time + d > clip.start
                }
                let startIndex = changes.lastIndex(where: { $0.time + max($0.duration, minimumDuration) <= clip.start }).map { $0 + 1 } ?? 0
                var startTarget = targets[startIndex]
                if !startTarget.visible, let shown = targets.first(where: \.visible) { startTarget = startTarget.hidden(like: shown) }
                startTarget.write(to: &clip)
                // Only the facecam appears and disappears; other clips keep their own opacity.
                let fades = role == .webcam
                if fades { clip.transform.opacity = AnimatedDouble(startTarget.visible ? 1 : 0) }
                if active.isEmpty {
                    clip.isEnabled = startTarget.visible
                    if fades { clip.transform.opacity = AnimatedDouble(1) }
                    timeline.tracks[ti].clips[ci] = clip
                    continue
                }
                clip.isEnabled = true
                var crop = AnimatedRect(startTarget.crop)
                for i in active {
                    var from = targets[i], to = targets[i + 1]
                    if !from.visible && to.visible { from = from.hidden(like: to) }
                    if from.visible && !to.visible { to = to.hidden(like: from) }
                    let t0 = changes[i].time - clip.start
                    let t1 = t0 + max(changes[i].duration, minimumDuration)
                    for (time, target) in [(t0, from), (t1, to)] {
                        clip.transform.positionX.setKeyframe(at: time, value: target.positionX)
                        clip.transform.positionY.setKeyframe(at: time, value: target.positionY)
                        clip.transform.scale.setKeyframe(at: time, value: target.scale)
                        if fades { clip.transform.opacity.setKeyframe(at: time, value: target.visible ? 1 : 0) }
                        crop.setKeyframe(at: time, target.crop)
                        clip.styleKeyframes.removeAll { abs($0.time - time) < 1.0 / 240 }
                        clip.styleKeyframes.append(StyleKeyframe(time: time, style: target.style))
                    }
                }
                clip.styleKeyframes.sort { $0.time < $1.time }
                clip.transform.cropAnimation = crop
                timeline.tracks[ti].clips[ci] = clip
            }
        }
        timeline.modifiedAt = Date()
    }
}

/// Plans AI layout switches for the Dynamic layout: facecam-dominant while the streamer is talking
/// calmly, split screen during action, facecam corner when gameplay is intense.
public enum DynamicLayoutPlanner {
    public struct Segment: Hashable, Sendable {
        public var range: TimeRange
        public var layout: LayoutPreset
    }

    /// `range` is in source time; returns segments in source time, merged and at least `minimum` long.
    public static func plan(range: TimeRange, signals: EngagementSignals, minimum: Seconds = 3) -> [Segment] {
        guard signals.count > 0, range.duration > minimum * 2 else { return [Segment(range: range, layout: .splitScreen)] }
        var segments: [Segment] = []
        var t = range.start
        while t < range.end {
            let window = TimeRange(start: t, end: min(t + minimum, range.end))
            let motion = signals.mean(signals.motion, in: window)
            let speech = signals.mean(signals.speech, in: window)
            let excitement = signals.mean(signals.excitement, in: window)
            let layout: LayoutPreset
            if motion > 1.2 && speech < 0.5 {
                layout = .facecamCorner
            } else if speech > 0.6 && motion < 0.2 && excitement < 0.25 {
                layout = .facecamDominant
            } else {
                layout = .splitScreen
            }
            if let last = segments.last, last.layout == layout {
                segments[segments.count - 1].range = TimeRange(start: last.range.start, end: window.end)
            } else {
                segments.append(Segment(range: window, layout: layout))
            }
            t = window.end
        }
        return segments
    }
}
