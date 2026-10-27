import Foundation

/// The app's accent colour (#425). The AI violet stays the same whichever you pick, so AI features keep
/// their own colour.
public enum AccentChoice: String, Codable, CaseIterable, Sendable {
    case pulse, electric, lime, amber

    public var displayName: String {
        switch self {
        case .pulse: return "Pulse pink"
        case .electric: return "Electric blue"
        case .lime: return "Lime"
        case .amber: return "Amber"
        }
    }

    /// The colour as 0xRRGGBB.
    public var hex: UInt32 {
        switch self {
        case .pulse: return 0xFF3D6E
        case .electric: return 0x3D8BFF
        case .lime: return 0xA6E22E
        case .amber: return 0xFFB020
        }
    }

    /// The far end of the accent gradient — a little warmer or cooler so filled controls read as lit.
    public var gradientEndHex: UInt32 {
        switch self {
        case .pulse: return 0xFF6A4D
        case .electric: return 0x5EDBFF
        case .lime: return 0x3DDC97
        case .amber: return 0xFF7A3D
        }
    }
}

/// Dark (the default), light, or whatever macOS is set to (#424).
public enum AppAppearance: String, Codable, CaseIterable, Sendable {
    case dark, light, system

    public var displayName: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .system: return "Match macOS"
        }
    }
}
