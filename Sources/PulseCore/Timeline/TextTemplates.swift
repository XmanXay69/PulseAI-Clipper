import Foundation

/// A text layer's look, ready to apply (#217): built-in lower third, callout, meme and title styles, plus the
/// ones you save from the inspector.
public struct TextTemplate: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var style: TextStyle
    public var animationIn: TextAnimation
    public var animationOut: TextAnimation
    public var maxWidth: Double
    public var positionX: Double
    public var positionY: Double
    public var builtIn: Bool

    public init(id: UUID = UUID(), name: String, style: TextStyle, animationIn: TextAnimation = .pop, animationOut: TextAnimation = .fadeIn,
                maxWidth: Double = 0.9, positionX: Double = 0.5, positionY: Double = 0.5, builtIn: Bool = false) {
        self.id = id
        self.name = name
        self.style = style
        self.animationIn = animationIn
        self.animationOut = animationOut
        self.maxWidth = maxWidth
        self.positionX = positionX
        self.positionY = positionY
        self.builtIn = builtIn
    }

    /// Applies the look to a text clip, keeping its words and timing.
    public func apply(to clip: inout TimelineClip) {
        guard case .text(var element) = clip.content else { return }
        element.style = style
        element.animationIn = animationIn
        element.animationOut = animationOut
        element.maxWidth = maxWidth
        clip.content = .text(element)
        clip.transform.positionX = AnimatedDouble(positionX)
        clip.transform.positionY = AnimatedDouble(positionY)
    }

    /// A template from a text clip as it stands.
    public static func capture(_ clip: TimelineClip, name: String) -> TextTemplate? {
        guard case .text(let element) = clip.content else { return nil }
        return TextTemplate(name: name, style: element.style, animationIn: element.animationIn, animationOut: element.animationOut,
                            maxWidth: element.maxWidth, positionX: clip.transform.positionX.value(at: 0), positionY: clip.transform.positionY.value(at: 0))
    }
}

public enum TextTemplates {
    public static let lowerThird = TextTemplate(
        name: "Lower third",
        style: TextStyle(fontName: TextStyle.tiktokSans, fontSize: 44, weight: .bold, textCase: .asTyped, color: .white,
                         strokeWidth: 0, shadowOpacity: 0, backgroundColor: RGBAColor(hex: "#101014")!, backgroundOpacity: 0.85,
                         backgroundPadding: 16, backgroundCornerRadius: 8),
        animationIn: .slideUp, animationOut: .fadeIn, maxWidth: 0.6, positionX: 0.28, positionY: 0.84, builtIn: true)

    public static let callout = TextTemplate(
        name: "Callout",
        style: TextStyle(fontName: TextStyle.tiktokSans, fontSize: 56, weight: .heavy, textCase: .asTyped, color: RGBAColor(hex: "#101014")!,
                         strokeWidth: 0, shadowOpacity: 0.35, shadowRadius: 10, shadowOffsetY: 6, backgroundColor: RGBAColor(hex: "#FFD60A")!,
                         backgroundOpacity: 1, backgroundPadding: 22, backgroundCornerRadius: 18),
        animationIn: .pop, animationOut: .pop, maxWidth: 0.7, positionX: 0.5, positionY: 0.3, builtIn: true)

    public static let meme = TextTemplate(
        name: "Meme",
        style: TextStyle(fontName: "Impact", fontSize: 84, weight: .black, textCase: .uppercase, color: .white,
                         strokeColor: .black, strokeWidth: 12, shadowOpacity: 0, backgroundOpacity: 0),
        animationIn: .none, animationOut: .none, maxWidth: 0.92, positionX: 0.5, positionY: 0.12, builtIn: true)

    public static let bigTitle = TextTemplate(
        name: "Big title",
        style: TextStyle(fontName: TextStyle.tiktokSans, fontSize: 110, weight: .black, textCase: .uppercase, color: .white,
                         strokeColor: .black, strokeWidth: 10, shadowOpacity: 0.5, shadowRadius: 8, shadowOffsetY: 6, backgroundOpacity: 0),
        animationIn: .pop, animationOut: .fadeIn, maxWidth: 0.9, positionX: 0.5, positionY: 0.5, builtIn: true)

    public static let subtitle = TextTemplate(
        name: "Subtitle",
        style: TextStyle(fontName: TextStyle.tiktokSans, fontSize: 48, weight: .semibold, textCase: .asTyped, color: .white,
                         strokeColor: .black, strokeWidth: 4, shadowOpacity: 0.4, shadowRadius: 4, shadowOffsetY: 2, backgroundOpacity: 0),
        animationIn: .fadeIn, animationOut: .fadeIn, maxWidth: 0.85, positionX: 0.5, positionY: 0.86, builtIn: true)

    public static let builtIn: [TextTemplate] = [lowerThird, callout, meme, bigTitle, subtitle]
}
