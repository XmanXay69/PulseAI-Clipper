import Foundation

// MARK: - Picking frames

/// A moment worth putting on a thumbnail: a reaction at a clip's payoff, nudged to the frame
/// where the face is biggest and the picture is stillest (less motion blur).
public struct ThumbnailPick: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var time: Seconds
    /// The biggest face at that moment (normalized, top-left origin), if one was detected.
    public var face: NormRect?
    /// Suggested thumbnail text for this moment.
    public var headline: String
    /// Why it was picked, e.g. "🔥 Peak reaction · 92".
    public var reason: String
    public var candidateID: UUID?

    public init(id: UUID = UUID(), time: Seconds, face: NormRect? = nil, headline: String, reason: String, candidateID: UUID? = nil) {
        self.id = id
        self.time = time
        self.face = face
        self.headline = headline
        self.reason = reason
        self.candidateID = candidateID
    }
}

public enum ThumbnailPicker {
    /// The best thumbnail moments, strongest clip first, at least `minSpacing` apart.
    /// `within` limits the search to source ranges (the parts of the VOD an edit actually uses);
    /// if nothing falls inside them, the whole recording is used.
    public static func pick(candidates: [ClipCandidate], analysis: MediaAnalysis?, within ranges: [TimeRange]? = nil,
                            count: Int = 4, minSpacing: Seconds = 20) -> [ThumbnailPick] {
        var pool = candidates.filter { $0.status != .dismissed }
        if let ranges, !ranges.isEmpty {
            let inside = pool.filter { c in ranges.contains { $0.contains(c.payoffTime) } }
            if !inside.isEmpty { pool = inside }
        }
        pool.sort { ($0.potential, $0.scores.reaction) > ($1.potential, $1.scores.reaction) }
        var picks: [ThumbnailPick] = []
        for candidate in pool where picks.count < count {
            let moment = bestMoment(near: candidate.payoffTime, in: candidate.range, visual: analysis?.visual)
            guard !picks.contains(where: { abs($0.time - moment.time) < minSpacing }) else { continue }
            let tag = candidate.tags.first
            let reason = "\(tag?.emoji ?? "🔥") \(tag?.displayName ?? "Peak moment") · \(candidate.potential)"
            picks.append(ThumbnailPick(time: moment.time, face: moment.face, headline: ThumbnailHeadline.make(from: candidate.title),
                                       reason: reason, candidateID: candidate.id))
        }
        return picks
    }

    /// Frames for one clip: its payoff first, then the biggest, stillest faces elsewhere in it.
    public static func pick(clip candidate: ClipCandidate, analysis: MediaAnalysis?, count: Int = 3) -> [ThumbnailPick] {
        var picks = pick(candidates: [candidate], analysis: analysis, count: 1)
        let headline = ThumbnailHeadline.make(from: candidate.title)
        for (t, face) in alternates(in: candidate.range, visual: analysis?.visual, count: count - picks.count, avoiding: picks.map(\.time)) {
            picks.append(ThumbnailPick(time: t, face: face, headline: headline, reason: "😮 Big reaction", candidateID: candidate.id))
        }
        return picks
    }

    /// The best face frames in a range, at least `spacing` apart and away from `avoiding`.
    public static func alternates(in range: TimeRange, visual: VisualFeatureSeries?, count: Int, avoiding: [Seconds] = [],
                                  spacing: Seconds = 3) -> [(time: Seconds, face: NormRect)] {
        guard count > 0, let visual else { return [] }
        let scored = visual.faces(in: range).compactMap { sample -> (Seconds, NormRect, Double)? in
            guard let face = sample.boxes.max(by: { $0.area < $1.area }) else { return nil }
            let stillness = 1 - Double(visual.motion(at: sample.time)).clamped(0, 0.25) * 4
            return (sample.time, face, sqrt(face.area) * 3 + stillness)
        }
        .sorted { $0.2 > $1.2 }
        var taken = avoiding
        var out: [(time: Seconds, face: NormRect)] = []
        for (t, face, _) in scored where out.count < count {
            guard !taken.contains(where: { abs($0 - t) < spacing }) else { continue }
            taken.append(t)
            out.append((t, face))
        }
        return out
    }

    /// Within a couple of seconds of the payoff: favour a big face, low motion, and staying close to the peak.
    public static func bestMoment(near payoff: Seconds, in range: TimeRange, visual: VisualFeatureSeries?) -> (time: Seconds, face: NormRect?) {
        let window = TimeRange(start: max(range.start, payoff - 2), end: min(range.end, payoff + 1))
        guard let visual, window.duration > 0 else { return (payoff, nil) }
        var best: (time: Seconds, face: NormRect?, score: Double) = (payoff, nil, -.infinity)
        var options: [(Seconds, NormRect?)] = visual.faces(in: window).map { sample in
            (sample.time, sample.boxes.max { $0.area < $1.area })
        }
        options.append((payoff, nil))
        for (t, face) in options {
            let faceScore = face.map { min(1, sqrt($0.area) / 0.35) } ?? 0
            let stillness = 1 - Double(visual.motion(at: t)).clamped(0, 0.25) * 4
            let closeness = 1 - min(1, abs(t - payoff) / 3)
            let score = faceScore * 2 + stillness + closeness * 0.8
            if score > best.score { best = (t, face, score) }
        }
        // Without a face nearby, the peak itself is the frame — but still borrow the nearest face box
        // so a "face zoom" layout has something to aim at.
        if best.face == nil, let nearest = visual.faces.min(by: { abs($0.time - best.time) < abs($1.time - best.time) }),
           abs(nearest.time - best.time) < 4 {
            best.face = nearest.boxes.max { $0.area < $1.area }
        }
        return (best.time, best.face)
    }
}

/// Short, punchy thumbnail text from a clip title: first clause, no emoji or hashtags, a few words.
public enum ThumbnailHeadline {
    public static func make(from title: String, maxWords: Int = 4, maxCharacters: Int = 24) -> String {
        var text = String(title.unicodeScalars.filter { scalar in
            !(scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && scalar.value > 0x238C) || scalar.value == 0xFE0F)
        })
        text = text.split(separator: " ").filter { !$0.hasPrefix("#") && !$0.hasPrefix("@") }.joined(separator: " ")
        // First clause only — "He rage quit — then came back" → "He rage quit".
        for separator in [" — ", " – ", " - ", ": ", " | ", "(", ". "] {
            if let r = text.range(of: separator), text.distance(from: text.startIndex, to: r.lowerBound) >= 4 {
                text = String(text[..<r.lowerBound])
            }
        }
        // Clip titles are often quoted ("“DID YOU SEE THAT?” 🔥"): look past the quotes for ?/!.
        let ending = text.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'“”‘’")))
            .last.flatMap { "!?".contains($0) ? String($0) : nil } ?? ""
        let words = text.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'’$%")).inverted)
            .filter { !$0.isEmpty }
        var kept: [String] = []
        for word in words {
            let next = (kept + [word]).joined(separator: " ")
            if kept.count >= maxWords || (next.count > maxCharacters && !kept.isEmpty) { break }
            kept.append(word)
        }
        let result = kept.joined(separator: " ")
        return result.isEmpty ? "NO WAY" : result + (kept.count == words.count ? ending : "")
    }
}

// MARK: - Thumbnail Studio documents

/// A design in Thumbnail Studio's file format (its `ThumbDocument`), written by PULSE so the
/// studio opens it like one of its own. Only the fields PULSE sets are written — the studio fills
/// every missing field with its own default, so this stays compatible as the studio grows.
public struct ThumbStudioDocument: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int
    public var backgroundHex: String?
    public var layers: [ThumbStudioLayer]

    public init(width: Int = 1280, height: Int = 720, backgroundHex: String? = nil, layers: [ThumbStudioLayer] = []) {
        self.width = width
        self.height = height
        self.backgroundHex = backgroundHex
        self.layers = layers
    }
}

public struct ThumbStudioLayer: Codable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case image(ThumbStudioImage)
        case text(ThumbStudioText)
        case shape(ThumbStudioShape)
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    /// Centre, as fractions of the canvas.
    public var x: Double
    public var y: Double
    public var widthFraction: Double
    public var heightFraction: Double
    public var rotationDegrees: Double
    public var opacity: Double

    public init(id: UUID = UUID(), name: String, kind: Kind, x: Double = 0.5, y: Double = 0.5, widthFraction: Double = 0.5,
                heightFraction: Double = 0.3, rotationDegrees: Double = 0, opacity: Double = 1) {
        self.id = id
        self.name = name
        self.kind = kind
        self.x = x
        self.y = y
        self.widthFraction = widthFraction
        self.heightFraction = heightFraction
        self.rotationDegrees = rotationDegrees
        self.opacity = opacity
    }
}

/// Encoded exactly like Swift's synthesized enum coding, which is what the studio decodes:
/// `{"image": {"_0": {...}}}`.
extension ThumbStudioLayer.Kind: Codable {
    private enum CaseKey: String, CodingKey { case image, text, shape }
    private enum PayloadKey: String, CodingKey { case _0 }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        if let p = try? c.nestedContainer(keyedBy: PayloadKey.self, forKey: .image) {
            self = .image(try p.decode(ThumbStudioImage.self, forKey: ._0))
        } else if let p = try? c.nestedContainer(keyedBy: PayloadKey.self, forKey: .text) {
            self = .text(try p.decode(ThumbStudioText.self, forKey: ._0))
        } else {
            let p = try c.nestedContainer(keyedBy: PayloadKey.self, forKey: .shape)
            self = .shape(try p.decode(ThumbStudioShape.self, forKey: ._0))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        switch self {
        case .image(let spec):
            var p = c.nestedContainer(keyedBy: PayloadKey.self, forKey: .image)
            try p.encode(spec, forKey: ._0)
        case .text(let spec):
            var p = c.nestedContainer(keyedBy: PayloadKey.self, forKey: .text)
            try p.encode(spec, forKey: ._0)
        case .shape(let spec):
            var p = c.nestedContainer(keyedBy: PayloadKey.self, forKey: .shape)
            try p.encode(spec, forKey: ._0)
        }
    }
}

/// The studio's crop rectangle: fractions of the source image, top-left origin.
public struct ThumbStudioRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct ThumbStudioImage: Codable, Hashable, Sendable {
    public var path: String
    public var crop: ThumbStudioRect?
    public var contrast: Double = 0
    public var saturation: Double = 0
    public var vibrance: Double = 0
    public var sharpness: Double = 0
    public var vignette: Double = 0

    public init(path: String, crop: ThumbStudioRect? = nil) {
        self.path = path
        self.crop = crop
    }
}

public struct ThumbStudioStroke: Codable, Hashable, Sendable {
    public var id: UUID
    public var width: Double
    public var hex: String

    public init(id: UUID = UUID(), width: Double, hex: String) {
        self.id = id
        self.width = width
        self.hex = hex
    }
}

public struct ThumbStudioText: Codable, Hashable, Sendable {
    public var text: String
    public var uppercase = true
    /// Font size as a fraction of canvas height.
    public var sizeFraction: Double
    /// "left", "center", "right".
    public var alignment = "center"
    public var fillHex = "FFFFFF"
    public var gradientHex: String?
    public var strokeHex = "000000"
    public var strokeWidth: Double = 12
    public var extraStrokes: [ThumbStudioStroke] = []
    public var shadowEnabled = true

    public init(text: String, sizeFraction: Double) {
        self.text = text
        self.sizeFraction = sizeFraction
    }
}

public struct ThumbStudioShape: Codable, Hashable, Sendable {
    public var shape: String
    public var fillHex: String?
    public var fillGradientHex: String?
    public var gradientAngleDegrees: Double = 90
    /// "none", "left", "right", "top", "bottom" — that edge becomes a slant.
    public var cutEdge = "none"
    public var cutAmount: Double = 0.22
    public var cornerRadius: Double = 0
    public var strokeWidth: Double = 0

    public init(shape: String, fillHex: String?) {
        self.shape = shape
        self.fillHex = fillHex
    }
}

// MARK: - Layouts

/// Starting layouts PULSE builds around a frame. Each is a normal, fully editable studio design.
public enum ThumbnailLayout: String, CaseIterable, Codable, Identifiable, Sendable {
    /// The whole frame, graded to pop, big text across the top.
    case fullFrame
    /// Pushed in on the face (right of centre), text on the left.
    case faceZoom
    /// A slanted colour panel on the left carrying the text, the frame on the right.
    case panel

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fullFrame: return "Full Frame"
        case .faceZoom: return "Face Zoom"
        case .panel: return "Color Panel"
        }
    }

    public var symbol: String {
        switch self {
        case .fullFrame: return "rectangle.inset.filled"
        case .faceZoom: return "face.smiling"
        case .panel: return "rectangle.split.2x1"
        }
    }
}

public enum ThumbnailDesigner {
    public static let canvas = (width: 1280, height: 720)
    static let aspect = 16.0 / 9.0
    /// YouTube's duration badge (lower right) — never put text there.
    public static let durationBadge = NormRect(x: 0.80, y: 0.855, width: 0.19, height: 0.125)

    /// Crop (fractions of the source) that has the canvas's aspect, is `zoom`× in, and is centred
    /// on `focus` as far as the frame edges allow.
    public static func coverCrop(sourceAspect: Double, focus: Vec2? = nil, zoom: Double = 1) -> ThumbStudioRect {
        let source = sourceAspect > 0 ? sourceAspect : aspect
        var w = 1.0, h = 1.0
        if source >= aspect { w = aspect / source } else { h = source / aspect }
        let z = max(1, zoom)
        w /= z
        h /= z
        let cx = focus?.x ?? 0.5, cy = focus?.y ?? 0.5
        let x = (cx - w / 2).clamped(0, 1 - w)
        let y = (cy - h / 2).clamped(0, 1 - h)
        return ThumbStudioRect(x: x, y: y, width: w, height: h)
    }

    /// One design. `framePath` is the full-resolution frame already saved where the studio keeps images.
    public static func design(_ layout: ThumbnailLayout, framePath: String, sourceAspect: Double, face: NormRect?,
                              headline: String, accentHex: String = "FFD60A", panelHex: String = "FF2D55",
                              logoPath: String? = nil) -> ThumbStudioDocument {
        var doc = ThumbStudioDocument(width: canvas.width, height: canvas.height, backgroundHex: "000000")
        let text = headline.trimmingCharacters(in: .whitespacesAndNewlines)
        switch layout {
        case .fullFrame:
            // Aim a little above the face so heads aren't cut by the top text.
            let focus = face.map { Vec2($0.center.x, $0.center.y - 0.05) }
            doc.layers.append(frameLayer(framePath, crop: coverCrop(sourceAspect: sourceAspect, focus: focus, zoom: 1)))
            if !text.isEmpty {
                var spec = headlineSpec(text, size: 0.17, accentHex: accentHex)
                spec.extraStrokes = [ThumbStudioStroke(width: 22, hex: "FFFFFF")]
                spec.strokeWidth = 12
                doc.layers.append(ThumbStudioLayer(name: "Headline", kind: .text(spec), x: 0.5, y: 0.17, widthFraction: 0.92, heightFraction: 0.26))
            }
        case .faceZoom:
            // Face about 45% of the frame height, sitting right of centre.
            let faceHeight = max(face?.height ?? 0.25, 0.04)
            let zoom = (0.45 / faceHeight).clamped(1, 3.5)
            let crop0 = coverCrop(sourceAspect: sourceAspect, focus: face?.center, zoom: zoom)
            let shift = crop0.width * 0.2
            let focus = face.map { Vec2($0.center.x - shift, $0.center.y) }
            doc.layers.append(frameLayer(framePath, crop: coverCrop(sourceAspect: sourceAspect, focus: focus, zoom: zoom)))
            if !text.isEmpty {
                var spec = headlineSpec(text, size: 0.15, accentHex: accentHex)
                spec.alignment = "left"
                doc.layers.append(ThumbStudioLayer(name: "Headline", kind: .text(spec), x: 0.28, y: 0.45, widthFraction: 0.5, heightFraction: 0.5))
            }
        case .panel:
            // Frame shifted right so the face clears the panel.
            let focus = Vec2((face?.center.x ?? 0.5) - 0.18, face?.center.y ?? 0.5)
            doc.layers.append(frameLayer(framePath, crop: coverCrop(sourceAspect: sourceAspect, focus: focus, zoom: 1.15)))
            var panel = ThumbStudioShape(shape: "rectangle", fillHex: panelHex)
            panel.fillGradientHex = darker(panelHex)
            panel.cutEdge = "right"
            panel.cutAmount = 0.2
            doc.layers.append(ThumbStudioLayer(name: "Panel", kind: .shape(panel), x: 0.24, y: 0.5, widthFraction: 0.5, heightFraction: 1.02))
            if !text.isEmpty {
                var spec = headlineSpec(text, size: 0.14, accentHex: nil)
                spec.alignment = "left"
                doc.layers.append(ThumbStudioLayer(name: "Headline", kind: .text(spec), x: 0.22, y: 0.5, widthFraction: 0.4, heightFraction: 0.6))
            }
        }
        // Brand logo bottom-left — the bottom-right belongs to YouTube's duration badge.
        if let logoPath, !logoPath.isEmpty {
            doc.layers.append(ThumbStudioLayer(name: "Logo", kind: .image(ThumbStudioImage(path: logoPath)), x: 0.09, y: 0.87,
                                               widthFraction: 0.12, heightFraction: 0.12, opacity: 0.95))
        }
        return doc
    }

    static func frameLayer(_ path: String, crop: ThumbStudioRect) -> ThumbStudioLayer {
        // The standard "make it pop" grade; every value is a normal slider in the studio's inspector.
        var image = ThumbStudioImage(path: path, crop: crop)
        image.contrast = 0.15
        image.saturation = 0.15
        image.vibrance = 0.3
        image.sharpness = 0.3
        image.vignette = 0.3
        return ThumbStudioLayer(name: "PULSE frame", kind: .image(image), x: 0.5, y: 0.5, widthFraction: 1, heightFraction: 1)
    }

    static func headlineSpec(_ text: String, size: Double, accentHex: String?) -> ThumbStudioText {
        var spec = ThumbStudioText(text: text, sizeFraction: size)
        spec.gradientHex = accentHex
        spec.strokeWidth = 12
        return spec
    }

    /// The same colour at 60% brightness, for a panel gradient.
    static func darker(_ hex: String) -> String {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard cleaned.count == 6, let v = UInt32(cleaned, radix: 16) else { return hex }
        let r = Double((v >> 16) & 0xFF) * 0.6, g = Double((v >> 8) & 0xFF) * 0.6, b = Double(v & 0xFF) * 0.6
        return String(format: "%02X%02X%02X", Int(r), Int(g), Int(b))
    }

    /// "#RRGGBB" for a brand colour, so the panel and accent can follow the brand kit.
    public static func hex(_ color: RGBAColor) -> String {
        String(format: "%02X%02X%02X", Int((color.red * 255).rounded().clamped(0, 255)),
               Int((color.green * 255).rounded().clamped(0, 255)), Int((color.blue * 255).rounded().clamped(0, 255)))
    }

    /// A file name the studio's gallery will show: "My Stream – NO WAY (Face Zoom)".
    public static func designName(project: String, headline: String, layout: ThumbnailLayout) -> String {
        let clean = { (s: String) in
            s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let head = clean(headline).isEmpty ? "Thumbnail" : String(clean(headline).prefix(28))
        let name = "\(String(clean(project).prefix(24))) – \(head) (\(layout.displayName))"
        return String(name.prefix(60))
    }
}
