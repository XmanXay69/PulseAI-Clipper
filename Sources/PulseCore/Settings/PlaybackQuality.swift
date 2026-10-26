import Foundation

/// How large the viewer renders each frame (#187). Lower is lighter on the GPU; exports always render full size.
public enum PlaybackQuality: String, Codable, CaseIterable, Sendable {
    case full, half, quarter

    public var scale: Double {
        switch self {
        case .full: return 1
        case .half: return 0.5
        case .quarter: return 0.25
        }
    }

    public var displayName: String {
        switch self {
        case .full: return "Full"
        case .half: return "½"
        case .quarter: return "¼"
        }
    }

    public var longName: String {
        switch self {
        case .full: return "Full quality"
        case .half: return "Half quality"
        case .quarter: return "Quarter quality"
        }
    }

    /// The next step down, or nil at the bottom.
    public var lower: PlaybackQuality? {
        switch self {
        case .full: return .half
        case .half: return .quarter
        case .quarter: return nil
        }
    }

    /// The viewer render size for a canvas at this quality, kept even for the encoder.
    public func renderSize(width: Int, height: Int) -> (width: Int, height: Int) {
        func even(_ v: Double) -> Int { max(2, Int(v.rounded()) / 2 * 2) }
        return (even(Double(width) * scale), even(Double(height) * scale))
    }
}
