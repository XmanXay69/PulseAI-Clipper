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

        var body: some View {
            configuration.label
                .font(.system(size: compact ? 11 : 12, weight: .medium))
                .padding(.horizontal, compact ? 8 : 12)
                .padding(.vertical, compact ? 4 : 6)
                .foregroundStyle(foreground)
                .background(RoundedRectangle(cornerRadius: Theme.radius).fill(background))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(border, lineWidth: 1))
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
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
            .background(RoundedRectangle(cornerRadius: Theme.radiusLarge).fill(Theme.panelRaised))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).strokeBorder(Theme.border))
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
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.textTertiary)
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
            Text(text).font(.pulseMicro)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(color)
        .background(Capsule().fill(color.opacity(0.14)))
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

struct InspectorSection<Content: View>: View {
    let title: String
    var isAI = false
    @State var expanded = true
    var trailing: AnyView?
    @ViewBuilder var content: () -> Content

    init(_ title: String, isAI: Bool = false, expanded: Bool = true, trailing: AnyView? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.isAI = isAI
        self._expanded = State(initialValue: expanded)
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
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
            if expanded {
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

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.pulseCaption).foregroundStyle(Theme.textSecondary).frame(width: 74, alignment: .leading)
            Slider(value: $value, in: range, onEditingChanged: onEditingChanged)
                .controlSize(.mini)
                .tint(Theme.accent)
            Text(String(format: format, value) + unit)
                .font(.pulseMono)
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 48, alignment: .trailing)
            if let onKeyframe {
                Button(action: onKeyframe) {
                    Image(systemName: keyframed ? "diamond.fill" : "diamond")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(keyframed ? Theme.warning : Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help(keyframed ? "Keyframe at playhead — click to remove" : "Add keyframe at playhead")
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
