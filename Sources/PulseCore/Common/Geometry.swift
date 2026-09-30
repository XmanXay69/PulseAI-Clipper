import Foundation

/// 2D vector / point. PulseCore avoids CoreGraphics so it stays platform-neutral.
public struct Vec2: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, k: Double) -> Vec2 { Vec2(a.x * k, a.y * k) }

    public func distance(to other: Vec2) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

public struct Size2: Codable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(_ width: Double, _ height: Double) {
        self.width = width
        self.height = height
    }

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let zero = Size2(0, 0)

    /// width / height; 1 when degenerate.
    public var aspect: Double { height > 0 ? width / height : 1 }
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    public func scaled(_ k: Double) -> Size2 { Size2(width * k, height * k) }

    /// Largest size with `aspect` that fits inside `self`.
    public func fitting(aspect: Double) -> Size2 {
        guard aspect > 0, !isEmpty else { return self }
        if self.aspect > aspect {
            return Size2(height * aspect, height)
        }
        return Size2(width, width / aspect)
    }
}

/// Rectangle in normalized coordinates (0…1), origin at the TOP-LEFT, y pointing down.
/// Used for crops (relative to the source frame) and placements (relative to the canvas).
public struct NormRect: Codable, Hashable, Sendable, CustomStringConvertible {
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

    public init(center: Vec2, width: Double, height: Double) {
        self.init(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }

    public static let full = NormRect(x: 0, y: 0, width: 1, height: 1)

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var center: Vec2 { Vec2(x + width / 2, y + height / 2) }
    public var area: Double { Swift.max(0, width) * Swift.max(0, height) }
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    /// Aspect ratio of this rect when mapped onto a frame of `frameSize`.
    public func pixelAspect(in frameSize: Size2) -> Double {
        let w = width * frameSize.width
        let h = height * frameSize.height
        return h > 0 ? w / h : 1
    }

    public func contains(_ p: Vec2) -> Bool {
        p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY
    }

    public func intersection(_ other: NormRect) -> NormRect? {
        let x0 = Swift.max(minX, other.minX)
        let y0 = Swift.max(minY, other.minY)
        let x1 = Swift.min(maxX, other.maxX)
        let y1 = Swift.min(maxY, other.maxY)
        guard x1 > x0, y1 > y0 else { return nil }
        return NormRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    public func union(_ other: NormRect) -> NormRect {
        let x0 = Swift.min(minX, other.minX)
        let y0 = Swift.min(minY, other.minY)
        let x1 = Swift.max(maxX, other.maxX)
        let y1 = Swift.max(maxY, other.maxY)
        return NormRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    public func iou(_ other: NormRect) -> Double {
        guard let i = intersection(other) else { return 0 }
        let u = area + other.area - i.area
        return u > 0 ? i.area / u : 0
    }

    /// Scales about the rect's own center.
    public func scaled(by k: Double) -> NormRect {
        NormRect(center: center, width: width * k, height: height * k)
    }

    public func offsetBy(dx: Double, dy: Double) -> NormRect {
        NormRect(x: x + dx, y: y + dy, width: width, height: height)
    }

    public func insetBy(dx: Double, dy: Double) -> NormRect {
        NormRect(x: x + dx, y: y + dy, width: width - 2 * dx, height: height - 2 * dy)
    }

    /// Moves (without resizing when possible) so the rect lies within the unit square.
    /// If the rect is larger than the unit square in a dimension it is shrunk to fit.
    public func clampedToUnit() -> NormRect {
        var r = self
        r.width = Swift.min(Swift.max(r.width, 0.0001), 1)
        r.height = Swift.min(Swift.max(r.height, 0.0001), 1)
        r.x = Swift.min(Swift.max(r.x, 0), 1 - r.width)
        r.y = Swift.min(Swift.max(r.y, 0), 1 - r.height)
        return r
    }

    /// Returns the largest rect with the given *pixel* aspect ratio (for a frame of `frameSize`)
    /// centered as close as possible to `focus`, fully inside the unit square.
    public static func crop(aspect targetAspect: Double, frameSize: Size2, focus: Vec2 = Vec2(0.5, 0.5), zoom: Double = 1) -> NormRect {
        guard !frameSize.isEmpty, targetAspect > 0 else { return .full }
        let frameAspect = frameSize.aspect
        var w: Double
        var h: Double
        if targetAspect < frameAspect {
            // Target is narrower than the frame: full height, partial width.
            h = 1
            w = (targetAspect / frameAspect)
        } else {
            w = 1
            h = frameAspect / targetAspect
        }
        let z = Swift.max(zoom, 1)
        w /= z
        h /= z
        return NormRect(center: focus, width: w, height: h).clampedToUnit()
    }

    /// Converts to pixel rect (top-left origin) for a frame size.
    public func pixels(in size: Size2) -> (x: Double, y: Double, width: Double, height: Double) {
        (x * size.width, y * size.height, width * size.width, height * size.height)
    }

    public var description: String {
        String(format: "NormRect(%.3f, %.3f, %.3f × %.3f)", x, y, width, height)
    }
}

/// sRGB color with alpha, all components 0…1.
public struct RGBAColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `#RRGGBB` or `#RRGGBBAA`.
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        if s.count == 6 {
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1
        } else {
            red = Double((value >> 24) & 0xFF) / 255
            green = Double((value >> 16) & 0xFF) / 255
            blue = Double((value >> 8) & 0xFF) / 255
            alpha = Double(value & 0xFF) / 255
        }
    }

    public var hexString: String {
        let r = Int((red * 255).rounded()).clamped(0, 255)
        let g = Int((green * 255).rounded()).clamped(0, 255)
        let b = Int((blue * 255).rounded()).clamped(0, 255)
        if alpha < 0.999 {
            let a = Int((alpha * 255).rounded()).clamped(0, 255)
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    public func withAlpha(_ a: Double) -> RGBAColor {
        RGBAColor(red: red, green: green, blue: blue, alpha: a)
    }

    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
    public static let clear = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0)
    public static let yellow = RGBAColor(hex: "#FFD60A")!
    public static let pulse = RGBAColor(hex: "#FF3D6E")!
    public static let mint = RGBAColor(hex: "#3DDC97")!
    public static let cyan = RGBAColor(hex: "#35C8FF")!
    public static let violet = RGBAColor(hex: "#8C6CFF")!
}
