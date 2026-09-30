import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Metal
import PulseCore

/// Renders one output frame from an instruction: layers (crop/zoom/pan, fit, masks, borders,
/// shadows, color, effects, transitions), text, and animated captions. GPU-accelerated through a
/// Metal-backed Core Image context.
public final class FrameRenderer: @unchecked Sendable {
    public static let shared = FrameRenderer()

    public let context: CIContext
    public let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let lock = NSLock()
    private var imageCache: [URL: CIImage] = [:]
    private var textCache: [String: CGImage] = [:]
    private var textCacheOrder: [String] = []
    private var lutCache: [String: (dimension: Int, data: Data)] = [:]

    public init() {
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, .cacheIntermediates: false])
        } else {
            context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        }
    }

    // MARK: Frame

    public func render(instruction: PulseCompositionInstruction, at time: Seconds, source: (CMPersistentTrackID) -> CVPixelBuffer?) -> CIImage {
        let scene = instruction.scene
        let bounds = CGRect(origin: .zero, size: scene.renderSize)
        let bg = scene.canvas.backgroundColor
        var output = CIImage(color: CIColor(red: bg.red, green: bg.green, blue: bg.blue, alpha: bg.alpha)).cropped(to: bounds)
        for layer in instruction.layers {
            if let image = renderLayer(layer, at: time, scene: scene, source: source) {
                output = image.composited(over: output)
            }
        }
        if let captions = scene.captions, let caption = renderCaptions(captions, at: time, scene: scene) {
            output = caption.composited(over: output)
        }
        return output.cropped(to: bounds)
    }

    // MARK: Layers

    func renderLayer(_ layer: RenderLayer, at time: Seconds, scene: RenderScene, source: (CMPersistentTrackID) -> CVPixelBuffer?) -> CIImage? {
        let clip = layer.clip
        let local = time - clip.start
        switch layer.content {
        case .video(let trackID, _, let orientation):
            guard let buffer = source(trackID) else { return nil }
            var image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
            image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
            return place(image, clip: clip, local: local, scene: scene, trackOpacity: layer.trackOpacity)
        case .image(let url, _):
            guard let image = cachedImage(url) else { return nil }
            return place(image, clip: clip, local: local, scene: scene, trackOpacity: layer.trackOpacity)
        case .text(let element):
            return renderTextLayer(element, clip: clip, local: local, scene: scene)
        case .solid(let color):
            let bounds = CGRect(origin: .zero, size: scene.renderSize)
            let opacity = clip.transform.opacity.value(at: local) * transitionState(clip, local: local, scene: scene).opacity
            return CIImage(color: CIColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha * opacity)).cropped(to: bounds)
        }
    }

    /// Crops, grades and positions a source image according to the clip's transform & style.
    func place(_ source: CIImage, clip: TimelineClip, local: Seconds, scene: RenderScene, trackOpacity: Double) -> CIImage? {
        let rs = scene.renderScale
        let H = Double(scene.renderSize.height)
        let sw = Double(source.extent.width)
        let sh = Double(source.extent.height)
        guard sw > 0, sh > 0 else { return nil }
        let g = LayerGeometry.resolve(clip.transform, at: local, sourceSize: Size2(sw, sh), canvasSize: scene.canvas.size)
        let c = g.crop
        let cropRect = CGRect(x: c.x * sw, y: (1 - c.y - c.height) * sh, width: max(c.width * sw, 1), height: max(c.height * sh, 1))
        var image = source.cropped(to: cropRect).transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))

        image = applyColor(image, clip.color)
        var shake = CGPoint.zero
        var pulse = 1.0
        for effect in clip.effects where effect.isEnabled {
            switch effect.kind {
            case .shake:
                let a = effect.parameter("amplitude", at: local) * rs
                let f = effect.parameter("frequency", at: local)
                shake = CGPoint(x: a * sin(2 * .pi * f * local), y: a * cos(2 * .pi * f * local * 1.31))
            case .zoomPulse:
                let amount = effect.parameter("amount", at: local)
                let f = effect.parameter("frequency", at: local)
                pulse *= 1 + amount * max(0, sin(2 * .pi * f * local))
            default:
                image = applyEffect(effect, to: image, local: local, renderScale: rs)
            }
        }

        let targetW = g.size.width * rs
        let targetH = g.size.height * rs
        guard targetW >= 1, targetH >= 1 else { return nil }
        let sx = targetW / Double(cropRect.width) * (g.flipHorizontal ? -1 : 1)
        let sy = targetH / Double(cropRect.height) * (g.flipVertical ? -1 : 1)
        image = image.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        image = image.cropped(to: CGRect(x: 0, y: 0, width: targetW, height: targetH))

        image = applyStyle(image, style: clip.style, size: CGSize(width: targetW, height: targetH), renderScale: rs)

        let tr = transitionState(clip, local: local, scene: scene)
        let center = CGPoint(x: g.center.x * rs + tr.offset.x + shake.x, y: H - g.center.y * rs + tr.offset.y + shake.y)
        var t = CGAffineTransform(translationX: -targetW / 2, y: -targetH / 2)
        let s = tr.scale * pulse
        if s != 1 { t = t.concatenating(CGAffineTransform(scaleX: s, y: s)) }
        if g.rotationDegrees != 0 { t = t.concatenating(CGAffineTransform(rotationAngle: -g.rotationDegrees * .pi / 180)) }
        t = t.concatenating(CGAffineTransform(translationX: center.x, y: center.y))
        image = image.transformed(by: t)

        let opacity = g.opacity * trackOpacity * tr.opacity
        if opacity < 0.999 { image = withOpacity(image, opacity) }
        if let wipe = tr.wipe { image = image.cropped(to: wipe) }
        return image
    }

    // MARK: Style (mask, border, shadow)

    func applyStyle(_ image: CIImage, style: LayerStyle, size: CGSize, renderScale rs: Double) -> CIImage {
        guard !style.isPlain || style.cornerRadius > 0 else { return image }
        let rect = CGRect(origin: .zero, size: size)
        let shorter = min(size.width, size.height)
        let radius: CGFloat
        switch style.mask {
        case .rectangle: radius = CGFloat(style.cornerRadius) * shorter
        case .roundedRectangle: radius = max(CGFloat(style.cornerRadius), 0.04) * shorter
        case .circle, .ellipse: radius = shorter / 2
        }
        var result = image
        if style.mask == .ellipse {
            let gradient = CIFilter.radialGradient()
            gradient.center = CGPoint(x: 0.5, y: 0.5)
            gradient.radius0 = 0.495
            gradient.radius1 = 0.5
            gradient.color0 = CIColor.white
            gradient.color1 = CIColor.clear
            if let unit = gradient.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)) {
                let ellipseMask = unit.transformed(by: CGAffineTransform(scaleX: size.width, y: size.height))
                result = mask(result, with: ellipseMask)
            }
        } else if radius > 0.5 {
            result = mask(result, with: roundedRect(rect, radius: radius, color: .white))
        }
        if style.borderWidth > 0 {
            let b = CGFloat(style.borderWidth * rs)
            let color = CIColor(red: style.borderColor.red, green: style.borderColor.green, blue: style.borderColor.blue, alpha: style.borderColor.alpha)
            let outer = roundedRect(rect.insetBy(dx: -b, dy: -b), radius: radius > 0 ? radius + b : 0, color: color)
            result = result.composited(over: outer)
        }
        if style.shadowOpacity > 0 {
            let b = CGFloat(max(style.borderWidth, 0) * rs)
            let shape = roundedRect(rect.insetBy(dx: -b, dy: -b), radius: radius > 0 ? radius + b : 0,
                                    color: CIColor(red: 0, green: 0, blue: 0, alpha: style.shadowOpacity))
            let blur = max(style.shadowRadius * rs, 0.5)
            let shadow = shape.clampedToExtent().applyingGaussianBlur(sigma: blur / 2)
                .cropped(to: shape.extent.insetBy(dx: -CGFloat(blur * 2), dy: -CGFloat(blur * 2)))
                .transformed(by: CGAffineTransform(translationX: 0, y: -CGFloat(style.shadowOffsetY * rs)))
            result = result.composited(over: shadow)
        }
        return result
    }

    func roundedRect(_ rect: CGRect, radius: CGFloat, color: CIColor) -> CIImage {
        let f = CIFilter.roundedRectangleGenerator()
        f.extent = rect
        f.radius = Float(min(radius, min(rect.width, rect.height) / 2))
        f.color = color
        return f.outputImage?.cropped(to: rect) ?? CIImage(color: color).cropped(to: rect)
    }

    func mask(_ image: CIImage, with mask: CIImage) -> CIImage {
        let f = CIFilter.blendWithAlphaMask()
        f.inputImage = image
        f.backgroundImage = CIImage.empty()
        f.maskImage = mask
        return f.outputImage?.cropped(to: image.extent) ?? image
    }

    func withOpacity(_ image: CIImage, _ opacity: Double) -> CIImage {
        let f = CIFilter.colorMatrix()
        f.inputImage = image
        f.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(max(0, min(1, opacity))))
        return f.outputImage ?? image
    }

    // MARK: Transitions

    struct TransitionState {
        var opacity: Double = 1
        var scale: Double = 1
        var offset: CGPoint = .zero
        var wipe: CGRect?
    }

    func transitionState(_ clip: TimelineClip, local: Seconds, scene: RenderScene) -> TransitionState {
        var state = TransitionState()
        let W = Double(scene.renderSize.width)
        let H = Double(scene.renderSize.height)
        func apply(_ transition: ClipTransition, progress p: Double, entering: Bool) {
            let e = Interpolation.easeInOut.apply(p)
            switch transition.kind {
            case .cut: break
            case .crossDissolve, .fadeToBlack: state.opacity *= e
            case .wipeLeft: state.wipe = CGRect(x: 0, y: 0, width: W * e, height: H)
            case .wipeRight: state.wipe = CGRect(x: W * (1 - e), y: 0, width: W * e, height: H)
            case .slideLeft: state.offset.x += (entering ? 1 : -1) * (1 - e) * W
            case .slideUp: state.offset.y += (entering ? -1 : 1) * (1 - e) * H
            case .zoomIn:
                state.scale *= entering ? 1.25 - 0.25 * e : 1 + 0.25 * (1 - e)
                state.opacity *= e
            }
        }
        if let t = clip.transitionIn, t.duration > 0, local < t.duration {
            apply(t, progress: max(0, local) / t.duration, entering: true)
        }
        if let t = clip.transitionOut, t.duration > 0, local > clip.duration - t.duration {
            apply(t, progress: max(0, clip.duration - local) / t.duration, entering: false)
        }
        return state
    }

    // MARK: Color

    func applyColor(_ input: CIImage, _ c: ColorAdjustments) -> CIImage {
        guard !c.isIdentity else { return input }
        var image = input
        if c.exposure != 0 {
            let f = CIFilter.exposureAdjust()
            f.inputImage = image
            f.ev = Float(c.exposure)
            image = f.outputImage ?? image
        }
        if c.contrast != 0 || c.saturation != 0 {
            let f = CIFilter.colorControls()
            f.inputImage = image
            f.contrast = Float(1 + c.contrast * 0.5)
            f.saturation = Float(max(0, 1 + c.saturation))
            f.brightness = 0
            image = f.outputImage ?? image
        }
        if c.highlights != 0 || c.shadows != 0 {
            let f = CIFilter.highlightShadowAdjust()
            f.inputImage = image
            f.highlightAmount = Float(1 - max(0, -c.highlights))
            f.shadowAmount = Float(c.shadows)
            image = f.outputImage ?? image
        }
        if c.temperature != 0 || c.tint != 0 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = image
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: CGFloat(6500 + c.temperature * 3000), y: CGFloat(c.tint * 60))
            image = f.outputImage ?? image
        }
        if c.sharpness > 0 {
            let f = CIFilter.sharpenLuminance()
            f.inputImage = image
            f.sharpness = Float(c.sharpness * 1.5)
            image = f.outputImage ?? image
        }
        if c.vignette > 0 {
            let f = CIFilter.vignette()
            f.inputImage = image
            f.intensity = Float(c.vignette * 1.5)
            f.radius = 1.6
            image = f.outputImage ?? image
        }
        if let path = c.lutPath, let lut = loadLUT(path) {
            let f = CIFilter.colorCubeWithColorSpace()
            f.inputImage = image
            f.cubeDimension = Float(lut.dimension)
            f.cubeData = lut.data
            f.colorSpace = colorSpace
            if let graded = f.outputImage {
                if c.lutIntensity >= 0.999 {
                    image = graded
                } else {
                    let blend = CIFilter.dissolveTransition()
                    blend.inputImage = image
                    blend.targetImage = graded
                    blend.time = Float(max(0, min(1, c.lutIntensity)))
                    image = blend.outputImage ?? graded
                }
            }
        }
        return image.cropped(to: input.extent)
    }

    // MARK: Effects

    func applyEffect(_ effect: EffectInstance, to input: CIImage, local: Seconds, renderScale rs: Double) -> CIImage {
        let extent = input.extent
        switch effect.kind {
        case .gaussianBlur:
            return input.clampedToExtent().applyingGaussianBlur(sigma: effect.parameter("radius", at: local) / 2).cropped(to: extent)
        case .sharpen:
            let f = CIFilter.sharpenLuminance()
            f.inputImage = input
            f.sharpness = Float(effect.parameter("amount", at: local))
            return f.outputImage?.cropped(to: extent) ?? input
        case .glow:
            let f = CIFilter.bloom()
            f.inputImage = input.clampedToExtent()
            f.radius = Float(effect.parameter("radius", at: local))
            f.intensity = Float(effect.parameter("intensity", at: local))
            return f.outputImage?.cropped(to: extent) ?? input
        case .vignette:
            let f = CIFilter.vignette()
            f.inputImage = input
            f.intensity = Float(effect.parameter("intensity", at: local))
            f.radius = Float(effect.parameter("radius", at: local))
            return f.outputImage?.cropped(to: extent) ?? input
        case .filmGrain:
            guard let noise = CIFilter.randomGenerator().outputImage else { return input }
            let jitter = CGFloat(Int(local * 24) % 97) * 13
            let amount = effect.parameter("amount", at: local)
            let grain = noise.transformed(by: CGAffineTransform(translationX: jitter, y: jitter * 0.7)).cropped(to: extent)
            let mono = CIFilter.colorMatrix()
            mono.inputImage = grain
            mono.rVector = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
            mono.gVector = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
            mono.bVector = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
            mono.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount))
            mono.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
            let overlay = CIFilter.overlayBlendMode()
            overlay.inputImage = mono.outputImage
            overlay.backgroundImage = input
            return overlay.outputImage?.cropped(to: extent) ?? input
        case .chromaticAberration:
            let shift = CGFloat(effect.parameter("amount", at: local) * rs)
            func channel(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, dx: CGFloat) -> CIImage {
                let f = CIFilter.colorMatrix()
                f.inputImage = input.clampedToExtent()
                f.rVector = CIVector(x: r, y: 0, z: 0, w: 0)
                f.gVector = CIVector(x: 0, y: g, z: 0, w: 0)
                f.bVector = CIVector(x: 0, y: 0, z: b, w: 0)
                f.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
                return (f.outputImage ?? input).transformed(by: CGAffineTransform(translationX: dx, y: 0))
            }
            let red = channel(1, 0, 0, dx: shift)
            let green = channel(0, 1, 0, dx: 0)
            let blue = channel(0, 0, 1, dx: -shift)
            let add1 = CIFilter.additionCompositing()
            add1.inputImage = red
            add1.backgroundImage = green
            let add2 = CIFilter.additionCompositing()
            add2.inputImage = blue
            add2.backgroundImage = add1.outputImage
            return add2.outputImage?.cropped(to: extent) ?? input
        case .motionBlur:
            let f = CIFilter.motionBlur()
            f.inputImage = input.clampedToExtent()
            f.radius = Float(effect.parameter("radius", at: local))
            f.angle = Float(effect.parameter("angle", at: local) * .pi / 180)
            return f.outputImage?.cropped(to: extent) ?? input
        case .blackAndWhite:
            let f = CIFilter.colorControls()
            f.inputImage = input
            f.saturation = Float(max(0, 1 - effect.parameter("intensity", at: local)))
            f.contrast = 1
            f.brightness = 0
            return f.outputImage?.cropped(to: extent) ?? input
        case .shake, .zoomPulse:
            return input
        }
    }

    // MARK: Text & captions

    func renderTextLayer(_ element: TextElement, clip: TimelineClip, local: Seconds, scene: RenderScene) -> CIImage? {
        let rs = scene.renderScale
        let d = max(element.animationDuration, 0.01)
        let pIn = min(max(local / d, 0), 1)
        let pOut = min(max((clip.duration - local) / d, 0), 1)
        var visible: Int?
        if element.animationIn == .typewriter {
            visible = Int((Double(element.text.count) * min(local / max(d * 3, 0.3), 1)).rounded(.up))
        }
        let key = "\(element.hashValue)|\(rs)|\(visible ?? -1)"
        let cg: CGImage
        if let hit = cachedText(key) {
            cg = hit
        } else {
            guard let rendered = TextRenderer.renderText(element, renderScale: rs, canvasWidth: Double(scene.canvas.width), visibleCharacters: visible) else { return nil }
            storeText(key, rendered.image)
            cg = rendered.image
        }
        var image = CIImage(cgImage: cg)
        var scale = clip.transform.scale.value(at: local)
        var opacity = clip.transform.opacity.value(at: local)
        var offsetY = 0.0
        switch element.animationIn {
        case .pop: scale *= 0.6 + 0.4 * pIn + 0.12 * sin(pIn * .pi)
        case .bounce: scale *= 1 + 0.2 * sin(pIn * .pi) * (1 - pIn)
        case .fadeIn: opacity *= pIn
        case .slideUp:
            offsetY = -(1 - Interpolation.easeOut.apply(pIn)) * 60 * rs
            opacity *= pIn
        case .typewriter, .none: break
        }
        switch element.animationOut {
        case .none: break
        case .fadeIn, .typewriter: opacity *= pOut
        case .pop: scale *= 0.7 + 0.3 * pOut
        case .slideUp:
            offsetY += (1 - pOut) * 60 * rs
            opacity *= pOut
        case .bounce: opacity *= pOut
        }
        let w = image.extent.width
        let h = image.extent.height
        let cx = clip.transform.positionX.value(at: local) * Double(scene.renderSize.width)
        let cy = Double(scene.renderSize.height) - clip.transform.positionY.value(at: local) * Double(scene.renderSize.height) + offsetY
        var t = CGAffineTransform(translationX: -w / 2, y: -h / 2)
        t = t.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        let rotation = clip.transform.rotation.value(at: local)
        if rotation != 0 { t = t.concatenating(CGAffineTransform(rotationAngle: -rotation * .pi / 180)) }
        t = t.concatenating(CGAffineTransform(translationX: cx, y: cy))
        image = image.transformed(by: t)
        let tr = transitionState(clip, local: local, scene: scene)
        opacity *= tr.opacity
        if opacity < 0.999 { image = withOpacity(image, opacity) }
        return image
    }

    func renderCaptions(_ captions: CaptionRenderData, at time: Seconds, scene: RenderScene) -> CIImage? {
        guard let page = CaptionLayoutEngine.page(at: time, in: captions.pages) else { return nil }
        let rs = scene.renderScale
        guard let frame = TextRenderer.renderCaption(page: page, style: captions.style, at: time, renderScale: rs) else { return nil }
        var image = CIImage(cgImage: frame.rendered.image)
        let W = Double(scene.renderSize.width)
        let H = Double(scene.renderSize.height)
        var cxN = captions.style.positionX
        var cyN = captions.style.positionY
        if let platform = captions.style.safeArea, scene.canvas.aspect < 1 {
            cyN = platform.clampCenterY(cyN, blockHeight: Double(frame.rendered.size.height) / H)
            cxN = platform.clampCenterX(cxN, blockWidth: min(Double(frame.rendered.size.width) / W, 0.8))
        }
        let w = image.extent.width
        let h = image.extent.height
        var t = CGAffineTransform(translationX: -w / 2, y: -h / 2)
        if frame.scale != 1 { t = t.concatenating(CGAffineTransform(scaleX: frame.scale, y: frame.scale)) }
        t = t.concatenating(CGAffineTransform(translationX: cxN * W, y: H - cyN * H - Double(frame.offsetY)))
        image = image.transformed(by: t)
        if frame.opacity < 0.999 { image = withOpacity(image, Double(frame.opacity)) }
        return image
    }

    // MARK: Caches

    func cachedImage(_ url: URL) -> CIImage? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = imageCache[url] { return hit }
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { return nil }
        if imageCache.count > 64 { imageCache.removeAll() }
        imageCache[url] = image
        return image
    }

    func cachedText(_ key: String) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return textCache[key]
    }

    func storeText(_ key: String, _ image: CGImage) {
        lock.lock()
        defer { lock.unlock() }
        textCache[key] = image
        textCacheOrder.append(key)
        if textCacheOrder.count > 256 {
            let drop = textCacheOrder.removeFirst()
            textCache[drop] = nil
        }
    }

    func loadLUT(_ path: String) -> (dimension: Int, data: Data)? {
        lock.lock()
        if let hit = lutCache[path] { lock.unlock(); return hit }
        lock.unlock()
        guard let text = try? String(contentsOfFile: path, encoding: .utf8), let lut = CubeLUT.parse(text) else { return nil }
        lock.lock()
        lutCache[path] = lut
        lock.unlock()
        return lut
    }
}

/// Minimal `.cube` 3D LUT parser (Adobe/Resolve format).
public enum CubeLUT {
    public static func parse(_ text: String) -> (dimension: Int, data: Data)? {
        var size = 0
        var values: [Float] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("TITLE") || line.hasPrefix("DOMAIN") { continue }
            if line.hasPrefix("LUT_3D_SIZE") {
                size = Int(line.split(separator: " ").last ?? "") ?? 0
                continue
            }
            let parts = line.split(separator: " ").compactMap { Float($0) }
            if parts.count == 3 { values.append(contentsOf: [parts[0], parts[1], parts[2], 1]) }
        }
        guard size >= 2, size <= 64, values.count == size * size * size * 4 else { return nil }
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        return (size, data)
    }
}
