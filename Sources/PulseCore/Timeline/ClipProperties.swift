import Foundation

/// How a (cropped) source fits the canvas before `scale` is applied.
public enum FitMode: String, Codable, CaseIterable, Sendable {
    case fit
    case fill
    case stretch

    public var displayName: String {
        switch self {
        case .fit: return "Fit"
        case .fill: return "Fill"
        case .stretch: return "Stretch"
        }
    }
}

/// Spatial properties of a visual layer. All position values are normalized canvas
/// coordinates (0.5, 0.5 = centered). Crop is normalized source coordinates.
///
/// Two kinds of zoom exist on purpose:
///  * `scale` resizes the whole layer on the canvas (e.g. shrinking the facecam).
///  * `zoom` punches in on the content *inside* the layer's frame (AI punch-ins, keyframed crop),
///    so a split-screen panel never spills outside its slot.
public struct VisualTransform: Codable, Hashable, Sendable {
    public var positionX: AnimatedDouble
    public var positionY: AnimatedDouble
    public var scale: AnimatedDouble
    public var rotation: AnimatedDouble
    public var opacity: AnimatedDouble
    /// Content zoom (≥ 1) inside the layer frame.
    public var zoom: AnimatedDouble
    /// Pans the crop window, in normalized source units (used by AI reframing / keyframed crop).
    public var panX: AnimatedDouble
    public var panY: AnimatedDouble
    public var crop: NormRect
    /// Keyframed crop (layout morphs); when animated it overrides `crop`.
    public var cropAnimation: AnimatedRect?
    public var fit: FitMode
    public var flipHorizontal: Bool
    public var flipVertical: Bool

    public init(positionX: Double = 0.5, positionY: Double = 0.5, scale: Double = 1, rotation: Double = 0,
                opacity: Double = 1, zoom: Double = 1, crop: NormRect = .full, fit: FitMode = .fit) {
        self.positionX = AnimatedDouble(positionX)
        self.positionY = AnimatedDouble(positionY)
        self.scale = AnimatedDouble(scale)
        self.rotation = AnimatedDouble(rotation)
        self.opacity = AnimatedDouble(opacity)
        self.zoom = AnimatedDouble(zoom)
        self.panX = AnimatedDouble(0)
        self.panY = AnimatedDouble(0)
        self.crop = crop
        self.cropAnimation = nil
        self.fit = fit
        self.flipHorizontal = false
        self.flipVertical = false
    }

    public static let identity = VisualTransform()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        positionX = c.decode(AnimatedDouble.self, forKey: .positionX, default: AnimatedDouble(0.5))
        positionY = c.decode(AnimatedDouble.self, forKey: .positionY, default: AnimatedDouble(0.5))
        scale = c.decode(AnimatedDouble.self, forKey: .scale, default: AnimatedDouble(1))
        rotation = c.decode(AnimatedDouble.self, forKey: .rotation, default: AnimatedDouble(0))
        opacity = c.decode(AnimatedDouble.self, forKey: .opacity, default: AnimatedDouble(1))
        zoom = c.decode(AnimatedDouble.self, forKey: .zoom, default: AnimatedDouble(1))
        panX = c.decode(AnimatedDouble.self, forKey: .panX, default: AnimatedDouble(0))
        panY = c.decode(AnimatedDouble.self, forKey: .panY, default: AnimatedDouble(0))
        crop = c.decode(NormRect.self, forKey: .crop, default: .full)
        cropAnimation = c.decode(AnimatedRect?.self, forKey: .cropAnimation, default: nil)
        fit = c.decode(FitMode.self, forKey: .fit, default: .fit)
        flipHorizontal = c.decode(Bool.self, forKey: .flipHorizontal, default: false)
        flipVertical = c.decode(Bool.self, forKey: .flipVertical, default: false)
    }

    public var hasKeyframes: Bool {
        [positionX, positionY, scale, rotation, opacity, zoom, panX, panY].contains { $0.isAnimated } || cropAnimation?.isAnimated == true
    }

    /// The crop at clip time `t` (before pan and content zoom).
    public func crop(at t: Seconds) -> NormRect {
        if let cropAnimation, cropAnimation.isAnimated { return cropAnimation.value(at: t) }
        return crop
    }

    public mutating func shiftKeyframes(by delta: Seconds) {
        positionX.shiftKeyframes(by: delta)
        positionY.shiftKeyframes(by: delta)
        scale.shiftKeyframes(by: delta)
        rotation.shiftKeyframes(by: delta)
        opacity.shiftKeyframes(by: delta)
        zoom.shiftKeyframes(by: delta)
        panX.shiftKeyframes(by: delta)
        panY.shiftKeyframes(by: delta)
        cropAnimation?.shiftKeyframes(by: delta)
    }

    public mutating func retainKeyframes(in range: TimeRange, rebasingTo origin: Seconds) {
        positionX.retainKeyframes(in: range, rebasingTo: origin)
        positionY.retainKeyframes(in: range, rebasingTo: origin)
        scale.retainKeyframes(in: range, rebasingTo: origin)
        rotation.retainKeyframes(in: range, rebasingTo: origin)
        opacity.retainKeyframes(in: range, rebasingTo: origin)
        zoom.retainKeyframes(in: range, rebasingTo: origin)
        panX.retainKeyframes(in: range, rebasingTo: origin)
        panY.retainKeyframes(in: range, rebasingTo: origin)
        cropAnimation?.retainKeyframes(in: range, rebasingTo: origin)
    }

    public mutating func removeAIKeyframes() {
        positionX.removeAIKeyframes()
        positionY.removeAIKeyframes()
        scale.removeAIKeyframes()
        rotation.removeAIKeyframes()
        opacity.removeAIKeyframes()
        zoom.removeAIKeyframes()
        panX.removeAIKeyframes()
        panY.removeAIKeyframes()
    }

    /// Crop actually sampled at time `t` after pan + content zoom, clamped inside the source.
    public func effectiveCrop(at t: Seconds) -> NormRect {
        let z = max(zoom.value(at: t), 0.05)
        var rect = crop(at: t).offsetBy(dx: panX.value(at: t), dy: panY.value(at: t))
        rect = rect.scaled(by: 1 / z)
        return rect.clampedToUnit()
    }
}

/// Resolved placement of a visual layer in canvas pixel space (top-left origin).
public struct ResolvedLayerGeometry: Hashable, Sendable {
    public var crop: NormRect
    public var center: Vec2
    public var size: Size2
    public var rotationDegrees: Double
    public var opacity: Double
    public var flipHorizontal: Bool
    public var flipVertical: Bool

    public var frame: (x: Double, y: Double, width: Double, height: Double) {
        (center.x - size.width / 2, center.y - size.height / 2, size.width, size.height)
    }
}

public enum LayerGeometry {
    /// Computes where a layer lands on the canvas at time `t`.
    public static func resolve(_ transform: VisualTransform, at t: Seconds, sourceSize: Size2, canvasSize: Size2) -> ResolvedLayerGeometry {
        let crop = transform.effectiveCrop(at: t)
        // Base size uses the un-zoomed crop so content zoom never changes the frame.
        let base = transform.crop(at: t).clampedToUnit()
        let cw = max(base.width * sourceSize.width, 1)
        let ch = max(base.height * sourceSize.height, 1)
        var size: Size2
        switch transform.fit {
        case .fit:
            let k = min(canvasSize.width / cw, canvasSize.height / ch)
            size = Size2(cw * k, ch * k)
        case .fill:
            let k = max(canvasSize.width / cw, canvasSize.height / ch)
            size = Size2(cw * k, ch * k)
        case .stretch:
            size = canvasSize
        }
        let s = transform.scale.value(at: t)
        size = size.scaled(max(s, 0))
        let center = Vec2(transform.positionX.value(at: t) * canvasSize.width, transform.positionY.value(at: t) * canvasSize.height)
        return ResolvedLayerGeometry(
            crop: crop,
            center: center,
            size: size,
            rotationDegrees: transform.rotation.value(at: t),
            opacity: transform.opacity.value(at: t).clamped(0, 1),
            flipHorizontal: transform.flipHorizontal,
            flipVertical: transform.flipVertical
        )
    }

    /// Computes `scale` + position so that a crop with the given pixel aspect exactly fills
    /// `slot` (normalized canvas rect) under `.fit`.
    public static func placement(fillingSlot slot: NormRect, cropAspect: Double, canvasSize: Size2) -> (positionX: Double, positionY: Double, scale: Double) {
        let slotW = slot.width * canvasSize.width
        let slotH = slot.height * canvasSize.height
        // Under .fit with scale 1 the crop's size is `canvas.fitting(aspect:)`.
        let fitted = canvasSize.fitting(aspect: cropAspect)
        let k = max(slotW / max(fitted.width, 1), slotH / max(fitted.height, 1))
        return (slot.center.x, slot.center.y, k)
    }
}

/// Shape used to mask a layer (webcam bubbles, rounded panels…).
public enum MaskShape: String, Codable, CaseIterable, Sendable {
    case rectangle
    case roundedRectangle
    case circle
    case ellipse

    public var displayName: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .roundedRectangle: return "Rounded"
        case .circle: return "Circle"
        case .ellipse: return "Ellipse"
        }
    }
}

/// Mask, border and shadow of a visual layer.
public struct LayerStyle: Codable, Hashable, Sendable {
    public var mask: MaskShape
    /// Corner radius as a fraction of the layer's shorter side (0…0.5).
    public var cornerRadius: Double
    /// Border width in canvas pixels.
    public var borderWidth: Double
    public var borderColor: RGBAColor
    public var shadowRadius: Double
    public var shadowOpacity: Double
    public var shadowOffsetY: Double

    public init(mask: MaskShape = .rectangle, cornerRadius: Double = 0, borderWidth: Double = 0,
                borderColor: RGBAColor = .white, shadowRadius: Double = 0, shadowOpacity: Double = 0,
                shadowOffsetY: Double = 0) {
        self.mask = mask
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.shadowRadius = shadowRadius
        self.shadowOpacity = shadowOpacity
        self.shadowOffsetY = shadowOffsetY
    }

    public static let plain = LayerStyle()
    public var isPlain: Bool { mask == .rectangle && borderWidth <= 0 && shadowOpacity <= 0 }

    /// Corner rounding as a fraction of the shorter side (circle = 0.5).
    var roundness: Double {
        switch mask {
        case .rectangle: return cornerRadius
        case .roundedRectangle: return max(cornerRadius, 0.04)
        case .circle, .ellipse: return 0.5
        }
    }

    /// Blend toward `other` (0…1). Different mask shapes morph through rounded corners, so a box can
    /// grow into a circle (a square slot with 50% rounding is a circle).
    public func interpolated(to other: LayerStyle, _ t: Double) -> LayerStyle {
        let p = t.clamped(0, 1)
        if p <= 0 { return self }
        if p >= 1 { return other }
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * p }
        var out = LayerStyle()
        if mask == other.mask {
            out.mask = mask
            out.cornerRadius = mix(cornerRadius, other.cornerRadius)
        } else if mask == .ellipse || other.mask == .ellipse {
            out.mask = p < 0.5 ? mask : other.mask
            out.cornerRadius = p < 0.5 ? cornerRadius : other.cornerRadius
        } else {
            out.mask = .rectangle
            out.cornerRadius = mix(roundness, other.roundness)
        }
        out.borderWidth = mix(borderWidth, other.borderWidth)
        out.borderColor = other.borderWidth > 0 ? other.borderColor : borderColor
        out.shadowRadius = mix(shadowRadius, other.shadowRadius)
        out.shadowOpacity = mix(shadowOpacity, other.shadowOpacity)
        out.shadowOffsetY = mix(shadowOffsetY, other.shadowOffsetY)
        return out
    }
}

/// A style at a moment of a clip (clip-relative time); styles between keyframes blend with ease-in-out.
public struct StyleKeyframe: Codable, Hashable, Sendable {
    public var time: Seconds
    public var style: LayerStyle

    public init(time: Seconds, style: LayerStyle) {
        self.time = time
        self.style = style
    }
}

extension Array where Element == StyleKeyframe {
    /// The blended style at clip time `t`, or nil when there are no keyframes.
    public func style(at t: Seconds) -> LayerStyle? {
        guard let first = first, let last = last else { return nil }
        if t <= first.time { return first.style }
        if t >= last.time { return last.style }
        guard let i = lastIndex(where: { $0.time <= t }), i + 1 < count else { return last.style }
        let a = self[i], b = self[i + 1]
        let span = b.time - a.time
        guard span > TimeRange.epsilon else { return b.style }
        return a.style.interpolated(to: b.style, Interpolation.easeInOut.apply((t - a.time) / span))
    }

    /// Same idea as `AnimatedDouble.retainKeyframes`: keep what shapes `range`, rebased.
    public func retained(in range: TimeRange, rebasingTo origin: Seconds) -> [StyleKeyframe] {
        let inside = indices.filter { self[$0].time >= range.start - TimeRange.epsilon && self[$0].time <= range.end + TimeRange.epsilon }
        var keep = Set(inside)
        if let before = indices.last(where: { self[$0].time < range.start - TimeRange.epsilon }), contains(where: { $0.time > range.start }) { keep.insert(before) }
        if let after = indices.first(where: { self[$0].time > range.end + TimeRange.epsilon }), contains(where: { $0.time < range.end }) { keep.insert(after) }
        return indices.filter { keep.contains($0) }.map { var k = self[$0]; k.time -= origin; return k }
    }
}

/// Primary color correction. All values are neutral at 0 (exposure in stops, others −1…1),
/// except `sharpness`/`vignette` (0…1).
public struct ColorAdjustments: Codable, Hashable, Sendable {
    public var exposure: Double = 0
    public var contrast: Double = 0
    public var highlights: Double = 0
    public var shadows: Double = 0
    public var saturation: Double = 0
    public var temperature: Double = 0
    public var tint: Double = 0
    public var sharpness: Double = 0
    public var vignette: Double = 0
    /// Path to a `.cube` LUT file.
    public var lutPath: String?
    public var lutIntensity: Double = 1

    public init() {}

    public var isIdentity: Bool {
        exposure == 0 && contrast == 0 && highlights == 0 && shadows == 0 && saturation == 0 &&
            temperature == 0 && tint == 0 && sharpness == 0 && vignette == 0 && lutPath == nil
    }

    public static let neutral = ColorAdjustments()
}

/// Non-destructive visual effects rendered by the compositor.
public enum EffectKind: String, Codable, CaseIterable, Sendable {
    case gaussianBlur
    case sharpen
    case glow
    case vignette
    case filmGrain
    case chromaticAberration
    case shake
    case zoomPulse
    case motionBlur
    case blackAndWhite

    public var displayName: String {
        switch self {
        case .gaussianBlur: return "Blur"
        case .sharpen: return "Sharpen"
        case .glow: return "Glow"
        case .vignette: return "Vignette"
        case .filmGrain: return "Noise / Grain"
        case .chromaticAberration: return "Chromatic Aberration"
        case .shake: return "Camera Shake"
        case .zoomPulse: return "Zoom Pulse"
        case .motionBlur: return "Motion Blur"
        case .blackAndWhite: return "Black & White"
        }
    }

    public var symbolName: String {
        switch self {
        case .gaussianBlur: return "drop"
        case .sharpen: return "triangle"
        case .glow: return "sun.max"
        case .vignette: return "circle.dashed"
        case .filmGrain: return "circle.grid.3x3"
        case .chromaticAberration: return "rainbow"
        case .shake: return "waveform.path"
        case .zoomPulse: return "plus.magnifyingglass"
        case .motionBlur: return "wind"
        case .blackAndWhite: return "circle.lefthalf.filled"
        }
    }

    /// Parameter names with default values.
    public var defaultParameters: [String: Double] {
        switch self {
        case .gaussianBlur: return ["radius": 12]
        case .sharpen: return ["amount": 0.6]
        case .glow: return ["intensity": 0.5, "radius": 18]
        case .vignette: return ["intensity": 0.8, "radius": 1.2]
        case .filmGrain: return ["amount": 0.15]
        case .chromaticAberration: return ["amount": 6]
        case .shake: return ["amplitude": 12, "frequency": 9]
        case .zoomPulse: return ["amount": 0.08, "frequency": 2]
        case .motionBlur: return ["radius": 14, "angle": 0]
        case .blackAndWhite: return ["intensity": 1]
        }
    }
}

public struct EffectInstance: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: EffectKind
    public var isEnabled: Bool
    public var parameters: [String: AnimatedDouble]
    public var aiGenerated: Bool

    public init(id: UUID = UUID(), kind: EffectKind, isEnabled: Bool = true, aiGenerated: Bool = false) {
        self.id = id
        self.kind = kind
        self.isEnabled = isEnabled
        self.aiGenerated = aiGenerated
        self.parameters = kind.defaultParameters.mapValues { AnimatedDouble($0) }
    }

    public func parameter(_ name: String, at t: Seconds) -> Double {
        parameters[name]?.value(at: t) ?? kind.defaultParameters[name] ?? 0
    }
}

/// Transition applied at a clip edge.
public enum TransitionKind: String, Codable, CaseIterable, Sendable {
    case cut
    case crossDissolve
    case fadeToBlack
    case wipeLeft
    case wipeRight
    case slideLeft
    case slideUp
    case zoomIn

    public var displayName: String {
        switch self {
        case .cut: return "Cut"
        case .crossDissolve: return "Dissolve"
        case .fadeToBlack: return "Fade"
        case .wipeLeft: return "Wipe Left"
        case .wipeRight: return "Wipe Right"
        case .slideLeft: return "Slide Left"
        case .slideUp: return "Slide Up"
        case .zoomIn: return "Zoom"
        }
    }
}

public struct ClipTransition: Codable, Hashable, Sendable {
    public var kind: TransitionKind
    public var duration: Seconds
    public var aiGenerated: Bool

    public init(kind: TransitionKind, duration: Seconds = 0.4, aiGenerated: Bool = false) {
        self.kind = kind
        self.duration = duration
        self.aiGenerated = aiGenerated
    }
}

/// Parametric 3-band EQ (gain in dB).
public struct EQSettings: Codable, Hashable, Sendable {
    public var isEnabled: Bool = false
    public var lowGain: Double = 0
    public var midGain: Double = 0
    public var highGain: Double = 0
    public var highPassHz: Double = 0

    public init() {}
}

public struct CompressorSettings: Codable, Hashable, Sendable {
    public var isEnabled: Bool = false
    public var thresholdDB: Double = -18
    public var ratio: Double = 3
    public var makeupGainDB: Double = 3

    public init() {}
}

/// How the Enhance chain removes background noise.
public enum NoiseReductionMethod: String, Codable, CaseIterable, Sendable {
    /// A neural network that keeps the voice and removes everything else (keyboard, music, crowd, fans).
    case voiceIsolation
    /// Spectral subtraction of a learned steady noise profile (hiss, hum, fans) plus a gentle expander.
    case spectral

    public var displayName: String {
        switch self {
        case .voiceIsolation: return "AI Voice Isolation"
        case .spectral: return "Classic"
        }
    }
}

/// Audio processing chain for a clip. Volume/fades/ducking are applied live by the audio mix;
/// the "enhance" chain (noise reduction, EQ, compressor, limiter) is rendered into a cached
/// processed file by the engine so it stays non-destructive.
public struct AudioSettings: Codable, Hashable, Sendable {
    /// Linear gain multiplier (1 = unity). Animatable for volume keyframes.
    public var volume: AnimatedDouble
    public var gainDB: Double
    public var pan: Double
    public var fadeIn: Seconds
    public var fadeOut: Seconds
    public var isMuted: Bool
    public var normalize: Bool
    public var noiseReduction: Double
    /// How noise is removed: the on-device neural voice isolator (new clips) or classic spectral subtraction.
    public var noiseMethod: NoiseReductionMethod
    public var voiceEnhance: Bool
    public var eq: EQSettings
    public var compressor: CompressorSettings
    public var limiter: Bool
    /// When true this clip is lowered while dialogue plays (music / game audio).
    public var duckUnderDialogue: Bool
    public var duckAmountDB: Double

    public init(volume: Double = 1) {
        self.volume = AnimatedDouble(volume)
        self.gainDB = 0
        self.pan = 0
        self.fadeIn = 0
        self.fadeOut = 0
        self.isMuted = false
        self.normalize = false
        self.noiseReduction = 0
        self.noiseMethod = .voiceIsolation
        self.voiceEnhance = false
        self.eq = EQSettings()
        self.compressor = CompressorSettings()
        self.limiter = false
        self.duckUnderDialogue = false
        self.duckAmountDB = -12
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        volume = c.decode(AnimatedDouble.self, forKey: .volume, default: AnimatedDouble(1))
        gainDB = c.decode(Double.self, forKey: .gainDB, default: 0)
        pan = c.decode(Double.self, forKey: .pan, default: 0)
        fadeIn = c.decode(Seconds.self, forKey: .fadeIn, default: 0)
        fadeOut = c.decode(Seconds.self, forKey: .fadeOut, default: 0)
        isMuted = c.decode(Bool.self, forKey: .isMuted, default: false)
        normalize = c.decode(Bool.self, forKey: .normalize, default: false)
        noiseReduction = c.decode(Double.self, forKey: .noiseReduction, default: 0)
        // Projects saved before the neural option keep the sound they were mixed with.
        noiseMethod = c.decode(NoiseReductionMethod.self, forKey: .noiseMethod, default: .spectral)
        voiceEnhance = c.decode(Bool.self, forKey: .voiceEnhance, default: false)
        eq = c.decode(EQSettings.self, forKey: .eq, default: EQSettings())
        compressor = c.decode(CompressorSettings.self, forKey: .compressor, default: CompressorSettings())
        limiter = c.decode(Bool.self, forKey: .limiter, default: false)
        duckUnderDialogue = c.decode(Bool.self, forKey: .duckUnderDialogue, default: false)
        duckAmountDB = c.decode(Double.self, forKey: .duckAmountDB, default: -12)
    }

    /// True when the processed-audio render path is needed.
    public var needsProcessing: Bool {
        noiseReduction > 0 || voiceEnhance || eq.isEnabled || compressor.isEnabled || limiter || normalize
    }

    /// Effective linear gain at clip-relative time `t` (volume × gain × fades), before ducking.
    public func gain(at t: Seconds, clipDuration: Seconds) -> Double {
        if isMuted { return 0 }
        var g = volume.value(at: t) * pow(10, gainDB / 20)
        if fadeIn > 0, t < fadeIn { g *= (t / fadeIn).clamped(0, 1) }
        if fadeOut > 0, t > clipDuration - fadeOut { g *= ((clipDuration - t) / fadeOut).clamped(0, 1) }
        return max(g, 0)
    }
}

/// What a clip on the timeline displays.
public enum ClipContent: Codable, Hashable, Sendable {
    case media(assetID: UUID)
    case text(TextElement)
    case solid(RGBAColor)
    /// A nested timeline (compound clip) stored in `ProjectDocument.compounds`.
    case compound(timelineID: UUID)

    public var assetID: UUID? {
        if case .media(let id) = self { return id }
        return nil
    }

    public var compoundID: UUID? {
        if case .compound(let id) = self { return id }
        return nil
    }

    /// Has a source time line that can't go below zero (media and compound clips).
    public var hasSourceTime: Bool { assetID != nil || compoundID != nil }

    public var textElement: TextElement? {
        if case .text(let element) = self { return element }
        return nil
    }
}
