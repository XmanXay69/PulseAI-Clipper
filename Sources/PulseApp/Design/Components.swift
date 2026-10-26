import PulseCore
import PulseEngine
import SwiftUI

// MARK: Buttons

struct PulseButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost, ai, destructive }
    var kind: Kind = .secondary
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, kind: kind, compact: compact)
    }

    private struct StyledButton: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        let compact: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var filled: Bool { kind == .primary || kind == .ai || kind == .destructive }

        var body: some View {
            configuration.label
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                .padding(.horizontal, compact ? 9 : 13)
                .padding(.vertical, compact ? 4 : 6)
                .foregroundStyle(foreground)
                .background(fillShape)
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(border, lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(filled ? 0.22 : 0.07), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .shadow(color: glow, radius: hovering ? 10 : 6, y: 3)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }

        @ViewBuilder var fillShape: some View {
            switch kind {
            case .primary: RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.accentGradient).opacity(hovering ? 1 : 0.92)
            case .ai: RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.aiGradient).opacity(hovering ? 1 : 0.92)
            default: RoundedRectangle(cornerRadius: Theme.radius).fill(background)
            }
        }

        var glow: Color {
            switch kind {
            case .primary: return Theme.accent.opacity(hovering ? 0.38 : 0.22)
            case .ai: return Theme.ai.opacity(hovering ? 0.38 : 0.22)
            default: return .clear
            }
        }

        var foreground: Color {
            switch kind {
            case .primary, .ai, .destructive: return .white
            case .secondary: return Theme.textPrimary
            case .ghost: return hovering ? Theme.textPrimary : Theme.textSecondary
            }
        }

        var background: Color {
            switch kind {
            case .primary: return hovering ? Theme.accent.opacity(0.9) : Theme.accent
            case .ai: return hovering ? Theme.ai.opacity(0.9) : Theme.ai
            case .destructive: return hovering ? Theme.danger.opacity(0.9) : Theme.danger.opacity(0.85)
            case .secondary: return hovering ? Theme.controlHover : Theme.control
            case .ghost: return hovering ? Theme.control : .clear
            }
        }

        var border: Color {
            switch kind {
            case .secondary: return Theme.border
            default: return .clear
            }
        }
    }
}

extension ButtonStyle where Self == PulseButtonStyle {
    static var pulsePrimary: PulseButtonStyle { PulseButtonStyle(kind: .primary) }
    static var pulseSecondary: PulseButtonStyle { PulseButtonStyle(kind: .secondary) }
    static var pulseGhost: PulseButtonStyle { PulseButtonStyle(kind: .ghost) }
    static var pulseAI: PulseButtonStyle { PulseButtonStyle(kind: .ai) }
    static var pulseDestructive: PulseButtonStyle { PulseButtonStyle(kind: .destructive) }
    static func pulse(_ kind: PulseButtonStyle.Kind, compact: Bool = false) -> PulseButtonStyle { PulseButtonStyle(kind: kind, compact: compact) }
}

/// Square icon button used in toolbars and panels.
struct IconButton: View {
    let symbol: String
    var help: String
    var isActive = false
    var size: CGFloat = 26
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .medium))
                .frame(width: size, height: size)
                .foregroundStyle(isActive ? Theme.accent : (hovering ? Theme.textPrimary : Theme.textSecondary))
                .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(isActive ? Theme.accentSoft : (hovering ? Theme.control : .clear)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(accessibilityName)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    /// The help text up to its first separator or bracket — "Split at playhead", not the shortcut (#458).
    var accessibilityName: String {
        let cut = help.firstIndex { $0 == "(" || $0 == "—" || $0 == "·" } ?? help.endIndex
        return help[..<cut].trimmingCharacters(in: .whitespaces)
    }
}

// MARK: Panels

struct PanelHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
                if let subtitle { Text(subtitle).font(.pulseCaption).foregroundStyle(Theme.textTertiary) }
            }
            Spacer(minLength: 4)
            trailing()
        }
        .padding(.horizontal, 12)
        .frame(height: subtitle == nil ? 34 : 42)
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .raisedSurface()
            .elevation(1)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Theme.control))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [Theme.accent.opacity(0.6), Theme.ai.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text(message).font(.pulseBody).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.pulsePrimary).padding(.top, 4)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Badges & chips

struct TagChip: View {
    let text: String
    var color: Color = Theme.textSecondary
    var symbol: String?

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: 8, weight: .bold)) }
            Text(text).font(.pulseMicro).lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(color)
        .background(Capsule().fill(color.opacity(0.14)))
        .overlay(Capsule().strokeBorder(color.opacity(0.22)))
        .fixedSize()
    }
}

/// "AI-generated" marker shown on anything the AI created.
struct AIBadge: View {
    var label = "AI"
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "sparkles").font(.system(size: 8, weight: .bold))
            Text(label).font(.system(size: 9, weight: .bold))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .foregroundStyle(Theme.ai)
        .background(Capsule().fill(Theme.aiSoft))
        .help("Created by PULSE AI — fully editable")
    }
}

/// LOCAL / CLOUD privacy badge.
struct ProcessingBadge: View {
    let location: ProcessingLocation
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: location == .local ? "lock.laptopcomputer" : "icloud").font(.system(size: 9, weight: .semibold))
            Text(location.displayName).font(.system(size: 9, weight: .bold)).tracking(0.5)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(location == .local ? Theme.success : Theme.warning)
        .background(Capsule().fill((location == .local ? Theme.success : Theme.warning).opacity(0.13)))
        .help(location == .local ? "Processed on this Mac. Nothing was uploaded." : "Processed by a cloud AI provider you enabled.")
    }
}

/// Compact "AI Potential" meter.
struct PotentialMeter: View {
    let potential: Int
    var showsLabel = true

    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.control)
                    Capsule().fill(Theme.potentialColor(potential)).frame(width: geo.size.width * CGFloat(potential) / 100)
                }
            }
            .frame(width: 44, height: 4)
            if showsLabel {
                Text("\(potential)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .fixedSize()
                    .foregroundStyle(Theme.potentialColor(potential))
            }
        }
        .help("AI Potential \(potential)/100 — an estimate, not a verdict. You decide what's good.")
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String
    var body: some View {
        HStack {
            Text(key).foregroundStyle(Theme.textTertiary)
            Spacer()
            Text(value).foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.middle)
        }
        .font(.pulseCaption)
    }
}

// MARK: Inspector controls

/// What's typed into the inspector's search field (#224); sections that don't match hide.
private struct InspectorQueryKey: EnvironmentKey {
    static let defaultValue = ""
}

extension EnvironmentValues {
    var inspectorQuery: String {
        get { self[InspectorQueryKey.self] }
        set { self[InspectorQueryKey.self] = newValue }
    }
}

/// Words that land on a section besides its title (#224).
enum InspectorKeywords {
    static let bySection: [String: String] = [
        "Transform": "position scale rotation opacity flip x y", "Crop & Zoom": "crop zoom pan reframe", "Shape & Border": "mask round circle border shadow",
        "Speed": "speed slow fast freeze reverse", "Transitions": "dissolve fade cut transition", "AI Framing": "framing reframe face follow",
        "Text": "font size weight color outline shadow background", "Look": "mask border shadow rounded circle", "Animation": "keyframe animate pop slide in out",
        "Volume": "gain mute fade pan loud quiet channels mono", "Auto Ducking": "duck music under dialogue attack release",
        "Enhance": "noise voice isolate eq compressor limiter de-esser deess hum normalize loudness", "Color": "exposure contrast saturation temperature tint grade lut bypass look",
        "Effects": "blur sharpen glow vignette grain shake", "Canvas": "resolution frame rate background blur fill", "Layout": "split facecam corner full",
        "Captions": "captions subtitles style", "Markers": "chapter marker todo", "Removed Sections": "restore cut silence filler", "Clip": "name enabled role",
    ]

    static func matches(_ title: String, _ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let haystack = (title + " " + (bySection[title] ?? "")).lowercased()
        return query.split(separator: " ").allSatisfy { haystack.contains($0) }
    }
}

struct InspectorSection<Content: View>: View {
    @Environment(\.inspectorQuery) private var query
    let title: String
    var isAI = false
    /// Remembered per section title, so a section you collapsed stays collapsed across clips and launches.
    @AppStorage var expanded: Bool
    var trailing: AnyView?
    @ViewBuilder var content: () -> Content

    init(_ title: String, isAI: Bool = false, expanded: Bool = true, trailing: AnyView? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.isAI = isAI
        self._expanded = AppStorage(wrappedValue: expanded, "inspector.expanded." + title)
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        if InspectorKeywords.matches(title, query) { section } else { EmptyView() }
    }

    /// Open when searched for, so the matching controls show straight away.
    var isOpen: Bool { expanded || !query.isEmpty }

    var section: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .foregroundStyle(Theme.textTertiary)
                    SectionLabel(text: title)
                    if isAI { AIBadge() }
                    Spacer()
                    if let trailing { trailing }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            if isOpen {
                VStack(alignment: .leading, spacing: 8) { content() }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
            Rectangle().fill(Theme.divider).frame(height: 1)
        }
    }
}

/// Label + slider + numeric field, with optional keyframe toggle.
struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var format: String = "%.2f"
    var unit: String = ""
    var keyframed: Bool = false
    var onKeyframe: (() -> Void)?
    var onEditingChanged: (Bool) -> Void = { _ in }
    /// When set, a reset arrow appears while the value differs (double-clicking the label resets too).
    var defaultValue: Double? = nil
    var onReset: (() -> Void)? = nil
    /// Between keyframes (the value is animated but there's no keyframe at the playhead).
    var animated: Bool = false
    var onPreviousKeyframe: (() -> Void)? = nil
    var onNextKeyframe: (() -> Void)? = nil
    @State private var editing = false
    @State private var draft = ""

    /// Typed value → clamped to the range (#207).
    func commitDraft() {
        editing = false
        let cleaned = draft.filter { "0123456789.-".contains($0) }
        guard let typed = Double(cleaned) else { return }
        value = min(max(typed, range.lowerBound), range.upperBound)
        onEditingChanged(false)
    }

    var isOffDefault: Bool { defaultValue.map { abs(value - $0) > 1e-6 } ?? false }

    func reset() {
        if let onReset { onReset() } else if let defaultValue { value = defaultValue }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.pulseCaption).foregroundStyle(isOffDefault ? Theme.textPrimary : Theme.textSecondary).frame(width: 74, alignment: .leading)
                .onTapGesture(count: 2) { if isOffDefault { reset() } }
                .help(defaultValue != nil ? "Double-click to reset" : "")
            Slider(value: $value, in: range, onEditingChanged: onEditingChanged)
                .controlSize(.mini)
                .tint(Theme.accent)
            if editing {
                TextField("", text: $draft, onCommit: commitDraft)
                    .textFieldStyle(.plain)
                    .font(.pulseMono)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                    .onExitCommand { editing = false }
            } else {
                Text(String(format: format, value) + unit)
                    .font(.pulseMono)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 48, alignment: .trailing)
                    .contentShape(Rectangle())
                    .onTapGesture { draft = String(format: format, value); editing = true }
                    .help("Click to type a value")
            }
            if animated, let onPreviousKeyframe {
                Button(action: onPreviousKeyframe) { Image(systemName: "chevron.left").font(.system(size: 8, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.textTertiary).help("Previous keyframe")
            }
            if defaultValue != nil {
                Button(action: reset) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isOffDefault ? Theme.textSecondary : Theme.textTertiary.opacity(0.35))
                }
                .buttonStyle(.plain)
                .disabled(!isOffDefault)
                .help(isOffDefault ? "Reset to \(String(format: format, defaultValue ?? 0))\(unit)" : "At the default")
            }
            if let onKeyframe {
                Button(action: onKeyframe) {
                    Image(systemName: keyframed ? "diamond.fill" : (animated ? "diamond.lefthalf.filled" : "diamond"))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(keyframed ? Theme.warning : (animated ? Theme.textSecondary : Theme.textTertiary))
                }
                .buttonStyle(.plain)
                .help(keyframed ? "Keyframe at playhead — click to remove" : (animated ? "Between keyframes — click to add one here" : "Add keyframe at playhead"))
            }
            if animated, let onNextKeyframe {
                Button(action: onNextKeyframe) { Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.textTertiary).help("Next keyframe")
            }
        }
    }
}

struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    var help: String? = nil

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(label).font(.pulseCaption).foregroundStyle(Theme.textSecondary)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .tint(Theme.accent)
        .help(help ?? label)
    }
}

struct ColorRow: View {
    let label: String
    @Binding var color: RGBAColor

    var body: some View {
        HStack {
            Text(label).font(.pulseCaption).foregroundStyle(Theme.textSecondary)
            Spacer()
            ColorPicker("", selection: Binding(get: { Color(color) }, set: { color = $0.rgba }), supportsOpacity: true)
                .labelsHidden()
        }
    }
}

// MARK: Progress

struct ProgressRing: View {
    let progress: Double
    var size: CGFloat = 16
    var color: Color = Theme.accent

    var body: some View {
        ZStack {
            Circle().stroke(Theme.control, lineWidth: 2.5)
            Circle().trim(from: 0, to: CGFloat(max(0.02, min(progress, 1))))
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.2), value: progress)
    }
}

struct ThinProgressBar: View {
    let progress: Double
    var color: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.control)
                Capsule().fill(color).frame(width: geo.size.width * CGFloat(max(0, min(progress, 1))))
            }
        }
        .frame(height: 4)
    }
}

// MARK: Media thumbnails

struct ThumbnailView: View {
    let url: URL?
    var time: Seconds = 1
    var maxWidth: Int = 320
    var contentMode: ContentMode = .fill
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Theme.well)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Image(systemName: "film").foregroundStyle(Theme.textTertiary)
            }
        }
        .clipped()
        .task(id: "\(url?.path ?? "")|\(Int(time * 10))|\(maxWidth)") {
            guard let url else { image = nil; return }
            image = await ThumbnailService.shared.image(for: url, at: time, maxWidth: maxWidth)
        }
    }
}

extension View {
    /// Standard panel background with a hairline border.
    func panelStyle() -> some View {
        background(Theme.panel)
    }

    @ViewBuilder
    func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}

/// Re-renders only its content when the playhead clock ticks — the surrounding view stays put.
/// Use it around the parts that show live time (timecode, playhead, handles, word highlights).
struct ClockObserving<Content: View>: View {
    @ObservedObject var clock: PlayheadClock
    @ViewBuilder let content: () -> Content

    var body: some View { content() }
}
