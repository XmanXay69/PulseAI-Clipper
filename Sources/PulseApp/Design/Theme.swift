import AppKit
import PulseCore
import SwiftUI

/// PULSE design tokens, in the same language as BulkBoard: neutral graphite surfaces, one accent, two status
/// colours used sparingly, soft continuous corners and hairline strokes. Every view reads these at draw time,
/// so a theme change repaints on the next pass.
enum Theme {
    /// Light theme on (#424). Set from Settings → General → Appearance (or macOS when matching it).
    nonisolated(unsafe) static var isLight = false

    // Surfaces: the page, the sidebar and chrome, cards, and the raised tone for controls and rows.
    static var window: Color { isLight ? Color(hex: 0xF5F5F7) : Color(hex: 0x161618) }
    static var panel: Color { isLight ? Color(hex: 0xECECEF) : Color(hex: 0x1A1A1D) }
    static var panelRaised: Color { isLight ? Color(hex: 0xFFFFFF) : Color(hex: 0x1F1F22) }
    static var control: Color { isLight ? Color(hex: 0xE4E4E9) : Color(hex: 0x2A2A2E) }
    static var controlHover: Color { isLight ? Color(hex: 0xD8D8DF) : Color(hex: 0x35353A) }
    /// The selected segment of a segmented control, and other "this one" fills on a control-coloured track.
    static var controlSelected: Color { isLight ? Color(hex: 0xFFFFFF) : Color(hex: 0x4A4A50) }
    /// Behind pictures: the viewer, thumbnails, the timeline's lanes.
    static var well: Color { isLight ? Color(hex: 0xDFDFE4) : Color(hex: 0x0F0F11) }
    /// Floating surfaces (popovers, menus, toasts).
    static var elevated: Color { isLight ? Color(hex: 0xFFFFFF) : Color(hex: 0x26262A) }

    static var border: Color { isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.08) }
    static var borderStrong: Color { isLight ? Color.black.opacity(0.16) : Color.white.opacity(0.14) }
    static var divider: Color { isLight ? Color.black.opacity(0.07) : Color.white.opacity(0.07) }

    // Text.
    static var textPrimary: Color { isLight ? Color(hex: 0x1D1D1F) : Color(hex: 0xF2F2F4) }
    static var textSecondary: Color { isLight ? Color(hex: 0x6E6E73) : Color(hex: 0x9A9AA0) }
    static var textTertiary: Color { isLight ? Color(hex: 0x9C9CA3) : Color(hex: 0x6F6F76) }

    // One accent (#425). The default is BulkBoard's blue, a deeper shade of it on the light theme; anything the
    // AI made is marked with the same accent and a sparkle rather than a colour of its own.
    nonisolated(unsafe) static var accentChoice: AccentChoice = .pulse
    static var accentHex: UInt32 {
        accentChoice == .pulse ? (isLight ? 0x2563EB : 0x4C8DFF) : accentChoice.hex
    }
    static var accent: Color { Color(hex: accentHex) }
    static var accentSoft: Color { Color(hex: accentHex).opacity(isLight ? 0.10 : 0.16) }
    static var ai: Color { accent }
    static var aiSoft: Color { accentSoft }

    // Status colours, used sparingly: done / over or failed, plus an amber for "look at this".
    static var success: Color { isLight ? Color(hex: 0x15803D) : Color(hex: 0x32D74B) }
    static var danger: Color { isLight ? Color(hex: 0xDC2626) : Color(hex: 0xFF6961) }
    static var warning: Color { isLight ? Color(hex: 0xB45309) : Color(hex: 0xFFB340) }
    /// "For your information" is the accent: a second blue beside it would read as a second accent.
    static var info: Color { accent }

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

    // Corner radii, all drawn continuous: 12 for cards and sheets, 10 for tiles and banners, 7 for buttons,
    // fields and list rows, 5 for the small things inside them.
    static let radiusSmall: CGFloat = 5
    static let radius: CGFloat = 7
    static let radiusLarge: CGFloat = 10
    static let radiusXL: CGFloat = 12

    /// The 4-pt spacing grid (#401): every padding and gap is one of these. Pages are padded by `xxl`,
    /// cards by `l`, and cards sit `xl` apart.
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    // Kept for call sites that fill with a "gradient": both are flat, so a filled control is one colour.
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accent], startPoint: .top, endPoint: .bottom)
    }
    static var aiGradient: LinearGradient { accentGradient }
    /// No light catch on raised surfaces; overlays that draw it draw nothing.
    static var edgeHighlight: LinearGradient {
        LinearGradient(colors: [Color.clear, Color.clear], startPoint: .top, endPoint: .bottom)
    }

    static func potentialColor(_ potential: Int) -> Color {
        switch PotentialBand(potential) {
        case .high: return success
        case .good: return accent
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
    /// Depth only where something floats: 1 = nothing (cards sit flat on the page), 2 = popovers and dragged
    /// items, 3 = sheets.
    func elevation(_ level: Int) -> some View {
        let radius: CGFloat = level <= 1 ? 0 : (level == 2 ? 10 : 24)
        let y: CGFloat = level <= 1 ? 0 : (level == 2 ? 3 : 10)
        return shadow(color: .black.opacity(level <= 1 ? 0 : (level == 2 ? 0.22 : 0.36)), radius: radius, y: y)
    }

    /// A card: the surface colour, a hairline stroke and a soft continuous corner.
    func raisedSurface(cornerRadius: CGFloat = Theme.radiusLarge, fill: Color = Theme.panelRaised, border: Color = Theme.border) -> some View {
        background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(border))
    }

    /// The standard card: 16 pt of padding on the card surface, stretched to the width it is given.
    func card(padding: CGFloat = Theme.Spacing.l) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .raisedSurface(cornerRadius: Theme.radiusXL)
    }

    /// A row or inset group inside a card: the raised tone, no stroke.
    func insetRow(cornerRadius: CGFloat = Theme.radius) -> some View {
        background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Theme.control.opacity(0.55)))
    }

    /// Standard page background.
    func pageBackground() -> some View {
        background(Theme.window)
    }
}

extension Font {
    /// The type scale (#401): 10 micro · 11 caption · 13 body · 13 headline · 15 subtitle · 20 title · 24 display.
    static let pulseDisplay = Font.system(size: 24, weight: .bold)
    static let pulseTitle = Font.system(size: 20, weight: .bold)
    static let pulseSubtitle = Font.system(size: 15, weight: .semibold)
    static let pulseHeadline = Font.system(size: 13, weight: .semibold)
    static let pulseBody = Font.system(size: 13)
    static let pulseCaption = Font.system(size: 11)
    static let pulseMicro = Font.system(size: 10, weight: .medium)
    static let pulseMono = Font.system(size: 11, design: .monospaced).monospacedDigit()
    static let pulseTimecode = Font.system(size: 14, weight: .medium, design: .monospaced).monospacedDigit()

    /// Numbers that matter: semibold with tabular digits.
    static func stat(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold).monospacedDigit()
    }
}

/// Small secondary label above a group of content ("Transform", "Clip length"), in sentence case.
struct SectionLabel: View {
    let text: String
    var color: Color = Theme.textSecondary

    init(text: String, color: Color = Theme.textSecondary) {
        self.text = text
        self.color = color
    }

    init(_ text: String, color: Color = Theme.textSecondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(color)
    }
}
