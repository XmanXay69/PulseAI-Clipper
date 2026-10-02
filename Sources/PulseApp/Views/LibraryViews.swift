import AppKit
import PulseCore
import PulseEngine
import SwiftUI

// MARK: Media bin

struct MediaView: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    @State private var category: MediaCategory?
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var sort: Sort = .imported
    @State private var selectedID: UUID?
    @State private var newTag = ""

    enum Sort: String, CaseIterable { case imported = "Date Imported", name = "Name", duration = "Duration", size = "Size" }

    var assets: [MediaAsset] {
        var list = session.document.media
        if let category { list = list.filter { $0.category == category } }
        if favoritesOnly { list = list.filter(\.isFavorite) }
        if !query.isEmpty {
            list = list.filter { a in a.name.localizedCaseInsensitiveContains(query) || a.tags.contains { $0.localizedCaseInsensitiveContains(query) } }
        }
        switch sort {
        case .imported: list.sort { $0.importedAt > $1.importedAt }
        case .name: list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .duration: list.sort { $0.metadata.duration > $1.metadata.duration }
        case .size: list.sort { $0.metadata.fileSize > $1.metadata.fileSize }
        }
        return list
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(text: "Library").padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 6)
                binRow(nil, title: "All Media", symbol: "tray.full")
                ForEach(MediaCategory.allCases, id: \.self) { c in
                    binRow(c, title: c.displayName, symbol: symbol(for: c))
                }
                Divider().padding(.vertical, 8)
                Toggle(isOn: $favoritesOnly) { Label("Favorites", systemImage: "star") }
                    .toggleStyle(.button).buttonStyle(.plain).font(.pulseCaption).padding(.horizontal, 12)
                Spacer()
            }
            .frame(width: 180)
            .background(Theme.panel)
            Rectangle().fill(Theme.divider).frame(width: 1)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    TextField("Search names and tags", text: $query).textFieldStyle(.roundedBorder).frame(width: 240)
                    Picker("", selection: $sort) { ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .frame(width: 150)
                    Spacer()
                    Button { app.showImportPanel() } label: { Label("Import", systemImage: "plus") }.buttonStyle(.pulseSecondary)
                }
                .padding(10)
                .background(Theme.panel)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
                if assets.isEmpty {
                    EmptyStateView(symbol: "photo.stack", title: "No media", message: "Import videos, audio, music, sound effects and graphics. Drag them straight onto the timeline.",
                                   actionTitle: "Import Media") { app.showImportPanel() }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)], spacing: 12) {
                            ForEach(assets) { asset in
                                MediaTile(session: session, asset: asset, selected: selectedID == asset.id)
                                    .onTapGesture { selectedID = asset.id }
                                    .onTapGesture(count: 2) { session.placeAsset(asset.id); app.section = .editor }
                                    .draggable(asset.id.uuidString)
                            }
                        }
                        .padding(14)
                    }
                }
            }
            if let id = selectedID, let asset = session.document.asset(id: id) {
                Rectangle().fill(Theme.divider).frame(width: 1)
                mediaInspector(asset).frame(width: 300)
            }
        }
    }

    func symbol(for c: MediaCategory) -> String {
        switch c {
        case .videos: return "film"
        case .audio: return "waveform"
        case .images: return "photo"
        case .music: return "music.note"
        case .sfx: return "speaker.wave.3"
        case .graphics: return "square.on.circle"
        }
    }

    func binRow(_ c: MediaCategory?, title: String, symbol: String) -> some View {
        let count = c.map { cat in session.document.media.filter { $0.category == cat }.count } ?? session.document.media.count
        return Button { category = c } label: {
            HStack {
                Image(systemName: symbol).frame(width: 16)
                Text(title)
                Spacer()
                Text("\(count)").foregroundStyle(Theme.textTertiary)
            }
            .font(.pulseCaption)
            .foregroundStyle(category == c ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 5).fill(category == c ? Theme.control : .clear))
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
    }

    func mediaInspector(_ asset: MediaAsset) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ThumbnailView(url: asset.kind == .audio ? nil : session.url(for: asset), time: 2, maxWidth: 560, contentMode: .fit)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(asset.name).font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
                HStack {
                    Button { session.edit("Favorite") { $0.updateAsset(id: asset.id) { $0.isFavorite.toggle() } } } label: {
                        Label(asset.isFavorite ? "Favorited" : "Favorite", systemImage: asset.isFavorite ? "star.fill" : "star")
                    }
                    .buttonStyle(.pulse(.secondary, compact: true))
                    Button("Add to Timeline") { session.placeAsset(asset.id) }.buttonStyle(.pulse(.secondary, compact: true))
                }
                VStack(alignment: .leading, spacing: 5) {
                    KeyValueRow(key: "Kind", value: asset.kind.displayName)
                    KeyValueRow(key: "Duration", value: Timecode.string(asset.metadata.duration))
                    KeyValueRow(key: "Resolution", value: asset.metadata.width > 0 ? "\(asset.metadata.width)×\(asset.metadata.height)" : "—")
                    KeyValueRow(key: "Frame rate", value: asset.metadata.frameRateLabel)
                    KeyValueRow(key: "Video codec", value: asset.metadata.videoCodec ?? "—")
                    KeyValueRow(key: "Audio", value: asset.metadata.hasAudio ? "\(asset.metadata.audioCodec ?? "") \(asset.metadata.audioChannels)ch \(Int(asset.metadata.audioSampleRate)) Hz" : "None")
                    KeyValueRow(key: "File size", value: ByteCountFormatter().string(fromByteCount: asset.metadata.fileSize))
                    KeyValueRow(key: "Location", value: asset.path)
                    if asset.syncOffset != 0 { KeyValueRow(key: "Sync offset", value: String(format: "%+.2fs", asset.syncOffset)) }
                }
                Picker("Role", selection: Binding(get: { asset.role }, set: { r in session.edit("Set Role") { $0.updateAsset(id: asset.id) { $0.role = r; $0.category = MediaAsset.defaultCategory(kind: $0.kind, role: r) } } })) {
                    ForEach(MediaRole.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Tags")
                    FlowLayout(spacing: 4) {
                        ForEach(asset.tags, id: \.self) { tag in
                            HStack(spacing: 3) {
                                Text(tag)
                                Button { session.edit("Remove Tag") { $0.updateAsset(id: asset.id) { $0.tags.removeAll { $0 == tag } } } } label: { Image(systemName: "xmark").font(.system(size: 7, weight: .bold)) }
                                    .buttonStyle(.plain)
                            }
                            .font(.pulseMicro).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.control)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    TextField("Add tag", text: $newTag, onCommit: {
                        let tag = newTag.trimmingCharacters(in: .whitespaces)
                        guard !tag.isEmpty else { return }
                        session.edit("Add Tag") { $0.updateAsset(id: asset.id) { if !$0.tags.contains(tag) { $0.tags.append(tag) } } }
                        newTag = ""
                    })
                    .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Button("Analyze") { session.analyze(assetID: asset.id) }.buttonStyle(.pulse(.ai, compact: true))
                    Button("Proxy") { session.generateProxy(assetID: asset.id) }.buttonStyle(.pulse(.secondary, compact: true))
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([session.url(for: asset)]) }.buttonStyle(.pulse(.ghost, compact: true))
                }
                if asset.availability == .missing {
                    Button("Relink Missing File…") {
                        let panel = NSOpenPanel()
                        panel.message = "Locate “\(asset.name)”"
                        if panel.runModal() == .OK, let url = panel.url { session.relink(assetID: asset.id, to: url) }
                    }
                    .buttonStyle(.pulsePrimary)
                }
            }
            .padding(14)
        }
        .background(Theme.panel)
    }
}

struct MediaTile: View {
    @ObservedObject var session: ProjectSession
    let asset: MediaAsset
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                if asset.kind == .audio {
                    WaveformStrip(url: session.url(for: asset), sourceRange: TimeRange(start: 0, end: max(asset.metadata.duration, 0.1)),
                                  color: asset.role == .music ? Theme.musicClip : (asset.role == .soundEffect ? Theme.sfxClip : Theme.audioClip))
                        .padding(8)
                        .background(Theme.well)
                } else {
                    ThumbnailView(url: session.url(for: asset), time: min(3, asset.metadata.duration / 3), maxWidth: 360)
                }
                HStack(spacing: 4) {
                    if asset.isFavorite { Image(systemName: "star.fill").foregroundStyle(Theme.warning) }
                    if asset.availability == .missing { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger) }
                    if session.analyses[asset.id] != nil { Image(systemName: "sparkles").foregroundStyle(Theme.ai) }
                }
                .font(.system(size: 10))
                .padding(6)
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(asset.name).font(.pulseCaption).foregroundStyle(Theme.textPrimary).lineLimit(1)
            HStack(spacing: 6) {
                Label(asset.role.displayName, systemImage: asset.role.symbolName)
                Spacer()
                Text(Timecode.duration(asset.metadata.duration))
            }
            .font(.pulseMicro)
            .foregroundStyle(Theme.textTertiary)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.control : Theme.panelRaised))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Theme.accent : Theme.border))
    }
}

// MARK: Templates

struct TemplatesView: View {
    @EnvironmentObject var app: AppModel
    @State private var saving = false
    @State private var templateName = "My Gaming Shorts Template"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Templates").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text("Reusable looks: caption style, facecam layout & frame, color, intro/outro, music settings.").font(.pulseCaption).foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Button { saving = true } label: { Label("Save Current Timeline as Template", systemImage: "square.and.arrow.down.on.square") }
                    .buttonStyle(.pulsePrimary)
                    .disabled(app.session?.activeTimeline == nil)
            }
            .padding(16)
            .background(Theme.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 14)], spacing: 14) {
                    ForEach(app.allTemplates) { template in
                        TemplateCard(template: template)
                    }
                }
                .padding(18)
            }
        }
        .alert("Save Template", isPresented: $saving) {
            TextField("Name", text: $templateName)
            Button("Save") { app.session?.saveTemplate(named: templateName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Captures the caption style, layout, facecam frame, color and music settings of the open timeline.")
        }
    }
}

struct TemplateCard: View {
    @EnvironmentObject var app: AppModel
    let template: ClipTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x1D2233), Color(hex: 0x0F1118)], startPoint: .top, endPoint: .bottom)
                HStack(spacing: 14) {
                    Image(systemName: template.layout.symbolName).font(.system(size: 26)).foregroundStyle(Theme.textSecondary)
                    CaptionPresetSwatch(style: template.captionStyle, selected: false).frame(width: 110)
                }
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Text(template.name).font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
                Spacer()
                if template.isBuiltIn { TagChip(text: "Built-in") }
            }
            HStack(spacing: 4) {
                TagChip(text: template.layout.displayName, color: Theme.info)
                TagChip(text: template.captionStyle.presetName, color: Theme.ai)
                if template.silencePreset != nil { TagChip(text: "Jump cuts", color: Theme.warning) }
            }
            HStack {
                Button("Apply to Timeline") {
                    app.session?.applyTemplate(template)
                    app.section = .editor
                }
                .buttonStyle(.pulse(.primary, compact: true))
                .disabled(app.session?.activeTimeline == nil)
                Spacer()
                if !template.isBuiltIn {
                    Button { app.deleteGlobalTemplate(template.id) } label: { Image(systemName: "trash") }.buttonStyle(.pulse(.ghost, compact: true))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.radiusLarge).fill(Theme.panelRaised))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).strokeBorder(Theme.border))
    }
}

// MARK: Exports

struct ExportSettingsForm: View {
    @Binding var settings: ExportSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Preset")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(ExportPreset.builtIn) { preset in
                    Button {
                        let dir = settings.outputDirectory
                        let quality = settings.quality
                        let burn = settings.burnInCaptions
                        let template = settings.filenameTemplate
                        settings = ExportSettings(preset: preset, outputDirectory: dir, quality: quality)
                        settings.burnInCaptions = burn
                        settings.filenameTemplate = template
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Image(systemName: preset.symbolName).font(.system(size: 14))
                            Text(preset.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            Text(preset.resolutionLabel).font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .foregroundStyle(settings.presetID == preset.id ? Theme.accent : Theme.textSecondary)
                        .background(RoundedRectangle(cornerRadius: 6).fill(settings.presetID == preset.id ? Theme.accentSoft : Theme.control))
                    }
                    .buttonStyle(.plain)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Resolution").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    HStack {
                        TextField("W", value: $settings.width, format: .number).frame(width: 70)
                        Text("×").foregroundStyle(Theme.textTertiary)
                        TextField("H", value: $settings.height, format: .number).frame(width: 70)
                        Text("(long side is used; aspect follows the timeline)").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                    }
                }
                GridRow {
                    Text("Frame rate").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    Picker("", selection: $settings.frameRate) {
                        Text("Timeline").tag(Double?.none)
                        ForEach([24.0, 25, 30, 50, 60], id: \.self) { Text("\(Int($0)) fps").tag(Optional($0)) }
                    }
                    .labelsHidden().frame(width: 140)
                }
                GridRow {
                    Text("Codec").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    Picker("", selection: $settings.codec) {
                        ForEach(VideoCodec.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden().frame(width: 200)
                }
                GridRow {
                    Text("Quality").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    Picker("", selection: $settings.quality) {
                        ForEach(ExportQuality.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 300)
                }
                GridRow {
                    Text("Video bitrate").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    HStack {
                        Slider(value: Binding(get: { Double(settings.videoBitrate) / 1_000_000 }, set: { settings.videoBitrate = Int($0 * 1_000_000) }), in: 1...80)
                            .frame(width: 200)
                        Text(String(format: "%.0f Mbps → %.1f Mbps effective", Double(settings.videoBitrate) / 1_000_000, Double(settings.effectiveVideoBitrate) / 1_000_000))
                            .font(.pulseMono).foregroundStyle(Theme.textTertiary)
                    }
                }
                GridRow {
                    Text("Audio bitrate").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    Picker("", selection: $settings.audioBitrate) {
                        ForEach([128_000, 192_000, 256_000, 320_000], id: \.self) { Text("\($0 / 1000) kbps").tag($0) }
                    }
                    .labelsHidden().frame(width: 140)
                }
                GridRow {
                    Text("Filename").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("{clip}-{preset}", text: $settings.filenameTemplate).frame(width: 300)
                        Text("Tokens: {project} {clip} {preset} {date} {index}").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                    }
                }
                GridRow {
                    Text("Folder").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    HStack {
                        Text(settings.outputDirectory.isEmpty ? "Not set" : settings.outputDirectory).font(.pulseCaption).foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.middle).frame(maxWidth: 300, alignment: .leading)
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.canCreateDirectories = true
                            if panel.runModal() == .OK, let url = panel.url { settings.outputDirectory = url.path }
                        }
                        .buttonStyle(.pulse(.secondary, compact: true))
                    }
                }
                GridRow {
                    Text("Options").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 14) {
                        Toggle("Burn in captions", isOn: $settings.burnInCaptions)
                        Toggle("Also export .srt", isOn: $settings.exportSRT)
                        Toggle("Hardware encoder", isOn: $settings.useHardwareEncoding)
                    }
                    .toggleStyle(.checkbox)
                    .font(.pulseCaption)
                }
            }
            .textFieldStyle(.roundedBorder)
        }
    }
}

struct ExportsView: View {
    @EnvironmentObject var app: AppModel
    @State private var settings = ExportSettings()
    @State private var loaded = false
    /// Settings as loaded; changes equal to it are not user edits.
    @State private var baseline: ExportSettings?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Export").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    ExportSettingsForm(settings: $settings)
                    HStack(spacing: 10) {
                        Button { exportCurrent() } label: { Label("Export Current Timeline", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.pulsePrimary)
                            .disabled(app.session?.activeTimeline == nil)
                        Button { exportAllShorts() } label: { Label("Export All Shorts (\(app.session?.document.timelines.count ?? 0))", systemImage: "square.and.arrow.up.on.square") }
                            .buttonStyle(.pulseSecondary)
                            .disabled((app.session?.document.timelines.isEmpty ?? true))
                    }
                    if let problem = settings.validationError(for: app.session?.activeTimeline?.canvas ?? .vertical1080) {
                        Label(problem, systemImage: "exclamationmark.triangle").font(.pulseCaption).foregroundStyle(Theme.warning)
                    }
                    Text("Exports render in the background with the GPU compositor and VideoToolbox hardware encoder. Keep editing while they run.")
                        .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity)
            Rectangle().fill(Theme.divider).frame(width: 1)
            ExportQueueView(queue: app.exports).frame(width: 400)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let preset = ExportPreset.preset(id: app.settings.defaultExportPresetID) ?? .tiktok
            settings = app.session?.document.exportSettings ?? ExportSettings(preset: preset)
            if settings.outputDirectory.isEmpty { settings.outputDirectory = app.exportFolder.path }
            // A YouTube edit (Edit My VOD) shouldn't start on a vertical short-form preset.
            if let timeline = app.session?.activeTimeline, EditFormat.of(timeline) == .longForm,
               ["tiktok", "shorts", "reels"].contains(settings.presetID) {
                let folder = settings.outputDirectory
                settings = ExportSettings(preset: .youtube)
                settings.outputDirectory = folder
            }
            baseline = settings
        }
        .onChange(of: settings) { _, newValue in
            if let baseline, newValue == baseline { return }
            baseline = nil
            app.session?.edit("Export Settings", coalesce: "export-settings") { $0.exportSettings = newValue }
            app.settings.defaultExportPresetID = newValue.presetID
        }
    }

    func exportCurrent() {
        guard let session = app.session, let timeline = session.activeTimeline else { return }
        app.exports.enqueue(timelines: [timeline], document: session.document, settings: settings)
        app.toast("Added “\(timeline.name)” to the export queue")
    }

    func exportAllShorts() {
        guard let session = app.session else { return }
        app.exports.enqueue(timelines: session.document.timelines, document: session.document, settings: settings)
        app.toast("Queued \(session.document.timelines.count) exports")
    }
}

struct ExportQueueView: View {
    @ObservedObject var queue: ExportQueueController

    var body: some View {
        let summary = queue.summary
        VStack(spacing: 0) {
            PanelHeader("Export Queue", subtitle: summary.total == 0 ? "Empty" : "\(summary.completed) done · \(summary.active) rendering · \(summary.queued) queued\(summary.failed > 0 ? " · \(summary.failed) failed" : "")") {
                HStack(spacing: 4) {
                    Button("Cancel All") { queue.cancelAll() }.buttonStyle(.pulse(.ghost, compact: true)).disabled(summary.active + summary.queued == 0)
                    Button("Clear") { queue.clearFinished() }.buttonStyle(.pulse(.ghost, compact: true))
                }
            }
            if summary.total > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    ThinProgressBar(progress: summary.overallProgress)
                    if let eta = summary.estimatedRemaining, summary.active + summary.queued > 0 {
                        Text("About \(Timecode.duration(eta)) remaining").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(12)
            }
            if queue.jobs.isEmpty {
                EmptyStateView(symbol: "tray", title: "No exports", message: "Queue one timeline, or select several AI clips and batch export them.")
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(queue.jobs) { job in ExportJobRow(queue: queue, job: job) }
                    }
                }
            }
        }
        .background(Theme.panel)
    }
}

struct ExportJobRow: View {
    @ObservedObject var queue: ExportQueueController
    let job: ExportJob

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(job.timelineName).font(.pulseBody).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer()
                Text(ExportPreset.preset(id: job.settings.presetID)?.name ?? "Custom").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            }
            switch job.status {
            case .queued:
                HStack { Text("Queued").font(.pulseMicro).foregroundStyle(Theme.textTertiary); Spacer(); Button("Cancel") { queue.cancel(job.id) }.buttonStyle(.pulse(.ghost, compact: true)) }
            case .preparing, .rendering:
                ThinProgressBar(progress: job.status.progress)
                HStack {
                    Text(job.status.label).font(.pulseMicro).foregroundStyle(Theme.textSecondary)
                    if let eta = job.estimatedRemaining() { Text("· \(Timecode.duration(eta)) left").font(.pulseMicro).foregroundStyle(Theme.textTertiary) }
                    Spacer()
                    Button("Cancel") { queue.cancel(job.id) }.buttonStyle(.pulse(.ghost, compact: true))
                }
            case .completed:
                HStack {
                    Label("Completed", systemImage: "checkmark.circle.fill").font(.pulseMicro).foregroundStyle(Theme.success)
                    Spacer()
                    Button("Show in Finder") { queue.reveal(job) }.buttonStyle(.pulse(.ghost, compact: true))
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 4) {
                    Label("Failed", systemImage: "xmark.octagon.fill").font(.pulseMicro).foregroundStyle(Theme.danger)
                    Text(message).font(.pulseMicro).foregroundStyle(Theme.textSecondary)
                    Button("Retry") { queue.retry(job.id) }.buttonStyle(.pulse(.secondary, compact: true))
                }
            case .cancelled:
                HStack { Text("Cancelled").font(.pulseMicro).foregroundStyle(Theme.textTertiary); Spacer(); Button("Retry") { queue.retry(job.id) }.buttonStyle(.pulse(.ghost, compact: true)) }
            }
        }
        .padding(12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }
}

/// Batch export from the AI Clips page: builds shorts for candidates that don't have one yet.
struct BatchExportSheet: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: ProjectSession
    let candidateIDs: Set<UUID>
    @State private var settings = ExportSettings()
    @State private var mode: ShortBuildOptions.Mode = .oneClick

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Batch Export \(candidateIDs.count) Clip\(candidateIDs.count == 1 ? "" : "s")").font(.pulseTitle).foregroundStyle(Theme.textPrimary)
            Text("Clips without an edit are built automatically (captions, framing, punch-ins) before exporting. Existing edits are exported as they are.")
                .font(.pulseCaption).foregroundStyle(Theme.textSecondary)
            Picker("Build mode", selection: $mode) {
                Text("Create Short").tag(ShortBuildOptions.Mode.oneClick)
                Text("Auto Edit").tag(ShortBuildOptions.Mode.autoEdit)
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
            ExportSettingsForm(settings: $settings)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.pulseSecondary).keyboardShortcut(.cancelAction)
                Button("Export \(candidateIDs.count)") { run() }.buttonStyle(.pulsePrimary).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 720)
        .background(Theme.panel)
        .onAppear {
            settings = session.document.exportSettings
            if settings.outputDirectory.isEmpty { settings.outputDirectory = app.exportFolder.path }
        }
    }

    func run() {
        var timelineIDs: [UUID] = []
        for id in candidateIDs {
            if let t = session.createShort(from: id, mode: mode, open: false) { timelineIDs.append(t) }
        }
        let timelines = timelineIDs.compactMap { session.document.timeline(id: $0) }
        app.exports.enqueue(timelines: timelines, document: session.document, settings: settings)
        app.toast("Queued \(timelines.count) exports")
        dismiss()
        app.section = .exports
    }
}
