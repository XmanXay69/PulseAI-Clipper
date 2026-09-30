import Foundation

/// Output frame presets per platform.
public struct CanvasPreset: Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var width: Int
    public var height: Int
    public var symbolName: String
    public var safeArea: SafeAreaPlatform?

    public var aspectLabel: String { CanvasSettings(width: width, height: height).aspectLabel }

    public func canvas(frameRate: Double) -> CanvasSettings {
        CanvasSettings(width: width, height: height, frameRate: frameRate)
    }

    public static let tiktok = CanvasPreset(id: "tiktok", name: "TikTok", width: 1080, height: 1920, symbolName: "music.note", safeArea: .tiktok)
    public static let shorts = CanvasPreset(id: "shorts", name: "YouTube Shorts", width: 1080, height: 1920, symbolName: "play.rectangle", safeArea: .youtubeShorts)
    public static let reels = CanvasPreset(id: "reels", name: "Instagram Reels", width: 1080, height: 1920, symbolName: "camera", safeArea: .instagramReels)
    public static let youtube = CanvasPreset(id: "youtube", name: "YouTube", width: 1920, height: 1080, symbolName: "play.tv", safeArea: nil)
    public static let twitter = CanvasPreset(id: "twitter", name: "Twitter / X", width: 1920, height: 1080, symbolName: "bubble.left", safeArea: nil)
    public static let square = CanvasPreset(id: "square", name: "Square 1:1", width: 1080, height: 1080, symbolName: "square", safeArea: nil)
    public static let portrait = CanvasPreset(id: "portrait", name: "Portrait 4:5", width: 1080, height: 1350, symbolName: "rectangle.portrait", safeArea: nil)

    public static let all: [CanvasPreset] = [.tiktok, .shorts, .reels, .youtube, .twitter, .square, .portrait]

    public static func preset(id: String) -> CanvasPreset? { all.first { $0.id == id } }
}

/// Aspect ratios offered by the canvas menu.
public enum AspectChoice: String, CaseIterable, Sendable {
    case vertical = "9:16"
    case square = "1:1"
    case landscape = "16:9"
    case portrait = "4:5"

    public var size: (width: Int, height: Int) {
        switch self {
        case .vertical: return (1080, 1920)
        case .square: return (1080, 1080)
        case .landscape: return (1920, 1080)
        case .portrait: return (1080, 1350)
        }
    }
}
