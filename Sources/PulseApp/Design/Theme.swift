import AppKit
import PulseCore
import SwiftUI

/// PULSE design tokens. Dark, dense, professional — subtle borders, compact controls,
/// a single energetic accent ("pulse") plus a violet reserved for AI features.
enum Theme {
    // Surfaces (darkest → lightest): neutral graphite, like a pro grading/editing suite.
    static let window = Color(hex: 0x151517)
    static let panel = Color(hex: 0x1C1C1F)
    static let panelRaised = Color(hex: 0x232327)
    static let control = Color(hex: 0x2C2C31)
    static let controlHover = Color(hex: 0x36363C)
    static let well = Color(hex: 0x101012)

    static let border = Color.white.opacity(0.07)
    static let borderStrong = Color.white.opacity(0.13)
    static let divider = Color.white.opacity(0.05)

    // Text.
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.38)

    // Accents.
    static let accent = Color(hex: 0xFF3D6E)          // Pulse pink-red
    static let accentSoft = Color(hex: 0xFF3D6E).opacity(0.16)
    static let ai = Color(hex: 0x8C6CFF)              // AI violet
    static let aiSoft = Color(hex: 0x8C6CFF).opacity(0.16)
    static let success = Color(hex: 0x3DDC97)
    static let warning = Color(hex: 0xFFB020)
    static let danger = Color(hex: 0xFF5A5F)
    static let info = Color(hex: 0x35C8FF)

    // Track colors.
    static let videoClip = Color(hex: 0x3A6FF7)
    static let webcamClip = Color(hex: 0x19A38A)
    static let audioClip = Color(hex: 0x2FA86A)
    static let musicClip = Color(hex: 0xD08B2E)
    static let sfxClip = Color(hex: 0xC4508C)
    static let textClip = Color(hex: 0x9B6BFF)
    static let compoundClip = Color(hex: 0xC2873A)

    /// Stable, distinct color per speaker.
    static func speakerColor(_ id: Int) -> Color {
        let palette: [UInt32] = [0x35C8FF, 0xFFB020, 0x3DDC97, 0xFF6FA8, 0xB08CFF, 0xFF8A3D]
        return Color(hex: palette[abs(id) % palette.count])
    }

    static let radiusSmall: CGFloat = 4
    static let radius: CGFloat = 6
    static let radiusLarge: CGFloat = 10

    static func potentialColor(_ potential: Int) -> Color {
        switch PotentialBand(potential) {
        case .high: return success
        case .good: return info
        case .fair: return warning
        case .low: return textTertiary
        }
    }

    static func clipColor(for clip: TimelineClip, track: Track) -> Color {
        switch clip.content {
        case .text: return textClip
        case .solid: return Color(hex: 0x555A66)
        case .compound: return compoundClip
        case .media:
            switch clip.role {
            case .webcam: return webcamClip
            case .music: return musicClip
            case .soundEffect: return sfxClip
            default: return track.kind == .audio ? audioClip : videoClip
            }
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }

    init(_ c: RGBAColor) {
        self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }

    var rgba: RGBAColor {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return RGBAColor(red: Double(ns.redComponent), green: Double(ns.greenComponent), blue: Double(ns.blueComponent), alpha: Double(ns.alphaComponent))
    }
}

extension Font {
    static let pulseTitle = Font.system(size: 22, weight: .semibold)
    static let pulseHeadline = Font.system(size: 13, weight: .semibold)
    static let pulseBody = Font.system(size: 12)
    static let pulseCaption = Font.system(size: 11)
    static let pulseMicro = Font.system(size: 10, weight: .medium)
    static let pulseMono = Font.system(size: 11, design: .monospaced).monospacedDigit()
    static let pulseTimecode = Font.system(size: 15, weight: .medium, design: .monospaced).monospacedDigit()
}

/// Section label style used in panels ("TRANSFORM", "CROP").
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.textTertiary)
    }
}
