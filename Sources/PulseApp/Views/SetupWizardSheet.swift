import PulseCore
import SwiftUI

/// "Set up for my stream": a few answers about how you stream become the twenty-odd settings that depend on
/// them — clip length, captions, extras, safe areas, export preset — with a live list of what will change.
struct SetupWizardSheet: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var setup = StreamSetup()
    @State private var loaded = false

    var changes: [String] { setup.changes(to: app.settings) }

    /// The caption look PULSE would pick for these answers.
    var suggestedCaption: String {
        var copy = setup
        copy.captionPreset = ""
        return copy.effectiveCaptionPreset
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Set up for my stream").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.textPrimary)
                Text("Answer a few questions and PULSE sets clip length, captions, extras, safe areas and the export preset to match. Everything can be changed later in Settings.")
                    .font(.pulseCaption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            Divider().overlay(Theme.divider)
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        question("Where do you stream?") {
                            Picker("", selection: $setup.platform) {
                                ForEach(StreamSetup.Platform.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                            .pickerStyle(.segmented).labelsHidden()
                        }
                        question("What do you stream most?") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                                ForEach(StreamSetup.Content.allCases, id: \.self) { content in
                                    choice(content.displayName, symbol: Self.symbol(for: content), on: setup.content == content) { setup.content = content }
                                }
                            }
                        }
                        question("Is there a facecam on screen?") {
                            Picker("", selection: $setup.facecam) {
                                Text("Yes").tag(true)
                                Text("No").tag(false)
                            }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 200)
                        }
                        question("Where's your voice?") {
                            Picker("", selection: $setup.mic) {
                                ForEach(StreamSetup.Mic.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                            .pickerStyle(.segmented).labelsHidden()
                            Text(setup.micAdvice).font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                        }
                        question("Where do your shorts go?") {
                            Picker("", selection: $setup.shortsTarget) {
                                ForEach(StreamSetup.ShortsTarget.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                            .pickerStyle(.segmented).labelsHidden()
                        }
                        question("How should the edits feel?") {
                            Picker("", selection: $setup.pace) {
                                ForEach(StreamSetup.Pace.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 300)
                            Text(paceHint).font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                        }
                        question("Caption look") {
                            Picker("", selection: $setup.captionPreset) {
                                Text("Pick for me (\(suggestedCaption))").tag("")
                                Divider()
                                ForEach(CaptionStyle.presets, id: \.presetName) { Text($0.presetName).tag($0.presetName) }
                            }
                            .labelsHidden().frame(width: 260)
                        }
                    }
                    .padding(20)
                }
                .frame(maxWidth: .infinity)
                Rectangle().fill(Theme.divider).frame(width: 1)
                VStack(alignment: .leading, spacing: 10) {
                    Text("What will change").font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
                    if changes.isEmpty {
                        Text("Nothing — your settings already match these answers.").font(.pulseCaption).foregroundStyle(Theme.textTertiary)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(changes, id: \.self) { line in
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: "arrow.turn.down.right").font(.system(size: 9)).foregroundStyle(Theme.accent).padding(.top, 3)
                                        Text(line).font(.pulseCaption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(20)
                .frame(width: 300)
                .frame(maxHeight: .infinity)
                .background(Theme.panelRaised)
            }
            Divider().overlay(Theme.divider)
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield").foregroundStyle(Theme.success)
                    Text("Nothing here leaves your Mac.").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.pulse(.ghost)).keyboardShortcut(.cancelAction)
                Button(changes.isEmpty ? "Done" : "Apply \(changes.count) Setting\(changes.count == 1 ? "" : "s")") { apply() }
                    .buttonStyle(.pulse(.primary)).keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 880, height: 620)
        .background(Theme.panel)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            setup = app.settings.streamSetup ?? StreamSetup()
        }
    }

    var paceHint: String {
        switch setup.pace {
        case .calm: return "Fewer, longer moments and light dead-air trimming."
        case .normal: return "PULSE's defaults."
        case .hype: return "More clips, beat-synced cuts, and replays on fast games."
        }
    }

    func apply() {
        let applied = setup.apply(to: &app.settings)
        if !applied.isEmpty { app.toast("Set up for your stream — \(applied.count) setting\(applied.count == 1 ? "" : "s") changed") }
        dismiss()
    }

    @ViewBuilder
    func question(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
            content()
        }
    }

    func choice(_ title: String, symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(on ? Theme.accent : Theme.textSecondary).frame(width: 18)
                Text(title).font(.pulseBody).foregroundStyle(on ? Theme.textPrimary : Theme.textSecondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(on ? Theme.accentSoft : Theme.control))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(on ? Theme.accent.opacity(0.6) : Theme.border))
        }
        .buttonStyle(.plain)
    }

    static func symbol(for content: StreamSetup.Content) -> String {
        switch content {
        case .shooter: return "scope"
        case .battleRoyale: return "shield.lefthalf.filled"
        case .moba: return "map"
        case .sports: return "sportscourt"
        case .horror: return "moon.haze"
        case .variety: return "dice"
        case .justChatting: return "bubble.left.and.bubble.right"
        case .podcast: return "mic"
        case .irl: return "figure.walk"
        }
    }
}
