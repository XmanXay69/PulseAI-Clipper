import Foundation

public enum FontWeight: String, Codable, CaseIterable, Sendable {
    case regular, medium, semibold, bold, heavy, black

    public var displayName: String { rawValue.capitalized }

    /// CSS-like numeric weight (used when resolving fonts).
    public var numericValue: Int {
        switch self {
        case .regular: return 400
        case .medium: return 500
        case .semibold: return 600
        case .bold: return 700
        case .heavy: return 800
        case .black: return 900
        }
    }
}

public enum TextAlign: String, Codable, CaseIterable, Sendable {
    case leading, center, trailing
}

public enum TextCase: String, Codable, CaseIterable, Sendable {
    case asTyped, uppercase, lowercase, titleCase

    public var displayName: String {
        switch self {
        case .asTyped: return "As Typed"
        case .uppercase: return "UPPERCASE"
        case .lowercase: return "lowercase"
        case .titleCase: return "Title Case"
        }
    }

    public func apply(_ text: String) -> String {
        switch self {
        case .asTyped: return text
        case .uppercase: return text.uppercased()
        case .lowercase: return text.lowercased()
        case .titleCase: return text.capitalized
        }
    }
}

public enum TextAnimation: String, Codable, CaseIterable, Sendable {
    case none, fadeIn, pop, slideUp, typewriter, bounce

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .fadeIn: return "Fade In"
        case .pop: return "Pop"
        case .slideUp: return "Slide Up"
        case .typewriter: return "Typewriter"
        case .bounce: return "Bounce"
        }
    }
}

/// Shared typographic styling for titles, labels and captions.
public struct TextStyle: Codable, Hashable, Sendable {
    /// TikTok's open-source typeface, bundled with PULSE (falls back to SF Pro if it's ever missing).
    public static let tiktokSans = "TikTok Sans"

    public var fontName: String
    /// Size in pixels on a 1080-px-wide canvas; scaled to the actual canvas at render time.
    public var fontSize: Double
    public var weight: FontWeight
    public var italic: Bool
    public var textCase: TextCase
    public var color: RGBAColor
    public var strokeColor: RGBAColor
    public var strokeWidth: Double
    public var shadowColor: RGBAColor
    public var shadowOpacity: Double
    public var shadowRadius: Double
    public var shadowOffsetY: Double
    public var backgroundColor: RGBAColor
    public var backgroundOpacity: Double
    public var backgroundPadding: Double
    public var backgroundCornerRadius: Double
    public var alignment: TextAlign
    public var letterSpacing: Double
    public var lineHeight: Double

    public init(fontName: String = TextStyle.tiktokSans, fontSize: Double = 72, weight: FontWeight = .heavy,
                italic: Bool = false, textCase: TextCase = .asTyped, color: RGBAColor = .white,
                strokeColor: RGBAColor = .black, strokeWidth: Double = 0, shadowColor: RGBAColor = .black,
                shadowOpacity: Double = 0.45, shadowRadius: Double = 8, shadowOffsetY: Double = 4,
                backgroundColor: RGBAColor = .black, backgroundOpacity: Double = 0, backgroundPadding: Double = 14,
                backgroundCornerRadius: Double = 12, alignment: TextAlign = .center, letterSpacing: Double = 0,
                lineHeight: Double = 1.1) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.weight = weight
        self.italic = italic
        self.textCase = textCase
        self.color = color
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.shadowColor = shadowColor
        self.shadowOpacity = shadowOpacity
        self.shadowRadius = shadowRadius
        self.shadowOffsetY = shadowOffsetY
        self.backgroundColor = backgroundColor
        self.backgroundOpacity = backgroundOpacity
        self.backgroundPadding = backgroundPadding
        self.backgroundCornerRadius = backgroundCornerRadius
        self.alignment = alignment
        self.letterSpacing = letterSpacing
        self.lineHeight = lineHeight
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TextStyle()
        fontName = c.decode(String.self, forKey: .fontName, default: d.fontName)
        fontSize = c.decode(Double.self, forKey: .fontSize, default: d.fontSize)
        weight = c.decode(FontWeight.self, forKey: .weight, default: d.weight)
        italic = c.decode(Bool.self, forKey: .italic, default: d.italic)
        textCase = c.decode(TextCase.self, forKey: .textCase, default: d.textCase)
        color = c.decode(RGBAColor.self, forKey: .color, default: d.color)
        strokeColor = c.decode(RGBAColor.self, forKey: .strokeColor, default: d.strokeColor)
        strokeWidth = c.decode(Double.self, forKey: .strokeWidth, default: d.strokeWidth)
        shadowColor = c.decode(RGBAColor.self, forKey: .shadowColor, default: d.shadowColor)
        shadowOpacity = c.decode(Double.self, forKey: .shadowOpacity, default: d.shadowOpacity)
        shadowRadius = c.decode(Double.self, forKey: .shadowRadius, default: d.shadowRadius)
        shadowOffsetY = c.decode(Double.self, forKey: .shadowOffsetY, default: d.shadowOffsetY)
        backgroundColor = c.decode(RGBAColor.self, forKey: .backgroundColor, default: d.backgroundColor)
        backgroundOpacity = c.decode(Double.self, forKey: .backgroundOpacity, default: d.backgroundOpacity)
        backgroundPadding = c.decode(Double.self, forKey: .backgroundPadding, default: d.backgroundPadding)
        backgroundCornerRadius = c.decode(Double.self, forKey: .backgroundCornerRadius, default: d.backgroundCornerRadius)
        alignment = c.decode(TextAlign.self, forKey: .alignment, default: d.alignment)
        letterSpacing = c.decode(Double.self, forKey: .letterSpacing, default: d.letterSpacing)
        lineHeight = c.decode(Double.self, forKey: .lineHeight, default: d.lineHeight)
    }
}

/// Free text layer: titles, labels, callouts, meme text.
public struct TextElement: Codable, Hashable, Sendable {
    public var text: String
    public var style: TextStyle
    public var animationIn: TextAnimation
    public var animationOut: TextAnimation
    public var animationDuration: Seconds
    /// Maximum text box width as a fraction of canvas width (wrapping).
    public var maxWidth: Double

    public init(text: String, style: TextStyle = TextStyle(), animationIn: TextAnimation = .pop,
                animationOut: TextAnimation = .none, animationDuration: Seconds = 0.3, maxWidth: Double = 0.86) {
        self.text = text
        self.style = style
        self.animationIn = animationIn
        self.animationOut = animationOut
        self.animationDuration = animationDuration
        self.maxWidth = maxWidth
    }
}
