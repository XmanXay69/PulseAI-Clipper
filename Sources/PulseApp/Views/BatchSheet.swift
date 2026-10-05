import PulseCore
import PulseEngine
import SwiftUI
import UniformTypeIdentifiers

/// Overnight batch: drop in several VODs, choose what to make, start — and go to bed.
struct BatchSheet: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var batch: BatchController
    @Environment(\.dismiss) private var dismiss
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "moon.stars.fill").font(.system(size: 20)).foregroundStyle(Theme.ai)
                    .frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: 10).fill(Theme.aiSoft))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Overnight Batch").font(.pulseTitle).foregroundStyle(Theme.textPrimary)
                    Text("Queue your VODs and let PULSE work through them — your Mac stays awake until it's done.")
                        .font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(20)
            Divider().overlay(Theme.divider)
            HStack(alignment: .top, spacing: 0) {
                queue.frame(maxWidth: .infinity)
                Divider().overlay(Theme.divider)
                optionsPanel.frame(width: 250)
            }
            Divider().overlay(Theme.divider)
            footer
        }
        .frame(width: 780, height: 560)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
    }

    var queue: some View {
        VStack(spacing: 0) {
            if batch.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 30)).foregroundStyle(Theme.textTertiary)
                    Text("Drop VODs here").font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
                    Button("Add Videos…") { pick() }.buttonStyle(.pulseSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(batch.items) { item in row(item) }
                    }
                    .padding(12)
                }
                HStack {
                    Button { pick() } label: { Label("Add Videos…", systemImage: "plus") }.buttonStyle(.pulse(.ghost, compact: true))
                    Spacer()
                    if batch.items.contains(where: { $0.status.isFinished }) {
                        Button("Clear Finished") { batch.clearFinished() }.buttonStyle(.pulse(.ghost, compact: true))
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 8)
            }
        }
        .background(dropTargeted ? Theme.accent.opacity(0.06) : .clear)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            loadURLs(from: providers) { urls in batch.add(urls) }
            return true
        }
    }

    func row(_ item: BatchController.Item) -> some View {
        HStack(spacing: 10) {
            statusIcon(item.status).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent).font(.pulseBody).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(statusText(item)).font(.pulseMicro).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            Spacer()
            if let path = item.projectPath, item.status.isFinished {
                Button("Open") { app.openProject(at: URL(fileURLWithPath: path)); dismiss() }.buttonStyle(.pulse(.secondary, compact: true))
            }
            if item.status == .queued {
                IconButton(symbol: "xmark", help: "Remove", size: 20) { batch.remove(item.id) }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.panelRaised))
    }

    @ViewBuilder
    func statusIcon(_ status: BatchController.Status) -> some View {
        switch status {
        case .queued: Image(systemName: "clock").foregroundStyle(Theme.textTertiary)
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
        case .cancelled: Image(systemName: "stop.circle").foregroundStyle(Theme.textTertiary)
        }
    }

    func statusText(_ item: BatchController.Item) -> String {
        let length = item.duration.map { Timecode.short($0) } ?? "…"
        switch item.status {
        case .queued: return "Queued · \(length)"
        case .running(let step): return step
        case .done(let summary): return summary
        case .failed(let message): return message
        case .cancelled: return "Cancelled"
        }
    }

    var optionsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "For each video")
            Stepper(value: $batch.options.shortsPerVOD, in: 0...10) {
                Text("\(batch.options.shortsPerVOD) best shorts").font(.pulseBody)
            }
            Toggle(isOn: $batch.options.makeYouTubeEdit) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("YouTube edit").font(.pulseBody)
                    Text("Edit My VOD, for videos 10 min or longer").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                }
            }
            .toggleStyle(.switch).controlSize(.small).tint(Theme.ai)
            if batch.options.makeYouTubeEdit, !app.settings.referenceStyles.isEmpty {
                Picker("Style", selection: $batch.options.styleID) {
                    Text("PULSE's own").tag(UUID?.none)
                    ForEach(app.settings.referenceStyles) { Text("Like “\($0.name)”").tag(UUID?.some($0.id)) }
                }
                .font(.pulseCaption)
                .help("Edit each YouTube video like a reference you studied (Edit Like a Reference)")
            }
            if batch.options.makeYouTubeEdit {
                let e = app.settings.ai.editExtras
                let on = [("facecam punch-ins", e.facecamPunchIns), ("B-roll", e.brollClips), ("beat sync", e.beatSync),
                          ("speaker-aware cuts", e.speakerAware), ("title cards", e.titleCards)].filter { $0.1 }.map { $0.0 }
                Text("Extras: \(on.isEmpty ? "none" : on.joined(separator: ", ")) — your last answers in Edit My VOD (nobody's there to ask overnight).")
                    .font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
            Toggle(isOn: $batch.options.makeThumbnails) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Thumbnail designs").font(.pulseBody)
                    Text("Best reaction frames, waiting in Thumbnail Studio").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                }
            }
            .toggleStyle(.switch).controlSize(.small).tint(Theme.ai)
            Toggle(isOn: $batch.options.exportEverything) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Export everything").font(.pulseBody)
                    Text("Into a folder per video in your exports folder").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                }
            }
            .toggleStyle(.switch).controlSize(.small).tint(Theme.ai)
            if batch.options.exportEverything {
                Picker("Shorts as", selection: $batch.options.exportPresetID) {
                    ForEach([ExportPreset.tiktok, .shorts, .reels], id: \.id) { Text($0.name).tag($0.id) }
                }
                .font(.pulseCaption)
            }
            Spacer()
            Label("Your brand kit is applied when it's switched on.", systemImage: "paintbrush.pointed")
                .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
        }
        .padding(16)
        .disabled(batch.isRunning)
    }

    var footer: some View {
        HStack {
            if let total = batch.estimatedTotal, !batch.isRunning {
                Label("About \(DurationText.approximate(total).replacingOccurrences(of: "about ", with: "")) for \(batch.items.filter { $0.status == .queued }.count) videos",
                      systemImage: "clock").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
            } else if batch.isRunning {
                Label("Working — keep PULSE open. Your Mac won't sleep until it's done.", systemImage: "moon.zzz")
                    .font(.pulseCaption).foregroundStyle(Theme.ai)
            }
            Spacer()
            Button("Close") { dismiss() }.buttonStyle(.pulseSecondary).keyboardShortcut(.cancelAction)
            if batch.isRunning {
                Button("Stop") { batch.cancel() }.buttonStyle(.pulse(.destructive))
            } else {
                Button { batch.start() } label: { Label("Start Batch", systemImage: "play.fill") }
                    .buttonStyle(.pulseAI)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!batch.items.contains { $0.status == .queued })
            }
        }
        .padding(16)
    }

    func pick() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        if panel.runModal() == .OK { batch.add(panel.urls) }
    }
}
