import Foundation

/// The app's accent colour (#425). One accent everywhere: buttons, selection, the playhead and the sparkle on
/// what the AI made. The default is the blue PULSE shares with BulkBoard.
public enum AccentChoice: String, Codable, CaseIterable, Sendable {
    case pulse, pink, electric, lime, amber

    public var displayName: String {
        switch self {
        case .pulse: return "Blue"
        case .pink: return "Pink"
        case .electric: return "Violet"
        case .lime: return "Lime"
        case .amber: return "Amber"
        }
    }

    /// The colour as 0xRRGGBB.
    public var hex: UInt32 {
        switch self {
        case .pulse: return 0x4C8DFF
        case .pink: return 0xFF3D6E
        case .electric: return 0x8C7BE0
        case .lime: return 0xA6E22E
        case .amber: return 0xFFB020
        }
    }

    /// A neighbouring shade of the accent, for the app icon and other artwork that wants two tones.
    public var gradientEndHex: UInt32 {
        switch self {
        case .pulse: return 0x7FB0FF
        case .pink: return 0xFF6A4D
        case .electric: return 0xB4A6F5
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
