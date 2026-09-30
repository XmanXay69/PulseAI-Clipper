import AppKit
import CoreText
import Foundation
import PulseCore

/// Renders titles and animated word-level captions with Core Text into bitmaps.
public enum TextRenderer {
    /// A rendered text block. `image` is sized in output pixels.
    public struct Rendered {
        public var image: CGImage
        public var size: CGSize
    }

    // MARK: Fonts

    public static func font(for style: TextStyle, pointSize: CGFloat) -> NSFont {
        let weight: NSFont.Weight
        switch style.weight {
        case .regular: weight = .regular
        case .medium: weight = .medium
        case .semibold: weight = .semibold
        case .bold: weight = .bold
        case .heavy: weight = .heavy
        case .black: weight = .black
        }
        var font: NSFont
        let name = style.fontName
        if name.hasPrefix("SF Pro") || name.isEmpty || name == "System" {
            font = NSFont.systemFont(ofSize: pointSize, weight: weight)
            if name.contains("Rounded"), let d = font.fontDescriptor.withDesign(.rounded) {
                font = NSFont(descriptor: d, size: pointSize) ?? font
            }
        } else if name == "New York" {
            font = NSFont.systemFont(ofSize: pointSize, weight: weight)
            if let d = font.fontDescriptor.withDesign(.serif) { font = NSFont(descriptor: d, size: pointSize) ?? font }
        } else if let named = NSFont(name: name, size: pointSize) {
            font = named
        } else {
            let descriptor = NSFontDescriptor(fontAttributes: [
                .family: name,
                .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue],
            ])
            font = NSFont(descriptor: descriptor, size: pointSize) ?? NSFont.systemFont(ofSize: pointSize, weight: weight)
        }
        if style.italic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }

    static func cgColor(_ c: RGBAColor, alpha: Double = 1) -> CGColor {
        CGColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha * alpha)
    }

    // MARK: Generic word runs

    /// A word with its own look inside a line.
    struct Run {
        var text: String
        var color: RGBAColor
        var scale: CGFloat
        var boxColor: RGBAColor?
        var alpha: CGFloat
    }

    /// Draws lines of runs centered/aligned, with stroke, shadow, optional background plate and per-word boxes.
    static func draw(lines: [[Run]], style: TextStyle, pointSize: CGFloat, maxWidth: CGFloat?) -> Rendered? {
        let baseFont = font(for: style, pointSize: pointSize)
        // Style values are in canvas pixels (1080-wide reference); `unit` converts them to output pixels.
        let unit = pointSize / CGFloat(max(style.fontSize, 1))
        let spacing = style.letterSpacing * Double(unit)
        let strokeWidth = CGFloat(style.strokeWidth) * unit
        struct LaidLine {
            var line: CTLine
            var width: CGFloat
            var ascent: CGFloat
            var descent: CGFloat
            var runs: [(range: NSRange, run: Run)]
        }
        var laid: [LaidLine] = []
        for runs in lines {
            let attributed = NSMutableAttributedString()
            var ranges: [(range: NSRange, run: Run)] = []
            for (i, run) in runs.enumerated() {
                let text = (i > 0 ? " " : "") + run.text
                let font = run.scale == 1 ? baseFont : (NSFont(descriptor: baseFont.fontDescriptor, size: pointSize * run.scale) ?? baseFont)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor(cgColor: cgColor(run.color, alpha: Double(run.alpha))) ?? .white,
                    .kern: spacing,
                ]
                let start = attributed.length + (i > 0 ? 1 : 0)
                attributed.append(NSAttributedString(string: text, attributes: attrs))
                ranges.append((range: NSRange(location: start, length: (run.text as NSString).length), run: run))
            }
            let line = CTLineCreateWithAttributedString(attributed)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            laid.append(LaidLine(line: line, width: width, ascent: ascent, descent: descent, runs: ranges))
        }
        guard !laid.isEmpty else { return nil }
        let lineHeight = CGFloat(style.lineHeight)
        let lineAdvance = laid.map { ($0.ascent + $0.descent) * lineHeight }
        let contentWidth = laid.map(\.width).max() ?? 0
        let contentHeight = lineAdvance.reduce(0, +)
        let padding = CGFloat(style.backgroundOpacity > 0 ? style.backgroundPadding : 0) * unit
        let shadowPad = CGFloat(style.shadowRadius + abs(style.shadowOffsetY)) * unit + strokeWidth + 4
        let width = ceil(contentWidth + 2 * (padding + shadowPad))
        let height = ceil(contentHeight + 2 * (padding + shadowPad))
        guard width > 1, height > 1, width < 16_384, height < 16_384 else { return nil }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldSmoothFonts(false)

        // Background plate.
        if style.backgroundOpacity > 0 {
            let rect = CGRect(x: shadowPad, y: shadowPad, width: contentWidth + 2 * padding, height: contentHeight + 2 * padding)
            let radius = CGFloat(style.backgroundCornerRadius) * unit
            ctx.setFillColor(cgColor(style.backgroundColor, alpha: style.backgroundOpacity))
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: min(radius, rect.width / 2), cornerHeight: min(radius, rect.height / 2), transform: nil))
            ctx.fillPath()
        }

        var y = height - shadowPad - padding
        for (index, l) in laid.enumerated() {
            let advance = lineAdvance[index]
            let baseline = y - (advance - (l.ascent + l.descent)) / 2 - l.ascent
            let x: CGFloat
            switch style.alignment {
            case .leading: x = shadowPad + padding
            case .center: x = (width - l.width) / 2
            case .trailing: x = width - shadowPad - padding - l.width
            }
            // Word boxes (highlight mode "box").
            for (range, run) in l.runs {
                guard let box = run.boxColor else { continue }
                let x0 = CTLineGetOffsetForStringIndex(l.line, range.location, nil)
                let x1 = CTLineGetOffsetForStringIndex(l.line, range.location + range.length, nil)
                let pad = pointSize * 0.12
                let rect = CGRect(x: x + x0 - pad, y: baseline - l.descent - pad * 0.5, width: x1 - x0 + 2 * pad, height: l.ascent + l.descent + pad)
                ctx.setFillColor(cgColor(box))
                ctx.addPath(CGPath(roundedRect: rect, cornerWidth: pad * 1.2, cornerHeight: pad * 1.2, transform: nil))
                ctx.fillPath()
            }
            ctx.saveGState()
            if style.shadowOpacity > 0 {
                ctx.setShadow(offset: CGSize(width: 0, height: -CGFloat(style.shadowOffsetY) * unit),
                              blur: CGFloat(style.shadowRadius) * unit,
                              color: cgColor(style.shadowColor, alpha: style.shadowOpacity))
            }
            if strokeWidth > 0 {
                ctx.setLineJoin(.round)
                // The stroke is centred on the glyph edge, so double it for the visible outline width.
                ctx.setLineWidth(strokeWidth * 2)
                ctx.setStrokeColor(cgColor(style.strokeColor))
                ctx.setTextDrawingMode(.stroke)
                ctx.textPosition = CGPoint(x: x, y: baseline)
                CTLineDraw(l.line, ctx)
                // Shadow once, under the stroke only.
                ctx.setShadow(offset: .zero, blur: 0, color: nil)
            }
            ctx.setTextDrawingMode(.fill)
            ctx.textPosition = CGPoint(x: x, y: baseline)
            CTLineDraw(l.line, ctx)
            ctx.restoreGState()
            y -= advance
        }
        guard let image = ctx.makeImage() else { return nil }
        return Rendered(image: image, size: CGSize(width: width, height: height))
    }

    /// Word-wraps plain text into lines no wider than `maxWidth` (in output pixels).
    static func wrap(_ text: String, style: TextStyle, pointSize: CGFloat, maxWidth: CGFloat) -> [String] {
        let font = font(for: style, pointSize: pointSize)
        var lines: [String] = []
        for paragraph in text.components(separatedBy: "\n") {
            var current = ""
            for word in paragraph.split(separator: " ").map(String.init) {
                let candidate = current.isEmpty ? word : current + " " + word
                let width = (candidate as NSString).size(withAttributes: [.font: font]).width
                if width > maxWidth && !current.isEmpty {
                    lines.append(current)
                    current = word
                } else {
                    current = candidate
                }
            }
            lines.append(current)
        }
        return lines
    }

    // MARK: Titles

    /// Renders a free text element. `visibleCharacters` supports the typewriter animation.
    public static func renderText(_ element: TextElement, renderScale: Double, canvasWidth: Double, visibleCharacters: Int? = nil) -> Rendered? {
        let style = element.style
        let pointSize = CGFloat(style.fontSize * renderScale)
        var text = style.textCase.apply(element.text)
        if let visibleCharacters { text = String(text.prefix(max(0, visibleCharacters))) }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let maxWidth = CGFloat(element.maxWidth * canvasWidth * renderScale)
        let lines = wrap(text, style: style, pointSize: pointSize, maxWidth: maxWidth).map { line in
            [Run(text: line, color: style.color, scale: 1, boxColor: nil, alpha: 1)]
        }
        return draw(lines: lines, style: style, pointSize: pointSize, maxWidth: maxWidth)
    }

    // MARK: Captions

    /// Renders one caption page at time `t` (timeline seconds) with word highlighting and animation.
    /// Returns the image plus a scale/opacity/offset for page-level animation.
    public struct CaptionFrame {
        public var rendered: Rendered
        public var scale: CGFloat
        public var opacity: CGFloat
        public var offsetY: CGFloat
    }

    public static func renderCaption(page: CaptionPage, style: CaptionStyle, at t: Seconds, renderScale: Double) -> CaptionFrame? {
        let speed = max(style.animationSpeed, 0.1)
        let active = CaptionLayoutEngine.activeWordIndex(in: page, at: t)
        var flatIndex = 0
        var lines: [[Run]] = []
        for line in page.lines {
            var runs: [Run] = []
            for word in line {
                let index = flatIndex
                flatIndex += 1
                // Reveal / typewriter: hide words not yet spoken.
                if style.displayMode == .reveal || style.animation == .typewriter, word.start > t + 0.02 {
                    runs.append(Run(text: word.text, color: style.text.color, scale: 1, boxColor: nil, alpha: 0))
                    continue
                }
                var color = word.isEmphasized ? style.emphasisColor : style.text.color
                var scale: CGFloat = word.isEmphasized ? CGFloat(style.emphasisScale) : 1
                var box: RGBAColor?
                let isActive = index == active && t < word.end + 0.25
                if isActive {
                    switch style.highlightMode {
                    case .none: break
                    case .color: color = style.highlightColor
                    case .box:
                        box = style.highlightBoxColor
                        color = style.highlightColor
                    case .scale: scale = max(scale, 1.12)
                    case .colorAndScale:
                        color = style.highlightColor
                        scale = max(scale, 1.1)
                    }
                    if style.animation == .bounce {
                        // Quick overshoot when the word starts.
                        let p = min(max((t - word.start) * speed / 0.18, 0), 1)
                        scale *= CGFloat(1 + 0.18 * sin(p * .pi))
                    }
                }
                runs.append(Run(text: word.text, color: color, scale: scale, boxColor: box, alpha: 1))
            }
            lines.append(runs)
        }
        let pointSize = CGFloat(style.text.fontSize * renderScale)
        guard let rendered = draw(lines: lines, style: style.text, pointSize: pointSize, maxWidth: nil) else { return nil }
        // Page-level entrance animation.
        let age = max(0, t - page.range.start) * speed
        var pageScale: CGFloat = 1
        var opacity: CGFloat = 1
        var offsetY: CGFloat = 0
        switch style.animation {
        case .pop:
            let p = min(age / 0.16, 1)
            pageScale = CGFloat(0.72 + 0.28 * p + 0.08 * sin(p * .pi))
        case .fade:
            opacity = CGFloat(min(age / 0.14, 1))
        case .slideUp:
            let p = min(age / 0.18, 1)
            offsetY = CGFloat((1 - p) * 26 * renderScale)
            opacity = CGFloat(p)
        case .bounce:
            let p = min(age / 0.2, 1)
            pageScale = CGFloat(0.85 + 0.15 * p + 0.1 * sin(p * .pi))
        case .none, .typewriter:
            break
        }
        return CaptionFrame(rendered: rendered, scale: pageScale, opacity: opacity, offsetY: offsetY)
    }
}
