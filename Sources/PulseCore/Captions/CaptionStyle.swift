import Foundation

public enum CaptionAnimation: String, Codable, CaseIterable, Sendable {
    case none, pop, bounce, fade, slideUp, typewriter

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .pop: return "Pop"
        case .bounce: return "Bounce"
        case .fade: return "Fade"
        case .slideUp: return "Slide Up"
        case .typewriter: return "Typewriter"
        }
    }
}

public enum WordHighlightMode: String, Codable, CaseIterable, Sendable {
    case none, color, box, scale, colorAndScale

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .color: return "Color"
        case .box: return "Box"
        case .scale: return "Scale"
        case .colorAndScale: return "Color + Scale"
        }
    }
}

public enum CaptionDisplayMode: String, Codable, CaseIterable, Sendable {
    /// Groups of words (pages) with the spoken word highlighted.
    case phrase
    /// One word at a time ("I" / "CAN'T" / "BELIEVE" / "THAT").
    case wordByWord
    /// Words appear cumulatively within the page as they're spoken.
    case reveal

    public var displayName: String {
        switch self {
        case .phrase: return "Phrase"
        case .wordByWord: return "Word by Word"
        case .reveal: return "Reveal"
        }
    }
}

public enum ProfanityMode: String, Codable, CaseIterable, Sendable {
    case off, mask, bleepText, hide

    public var displayName: String {
        switch self {
        case .off: return "Show"
        case .mask: return "Mask (f***)"
        case .bleepText: return "[bleep]"
        case .hide: return "Hide word"
        }
    }
}

/// Complete caption look. Every field is user-editable; presets are just starting points.
public struct CaptionStyle: Codable, Hashable, Sendable {
    public var presetName: String
    public var text: TextStyle
    public var highlightColor: RGBAColor
    public var highlightBoxColor: RGBAColor
    public var emphasisColor: RGBAColor
    public var emphasisScale: Double
    public var highlightMode: WordHighlightMode
    public var animation: CaptionAnimation
    /// 1 = normal; higher = snappier animations.
    public var animationSpeed: Double
    public var displayMode: CaptionDisplayMode
    public var maxWordsPerPage: Int
    public var maxCharsPerLine: Int
    public var maxLines: Int
    /// Center of the caption block (normalized canvas).
    public var positionX: Double
    public var positionY: Double
    /// Keep captions clear of this platform's UI.
    public var safeArea: SafeAreaPlatform?

    public init(presetName: String, text: TextStyle, highlightColor: RGBAColor = .yellow, highlightBoxColor: RGBAColor = .pulse,
                emphasisColor: RGBAColor = .yellow, emphasisScale: Double = 1.12, highlightMode: WordHighlightMode = .color,
                animation: CaptionAnimation = .pop, animationSpeed: Double = 1, displayMode: CaptionDisplayMode = .phrase,
                maxWordsPerPage: Int = 4, maxCharsPerLine: Int = 18, maxLines: Int = 2, positionX: Double = 0.5,
                positionY: Double = 0.7, safeArea: SafeAreaPlatform? = .tiktok) {
        self.presetName = presetName
        self.text = text
        self.highlightColor = highlightColor
        self.highlightBoxColor = highlightBoxColor
        self.emphasisColor = emphasisColor
        self.emphasisScale = emphasisScale
        self.highlightMode = highlightMode
        self.animation = animation
        self.animationSpeed = animationSpeed
        self.displayMode = displayMode
        self.maxWordsPerPage = maxWordsPerPage
        self.maxCharsPerLine = maxCharsPerLine
        self.maxLines = maxLines
        self.positionX = positionX
        self.positionY = positionY
        self.safeArea = safeArea
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CaptionStyle.bold
        presetName = c.decode(String.self, forKey: .presetName, default: "Custom")
        text = c.decode(TextStyle.self, forKey: .text, default: d.text)
        highlightColor = c.decode(RGBAColor.self, forKey: .highlightColor, default: d.highlightColor)
        highlightBoxColor = c.decode(RGBAColor.self, forKey: .highlightBoxColor, default: d.highlightBoxColor)
        emphasisColor = c.decode(RGBAColor.self, forKey: .emphasisColor, default: d.emphasisColor)
        emphasisScale = c.decode(Double.self, forKey: .emphasisScale, default: d.emphasisScale)
        highlightMode = c.decode(WordHighlightMode.self, forKey: .highlightMode, default: d.highlightMode)
        animation = c.decode(CaptionAnimation.self, forKey: .animation, default: d.animation)
        animationSpeed = c.decode(Double.self, forKey: .animationSpeed, default: d.animationSpeed)
        displayMode = c.decode(CaptionDisplayMode.self, forKey: .displayMode, default: d.displayMode)
        maxWordsPerPage = c.decode(Int.self, forKey: .maxWordsPerPage, default: d.maxWordsPerPage)
        maxCharsPerLine = c.decode(Int.self, forKey: .maxCharsPerLine, default: d.maxCharsPerLine)
        maxLines = c.decode(Int.self, forKey: .maxLines, default: d.maxLines)
        positionX = c.decode(Double.self, forKey: .positionX, default: d.positionX)
        positionY = c.decode(Double.self, forKey: .positionY, default: d.positionY)
        safeArea = c.decode(SafeAreaPlatform?.self, forKey: .safeArea, default: d.safeArea)
    }

    // MARK: Presets

    /// TikTok's own look: TikTok Sans Bold, white with a thin dark outline, sentence case, two short lines.
    public static let tiktok = CaptionStyle(
        presetName: "TikTok",
        text: TextStyle(fontName: TextStyle.tiktokSans, fontSize: 76, weight: .bold, textCase: .asTyped, color: .white,
                        strokeColor: .black, strokeWidth: 5, shadowOpacity: 0.45, shadowRadius: 6, shadowOffsetY: 3),
        highlightColor: RGBAColor(hex: "#FE2C55")!, highlightMode: .color, animation: .pop, displayMode: .phrase,
        maxWordsPerPage: 4, maxCharsPerLine: 18, maxLines: 2, positionY: 0.66)

    public static let clean = CaptionStyle(
        presetName: "Clean",
        text: TextStyle(fontName: TextStyle.tiktokSans, fontSize: 64, weight: .bold, textCase: .asTyped, color: .white,
                        strokeWidth: 0, shadowOpacity: 0.55, shadowRadius: 10, shadowOffsetY: 3),
        highlightColor: RGBAColor(hex: "#FFFFFF")!, highlightMode: .none, animation: .fade, displayMode: .phrase,
        maxWordsPerPage: 6, maxCharsPerLine: 24, maxLines: 2, positionY: 0.72)

    public static let bold = CaptionStyle(
        presetName: "Bold",
        text: TextStyle(fontName: TextStyle.tiktokSans, fontSize: 84, weight: .black, textCase: .uppercase, color: .white,
                        strokeColor: .black, strokeWidth: 9, shadowOpacity: 0.5, shadowRadius: 6, shadowOffsetY: 5),
        highlightColor: .yellow, highlightMode: .colorAndScale, animation: .pop, displayMode: .phrase,
        maxWordsPerPage: 3, maxCharsPerLine: 14, maxLines: 2, positionY: 0.66)

    public static let gaming = CaptionStyle(
        presetName: "Gaming",
        text: TextStyle(fontName: "SF Pro Rounded", fontSize: 86, weight: .black, italic: false, textCase: .uppercase,
                        color: .white, strokeColor: RGBAColor(hex: "#0B0B12")!, strokeWidth: 10, shadowColor: RGBAColor(hex: "#35C8FF")!,
                        shadowOpacity: 0.6, shadowRadius: 14, shadowOffsetY: 0),
        highlightColor: RGBAColor(hex: "#3DDC97")!, emphasisColor: RGBAColor(hex: "#FF3D6E")!, emphasisScale: 1.18,
        highlightMode: .colorAndScale, animation: .bounce, displayMode: .phrase, maxWordsPerPage: 3, maxCharsPerLine: 14,
        maxLines: 2, positionY: 0.5)

    public static let meme = CaptionStyle(
        presetName: "Meme",
        text: TextStyle(fontName: "Impact", fontSize: 96, weight: .black, textCase: .uppercase, color: .white,
                        strokeColor: .black, strokeWidth: 12, shadowOpacity: 0, shadowRadius: 0, shadowOffsetY: 0),
        highlightColor: .white, highlightMode: .none, animation: .none, displayMode: .phrase,
        maxWordsPerPage: 5, maxCharsPerLine: 16, maxLines: 2, positionY: 0.14, safeArea: nil)

    public static let minimal = CaptionStyle(
        presetName: "Minimal",
        text: TextStyle(fontName: TextStyle.tiktokSans, fontSize: 50, weight: .medium, textCase: .lowercase, color: .white,
                        strokeWidth: 0, shadowOpacity: 0.35, shadowRadius: 6, shadowOffsetY: 2),
        highlightColor: RGBAColor(hex: "#FFFFFF")!, highlightMode: .none, animation: .fade, displayMode: .phrase,
        maxWordsPerPage: 7, maxCharsPerLine: 28, maxLines: 2, positionY: 0.78)

    public static let cinematic = CaptionStyle(
        presetName: "Cinematic",
        text: TextStyle(fontName: "New York", fontSize: 56, weight: .semibold, italic: true, textCase: .asTyped,
                        color: RGBAColor(hex: "#F5F0E6")!, strokeWidth: 0, shadowOpacity: 0.6, shadowRadius: 12,
                        shadowOffsetY: 2, letterSpacing: 1.5),
        highlightColor: RGBAColor(hex: "#F5C16C")!, highlightMode: .color, animation: .fade, displayMode: .phrase,
        maxWordsPerPage: 6, maxCharsPerLine: 26, maxLines: 2, positionY: 0.82)

    public static let podcast = CaptionStyle(
        presetName: "Podcast",
        text: TextStyle(fontName: TextStyle.tiktokSans, fontSize: 66, weight: .heavy, textCase: .asTyped, color: .white,
                        strokeWidth: 0, shadowOpacity: 0, backgroundColor: RGBAColor(hex: "#101014")!,
                        backgroundOpacity: 0.78, backgroundPadding: 18, backgroundCornerRadius: 16),
        highlightColor: RGBAColor(hex: "#101014")!, highlightBoxColor: RGBAColor(hex: "#FFD60A")!, highlightMode: .box,
        animation: .pop, displayMode: .phrase, maxWordsPerPage: 5, maxCharsPerLine: 20, maxLines: 2, positionY: 0.68)

    public static let highEnergy = CaptionStyle(
        presetName: "High Energy",
        text: TextStyle(fontName: TextStyle.tiktokSans, fontSize: 104, weight: .black, italic: true, textCase: .uppercase,
                        color: .white, strokeColor: .black, strokeWidth: 12, shadowOpacity: 0.65, shadowRadius: 0,
                        shadowOffsetY: 8),
        highlightColor: RGBAColor(hex: "#FF3D6E")!, emphasisColor: RGBAColor(hex: "#FFD60A")!, emphasisScale: 1.25,
        highlightMode: .colorAndScale, animation: .bounce, animationSpeed: 1.4, displayMode: .wordByWord,
        maxWordsPerPage: 1, maxCharsPerLine: 12, maxLines: 1, positionY: 0.58)

    public static let presets: [CaptionStyle] = [.tiktok, .clean, .bold, .gaming, .meme, .minimal, .cinematic, .podcast, .highEnergy]

    public static func preset(named name: String) -> CaptionStyle? {
        presets.first { $0.presetName.caseInsensitiveCompare(name) == .orderedSame }
    }
}
