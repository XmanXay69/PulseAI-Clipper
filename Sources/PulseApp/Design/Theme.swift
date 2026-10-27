import AppKit
import PulseCore
import SwiftUI

/// PULSE design tokens. Dark, dense, professional — subtle borders, compact controls,
/// a single energetic accent ("pulse") plus a violet reserved for AI features.
enum Theme {
    /// Light theme on (#424). Set from Settings → General → Appearance (or macOS when matching it); views
    /// read the surface, border and text colours below at draw time, so a change repaints on the next pass.
    nonisolated(unsafe) static var isLight = false

    // Surfaces (darkest → lightest): neutral graphite, like a pro grading/editing suite; a cool paper white
    // in the light theme.
    static var window: Color { isLight ? Color(hex: 0xEDEDF0) : Color(hex: 0x151517) }
    static var panel: Color { isLight ? Color(hex: 0xF6F6F8) : Color(hex: 0x1C1C1F) }
    static var panelRaised: Color { isLight ? Color(hex: 0xFFFFFF) : Color(hex: 0x232327) }
    static var control: Color { isLight ? Color(hex: 0xE6E6EA) : Color(hex: 0x2C2C31) }
    static var controlHover: Color { isLight ? Color(hex: 0xDCDCE2) : Color(hex: 0x36363C) }
    static var well: Color { isLight ? Color(hex: 0xE2E2E6) : Color(hex: 0x101012) }

    static var border: Color { isLight ? Color.black.opacity(0.09) : Color.white.opacity(0.07) }
    static var borderStrong: Color { isLight ? Color.black.opacity(0.18) : Color.white.opacity(0.13) }
    static var divider: Color { isLight ? Color.black.opacity(0.07) : Color.white.opacity(0.05) }

    // Text.
    static var textPrimary: Color { isLight ? Color.black.opacity(0.88) : Color.white.opacity(0.92) }
    static var textSecondary: Color { isLight ? Color.black.opacity(0.6) : Color.white.opacity(0.62) }
    static var textTertiary: Color { isLight ? Color.black.opacity(0.4) : Color.white.opacity(0.38) }

    // Accents. The accent follows Settings → General → Appearance (#425); the AI violet never changes.
    nonisolated(unsafe) static var accentChoice: AccentChoice = .pulse
    static var accent: Color { Color(hex: accentChoice.hex) }
    static var accentSoft: Color { Color(hex: accentChoice.hex).opacity(0.16) }
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
    static let radiusXL: CGFloat = 16

    /// A lifted surface (popovers, hovered cards).
    static var elevated: Color { isLight ? Color(hex: 0xFFFFFF) : Color(hex: 0x27272C) }

    // Gradients: the accent and the AI violet get a little warmth/cool so filled controls read as lit.
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: accentChoice.hex), Color(hex: accentChoice.gradientEndHex)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static let aiGradient = LinearGradient(colors: [Color(hex: 0x8C6CFF), Color(hex: 0x5E9BFF)], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// The 1 px light catch along the top edge of raised surfaces.
    static var edgeHighlight: LinearGradient {
        LinearGradient(colors: [Color.white.opacity(isLight ? 0.8 : 0.09), Color.white.opacity(0)], startPoint: .top, endPoint: .center)
    }

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

extension Theme {
    /// The animation, or none when the system asks for reduced motion (#426).
    static func motion(_ animation: Animation) -> Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : animation
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

extension View {
    /// Elevation shadows: 1 = cards, 2 = popovers/hovered cards, 3 = sheets and the hero.
    func elevation(_ level: Int) -> some View {
        let radius: CGFloat = level <= 1 ? 8 : (level == 2 ? 16 : 28)
        let y: CGFloat = level <= 1 ? 3 : (level == 2 ? 6 : 12)
        return shadow(color: .black.opacity(level <= 1 ? 0.22 : (level == 2 ? 0.32 : 0.45)), radius: radius, y: y)
    }

    /// A raised, bordered surface with the top-edge light catch (cards, tiles, popovers).
    func raisedSurface(cornerRadius: CGFloat = Theme.radiusLarge, fill: Color = Theme.panelRaised, border: Color = Theme.border) -> some View {
        background(RoundedRectangle(cornerRadius: cornerRadius).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(border))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Theme.edgeHighlight, lineWidth: 1))
    }
}

extension Font {
    static let pulseDisplay = Font.system(size: 28, weight: .bold)
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
