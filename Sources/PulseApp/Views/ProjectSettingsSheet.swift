import PulseCore
import SwiftUI

/// File → Project Settings… (#445): the few settings a project pins instead of following the app-wide ones.
struct ProjectSettingsSheet: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    @Environment(\.dismiss) private var dismiss

    var overrides: Binding<ProjectOverrides> {
        Binding(get: { session.document.overrides },
                set: { value in session.edit("Project Settings") { $0.overrides = value } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeader("Project Settings", symbol: "slider.horizontal.below.square.filled.and.square", tint: Theme.accent,
                        subtitle: "Each row follows Settings unless you pin a value here for “\(session.document.name)”.", padded: false)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Export preset").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    Picker("", selection: Binding(get: { overrides.wrappedValue.exportPresetID ?? "" }, set: { overrides.wrappedValue.exportPresetID = $0.isEmpty ? nil : $0 })) {
                        Text("Follow Settings (\(ExportPreset.preset(id: app.settings.defaultExportPresetID)?.name ?? "TikTok"))").tag("")
                        ForEach(ExportPreset.builtIn) { preset in Text(preset.name).tag(preset.id) }
                    }
                    .labelsHidden().frame(width: 260)
                }
                GridRow {
                    Text("Target platform").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    Picker("", selection: Binding(get: { overrides.wrappedValue.safeAreaPlatform }, set: { overrides.wrappedValue.safeAreaPlatform = $0 })) {
                        Text("Follow Settings (\(app.settings.safeAreaPlatform.displayName))").tag(SafeAreaPlatform?.none)
                        ForEach(SafeAreaPlatform.allCases, id: \.self) { Text($0.displayName).tag(SafeAreaPlatform?.some($0)) }
                    }
                    .labelsHidden().frame(width: 260)
                }
                GridRow {
                    Text("Loudness target").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    Picker("", selection: Binding(get: { overrides.wrappedValue.loudnessTarget ?? 0 }, set: { overrides.wrappedValue.loudnessTarget = $0 == 0 ? nil : $0 })) {
                        Text("Follow the export sheet").tag(0.0)
                        Text("−14 LUFS (YouTube)").tag(-14.0)
                        Text("−16 LUFS (podcast)").tag(-16.0)
                        Text("−18 LUFS (quiet)").tag(-18.0)
                    }
                    .labelsHidden().frame(width: 260)
                }
                GridRow {
                    Text("Caption look").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    Picker("", selection: Binding(get: { overrides.wrappedValue.captionPresetName ?? "" }, set: { overrides.wrappedValue.captionPresetName = $0.isEmpty ? nil : $0 })) {
                        Text("Follow Settings (\(app.settings.ai.captionPresetName.isEmpty ? "TikTok" : app.settings.ai.captionPresetName))").tag("")
                        ForEach(CaptionStyle.presets, id: \.presetName) { Text($0.presetName).tag($0.presetName) }
                    }
                    .labelsHidden().frame(width: 260)
                }
            }
            Text(session.document.overrides.isEmpty ? "Nothing pinned — this project follows Settings everywhere."
                 : "\(session.document.overrides.count) setting\(session.document.overrides.count == 1 ? "" : "s") pinned for this project.")
                .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            HStack {
                Button("Clear All") { overrides.wrappedValue = ProjectOverrides() }
                    .buttonStyle(.pulse(.ghost, compact: true))
                    .disabled(session.document.overrides.isEmpty)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.pulse(.primary, compact: true)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 520)
        .background(Theme.panel)
    }
}
