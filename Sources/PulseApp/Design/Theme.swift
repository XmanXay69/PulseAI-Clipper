import AppKit
import PulseCore
import SwiftUI

/// PULSE design tokens. Deep charcoal surfaces, hairline borders, one accent, flat controls — the restraint of a
/// professional grading and editing suite. Every view reads these at draw time, so a theme change repaints on the
/// next pass. Gradients, glows and lifted shadows are deliberately absent from filled controls and cards.
enum Theme {
    /// Light theme on (#424). Set from Settings → General → Appearance (or macOS when matching it).
    nonisolated(unsafe) static var isLight = false

    // Surfaces, darkest → lightest. Never pure black: the viewer well is the darkest, then the window, then panels.
    static var window: Color { isLight ? Color(hex: 0xE9E9EC) : Color(hex: 0x121214) }
    static var panel: Color { isLight ? Color(hex: 0xF3F3F5) : Color(hex: 0x19191C) }
    static var panelRaised: Color { isLight ? Color(hex: 0xFAFAFB) : Color(hex: 0x1F1F23) }
    static var control: Color { isLight ? Color(hex: 0xE2E2E6) : Color(hex: 0x2A2A2F) }
    static var controlHover: Color { isLight ? Color(hex: 0xD8D8DE) : Color(hex: 0x34343A) }
    static var well: Color { isLight ? Color(hex: 0xDDDDE2) : Color(hex: 0x0C0C0E) }
    /// Floating surfaces (popovers, menus, toasts).
    static var elevated: Color { isLight ? Color(hex: 0xFFFFFF) : Color(hex: 0x242428) }

    static var border: Color { isLight ? Color.black.opacity(0.10) : Color.white.opacity(0.08) }
    static var borderStrong: Color { isLight ? Color.black.opacity(0.20) : Color.white.opacity(0.15) }
    static var divider: Color { isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.06) }

    // Text.
    static var textPrimary: Color { isLight ? Color.black.opacity(0.88) : Color.white.opacity(0.92) }
    static var textSecondary: Color { isLight ? Color.black.opacity(0.58) : Color.white.opacity(0.60) }
    static var textTertiary: Color { isLight ? Color.black.opacity(0.40) : Color.white.opacity(0.38) }

    // Accents. The accent follows Settings → General → Appearance (#425); the AI violet marks what the AI made.
    nonisolated(unsafe) static var accentChoice: AccentChoice = .pulse
    static var accent: Color { Color(hex: accentChoice.hex) }
    static var accentSoft: Color { Color(hex: accentChoice.hex).opacity(0.16) }
    static let ai = Color(hex: 0x8C7BE0)
    static let aiSoft = Color(hex: 0x8C7BE0).opacity(0.16)
    static let success = Color(hex: 0x4CC38A)
    static let warning = Color(hex: 0xE8A33D)
    static let danger = Color(hex: 0xE5484D)
    static let info = Color(hex: 0x4FA8D8)

    // Track colours: muted, so a dense timeline stays calm.
    static let videoClip = Color(hex: 0x4F7FD0)
    static let webcamClip = Color(hex: 0x2E9C8A)
    static let audioClip = Color(hex: 0x3F9E6C)
    static let musicClip = Color(hex: 0xC48A3C)
    static let sfxClip = Color(hex: 0xB25C8E)
    static let textClip = Color(hex: 0x8E74D8)
    static let compoundClip = Color(hex: 0xB7843F)

    /// Stable, distinct colour per speaker.
    static func speakerColor(_ id: Int) -> Color {
        let palette: [UInt32] = [0x4FA8D8, 0xE8A33D, 0x4CC38A, 0xE27BA6, 0xA48CF0, 0xEC8A4D]
        return Color(hex: palette[abs(id) % palette.count])
    }

    // Corner radii: desktop software, not cards. Panels and tiles stay close to square.
    static let radiusSmall: CGFloat = 3
    static let radius: CGFloat = 4
    static let radiusLarge: CGFloat = 6
    static let radiusXL: CGFloat = 8

    /// The 4-pt spacing grid (#401): every padding and gap is one of these.
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    // Kept for call sites that fill with a "gradient": both are flat now, so a filled control is one colour.
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: accentChoice.hex), Color(hex: accentChoice.hex)], startPoint: .top, endPoint: .bottom)
    }
    static let aiGradient = LinearGradient(colors: [Color(hex: 0x8C7BE0), Color(hex: 0x8C7BE0)], startPoint: .top, endPoint: .bottom)
    /// No light catch on raised surfaces any more; overlays that draw it draw nothing.
    static var edgeHighlight: LinearGradient {
        LinearGradient(colors: [Color.clear, Color.clear], startPoint: .top, endPoint: .bottom)
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
        case .solid: return Color(hex: 0x5A5F6B)
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
    /// Depth only where something floats: 1 = nothing (cards sit flat in their panel), 2 = popovers and dragged
    /// items, 3 = sheets.
    func elevation(_ level: Int) -> some View {
        let radius: CGFloat = level <= 1 ? 0 : (level == 2 ? 12 : 24)
        let y: CGFloat = level <= 1 ? 0 : (level == 2 ? 4 : 10)
        return shadow(color: .black.opacity(level <= 1 ? 0 : (level == 2 ? 0.28 : 0.4)), radius: radius, y: y)
    }

    /// A surface a tone lighter than its panel with a hairline border — tiles, cards, popovers.
    func raisedSurface(cornerRadius: CGFloat = Theme.radiusLarge, fill: Color = Theme.panelRaised, border: Color = Theme.border) -> some View {
        background(RoundedRectangle(cornerRadius: cornerRadius).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(border))
    }
}

extension Font {
    /// The type scale (#401): 10 micro · 11 caption · 12 body · 12.5 headline · 14 subtitle · 18 title · 24 display.
    static let pulseDisplay = Font.system(size: 24, weight: .semibold)
    static let pulseTitle = Font.system(size: 18, weight: .semibold)
    static let pulseSubtitle = Font.system(size: 14, weight: .semibold)
    static let pulseHeadline = Font.system(size: 12.5, weight: .semibold)
    static let pulseBody = Font.system(size: 12)
    static let pulseCaption = Font.system(size: 11)
    static let pulseMicro = Font.system(size: 10, weight: .medium)
    static let pulseMono = Font.system(size: 11, design: .monospaced).monospacedDigit()
    static let pulseTimecode = Font.system(size: 14, weight: .medium, design: .monospaced).monospacedDigit()
}

/// Section label style used in panels ("TRANSFORM", "CROP").
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(Theme.textTertiary)
    }
}
