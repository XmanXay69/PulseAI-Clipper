import UniformTypeIdentifiers
import PulseCore
import PulseEngine
import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject var app: AppModel
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var sort: Sort = .modified
    @AppStorage("projects.board") private var board = false

    enum Filter: String, CaseIterable { case all = "All", favorites = "Favorites", thisWeek = "This Week", inProgress = "In Progress", exported = "Exported", dueSoon = "Due Soon", trash = "Trash" }
    enum Sort: String, CaseIterable { case modified = "Last Edited", name = "Name", duration = "Duration", clips = "Clips" }

    var filtered: [ProjectSummary] {
        var list: [ProjectSummary]
        switch filter {
        case .all: list = app.projects.filter { !$0.isTrashed }
        case .favorites: list = app.projects.filter { $0.isFavorite && !$0.isTrashed }
        case .thisWeek: list = app.projects.filter { !$0.isTrashed && $0.modifiedAt > Date().addingTimeInterval(-7 * 86400) }
        case .inProgress: list = app.projects.filter { !$0.isTrashed && ($0.status == .editing || $0.status == .clipsReady || $0.status == .analyzing) }
        case .exported: list = app.projects.filter { !$0.isTrashed && $0.status == .exported }
        case .dueSoon: list = app.projects.filter { !$0.isTrashed && ($0.deadline.map { $0.timeIntervalSinceNow < 7 * 86400 } ?? false) }.sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
        case .trash: list = (app.library?.projects(includeTrashed: true) ?? []).filter(\.isTrashed)
        }
        if !query.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(query) } }
        switch sort {
        case .modified: list.sort { $0.modifiedAt > $1.modifiedAt }
        case .name: list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .duration: list.sort { $0.duration > $1.duration }
        case .clips: list.sort { $0.clipCount > $1.clipCount }
        }
        return list
    }

    /// "3 projects · ~/Movies/PULSE Projects"
    var subtitle: String {
        let count = app.projects.filter { !$0.isTrashed }.count
        let folder = (app.projectsFolder.path as NSString).abbreviatingWithTildeInPath
        return "\(count) project\(count == 1 ? "" : "s") · \(folder)"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader("Projects", subtitle: subtitle) {
                    Button { app.showOpenPanel() } label: { Label("Open…", systemImage: "folder") }.buttonStyle(.pulse(.secondary, compact: true))
                    Button { app.showNewProjectSheet = true } label: { Label("New project", systemImage: "plus") }.buttonStyle(.pulse(.primary, compact: true))
                }
                HStack(spacing: 10) {
                    PulseSegmented(selection: $filter, Filter.allCases) { $0.rawValue }
                        .frame(width: 520)
                    Spacer(minLength: 8)
                    TextField("Search projects", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 190)
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    } label: { Label(sort.rawValue, systemImage: "arrow.up.arrow.down") }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Sort projects")
                    IconButton(symbol: board ? "rectangle.split.3x1.fill" : "rectangle.split.3x1", help: board ? "Grid" : "Status board — Editing, Ready, Exported, Posted; drag to move (#474)", isActive: board) { board.toggle() }
                }
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.top, 4)
            .padding(.bottom, Theme.Spacing.l)

            if filtered.isEmpty {
                EmptyStateView(symbol: filter == .trash ? "trash" : "square.grid.2x2",
                               title: filter == .trash ? "Trash is empty" : "No projects",
                               message: filter == .trash ? "Projects you move to the Trash appear here until you delete them." : "Projects live in \(app.projectsFolder.path). Create one or open the sample project.",
                               actionTitle: filter == .trash ? nil : "New Project") { app.showNewProjectSheet = true }
            } else if board {
                ProjectBoard(projects: filtered)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 16)], spacing: 16) {
                        ForEach(filtered) { ProjectCard(project: $0) }
                    }
                    .padding(.horizontal, Theme.Spacing.xxl)
                    .padding(.bottom, Theme.Spacing.xxl)
                }
            }
        }
        .onAppear { app.refreshProjects() }
    }
}

struct NewProjectSheet: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Untitled Project"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New project").font(.pulseTitle).foregroundStyle(Theme.textPrimary)
            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                TextField("Project name", text: $name).textFieldStyle(.roundedBorder).onSubmit(create)
            }
            Text("Saved to \(app.projectsFolder.path)").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.pulseSecondary).keyboardShortcut(.cancelAction)
                Button("Create", action: create).buttonStyle(.pulsePrimary).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(Theme.panel)
    }

    func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        app.newProject(name: trimmed)
        dismiss()
    }
}

// MARK: Import

struct ImportView: View {
    @EnvironmentObject var app: AppModel
    @State private var targeted = false

    var body: some View {
        if let session = app.session {
            ImportProjectView(session: session)
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                PageHeader("Import", subtitle: "Drop in a stream, podcast or gameplay recording to start a project") {
                    Button { app.openDemoProject() } label: { Label("Sample project", systemImage: "play.rectangle") }.buttonStyle(.pulse(.secondary, compact: true))
                    Button { app.showRecordSheet = true } label: { Label("Record screen…", systemImage: "record.circle") }.buttonStyle(.pulse(.secondary, compact: true))
                    Button { app.showImportPanel() } label: { Label("Choose files…", systemImage: "folder") }.buttonStyle(.pulse(.primary, compact: true))
                }
                DropZone(targeted: $targeted) { app.importMedia($0) }
                    .frame(maxWidth: .infinity, maxHeight: 360)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.top, 4)
            .padding(.bottom, Theme.Spacing.xxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct DropZone: View {
    @Binding var targeted: Bool
    let onDrop: ([URL]) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(targeted ? Theme.accent : Theme.textSecondary)
            Text("Drop a long video here").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text("Twitch VODs, YouTube videos, podcasts, gameplay. Add separate webcam, gameplay and microphone recordings together and PULSE will sync them.")
                .font(.pulseBody).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 460)
            HStack(spacing: 6) {
                ForEach(["MP4", "MOV", "MKV", "WebM", "WAV", "MP3", "SRT"], id: \.self) { TagChip(text: $0) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.radiusXL, style: .continuous).fill(targeted ? Theme.accentSoft : Theme.panelRaised))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusXL, style: .continuous).strokeBorder(targeted ? Theme.accent : Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [6, 5])))
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            loadURLs(from: providers) { onDrop($0) }
            return true
        }
    }
}

struct ImportProjectView: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    @State private var targeted = false
    @State private var lengthPreset: ClipLengthPreset = .medium30
    @State private var customLength: Double = 45
    @State private var aggressiveness: Double = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            PageHeader("Import", subtitle: "Add recordings to \(session.document.name), then let PULSE find the moments") {
                Button { app.showRecordSheet = true } label: { Label("Record screen…", systemImage: "record.circle") }
                    .buttonStyle(.pulse(.secondary, compact: true))
                Button { app.showImportPanel() } label: { Label("Choose files…", systemImage: "folder") }
                    .buttonStyle(.pulse(.primary, compact: true))
            }
            columns
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.top, 4)
        .padding(.bottom, Theme.Spacing.xxl)
        .onAppear {
            lengthPreset = app.settings.ai.defaultClipLength
            customLength = app.settings.ai.customClipLength
            aggressiveness = app.settings.ai.clipAggressiveness
        }
    }

    var columns: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: 14) {
                DropZone(targeted: $targeted) { session.importMedia($0) }
                    .frame(height: 190)
                SectionLabel(text: "Media in this project")
                ForEach(session.multicamGroups, id: \.id) { group in
                    MulticamSessionCard(session: session, group: group)
                }
                if session.document.media.isEmpty {
                    Text("Nothing imported yet.").font(.pulseBody).foregroundStyle(Theme.textTertiary)
                }
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(session.document.media) { asset in
                            ImportedAssetRow(session: session, asset: asset)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            analyzePanel.frame(width: 340)
        }
    }

    var analyzePanel: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionLabel(text: "Analyze video")
                    Spacer()
                    AIBadge()
                }
                Text("PULSE transcribes speech, measures loudness, laughter and reactions, detects scene changes and faces, then proposes clips with a hook, context and payoff.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Clip length")
                    PulseSegmented(selection: $lengthPreset, segments: ClipLengthPreset.allCases.map { PulseSegment($0, $0.segmentTitle, help: $0.displayName) })
                    if lengthPreset == .custom {
                        LabeledSlider(label: "Seconds", value: $customLength, range: 10...90, format: "%.0f", unit: "s")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "How many clips")
                    LabeledSlider(label: aggressiveness < 0.34 ? "Best only" : (aggressiveness < 0.67 ? "Balanced" : "Lots"), value: Binding(get: { aggressiveness * 100 }, set: { aggressiveness = $0 / 100 }), range: 0...100, format: "%.0f", unit: "%")
                }
                let status = TranscriptionEngineFactory.friendlyStatus(settings: app.settings.ai)
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: status.ready ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(.system(size: 11)).foregroundStyle(status.ready ? Theme.success : Theme.warning)
                    Text(status.text).font(.pulseMicro).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                if let asset = session.document.primaryAsset {
                    if let progress = session.analysisProgress[asset.id] {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(progress.stage).font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Text("\(Int(progress.fraction * 100))%").font(.pulseMono).foregroundStyle(Theme.textTertiary)
                            }
                            ThinProgressBar(progress: progress.fraction, color: Theme.ai)
                            if let left = session.analysisRemaining[asset.id] {
                                Text(DurationText.remaining(left)).font(.pulseMicro).foregroundStyle(Theme.ai)
                            }
                        }
                    } else if session.analyses[asset.id] == nil {
                        Label("Takes \(DurationText.approximate(session.analysisEstimate(for: asset))) for this \(Timecode.short(asset.metadata.duration)) video on this Mac",
                              systemImage: "clock")
                            .font(.pulseMicro).foregroundStyle(Theme.textSecondary)
                    }
                    Button {
                        applySettings()
                        if session.analyses[asset.id] == nil || session.analyses[asset.id]?.audio == nil {
                            session.analyze(assetID: asset.id)
                        } else {
                            session.generateCandidates(assetID: asset.id)
                        }
                    } label: {
                        Label(session.analyses[asset.id] == nil ? "Analyze & Find Clips" : "Find Clips Again", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pulsePrimary)
                    .disabled(session.analysisProgress[asset.id] != nil)
                    Button { app.showLongFormSheet = true } label: {
                        Label("Edit My VOD into a YouTube Video", systemImage: "film.stack").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pulseSecondary)
                    .help("Cut the stream down to a 10–20 minute video with a hook, zooms, captions, memes, music and sound effects")
                    Text("Main recording: \(asset.name)").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                } else {
                    Text("Import a video to analyze it.").font(.pulseCaption).foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    func applySettings() {
        app.settings.ai.defaultClipLength = lengthPreset
        app.settings.ai.customClipLength = customLength
        app.settings.ai.clipAggressiveness = aggressiveness
    }
}

struct ImportedAssetRow: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    let asset: MediaAsset

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(url: asset.kind == .audio ? nil : session.url(for: asset), time: min(5, asset.metadata.duration / 3), maxWidth: 200)
                .frame(width: 96, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .overlay(alignment: .center) {
                    if asset.kind == .audio { Image(systemName: "waveform").foregroundStyle(Theme.audioClip) }
                }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(asset.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    if session.document.primaryAssetID == asset.id { TagChip(text: "Main", color: Theme.accent) }
                    if asset.availability == .missing { TagChip(text: "Offline", color: Theme.danger, symbol: "exclamationmark.triangle.fill") }
                    if asset.preparation.proxyPath != nil { TagChip(text: "Proxy") }
                }
                Text("\(asset.kind.displayName) · \(Timecode.duration(asset.metadata.duration)) · \(asset.metadata.resolutionLabel) · \(asset.metadata.frameRateLabel)\(asset.metadata.videoCodec.map { " · \($0)" } ?? "")")
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                analysisState
            }
            Spacer()
            Menu {
                Picker("Role", selection: Binding(get: { asset.role }, set: { role in session.edit("Set Role") { $0.updateAsset(id: asset.id) { $0.role = role } } })) {
                    ForEach(MediaRole.allCases, id: \.self) { Label($0.displayName, systemImage: $0.symbolName).tag($0) }
                }
            } label: {
                Label(asset.role.displayName, systemImage: asset.role.symbolName).font(.pulseCaption)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 130)
            Menu {
                Button("Set as Main Recording") { session.edit("Set Main Recording") { $0.primaryAssetID = asset.id } }
                Button("Analyze") { session.analyze(assetID: asset.id) }
                Button("Import Transcript (SRT/VTT)…") { pickTranscript() }
                Button("Import Chat Replay (Twitch / YouTube)…") { pickChat() }
                Button("Import Game Events (Riot log, CSV, JSON)…") { pickGameEvents() }
                let signals = PluginRegistry.shared.signals
                if !signals.isEmpty {
                    Menu("Run Signal Plugin") {
                        ForEach(signals) { plugin in
                            Button(plugin.manifest.name) { session.runSignalPlugin(plugin, assetID: asset.id) }
                        }
                    }
                }
                if session.analyses[asset.id]?.chat != nil {
                    Menu("Chat Replay") {
                        Button("Chat 5 s Earlier") { session.shiftChat(by: -5, assetID: asset.id) }
                        Button("Chat 5 s Later") { session.shiftChat(by: 5, assetID: asset.id) }
                        Divider()
                        Button("Remove Chat Replay") { session.removeChat(assetID: asset.id) }
                    }
                }
                Button("Generate Proxy") { session.generateProxy(assetID: asset.id) }
                Button("Add to Timeline") { session.placeAsset(asset.id) }
                if asset.availability == .missing { Button("Relink…") { relink() } }
                Divider()
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([session.url(for: asset)]) }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .frame(width: 30)
        }
        .padding(12)
        .raisedSurface(cornerRadius: Theme.radiusXL)
    }

    @ViewBuilder
    var analysisState: some View {
        if let progress = session.analysisProgress[asset.id] {
            HStack(spacing: 6) {
                ProgressRing(progress: progress.fraction, size: 12, color: Theme.ai)
                Text(progress.stage).font(.pulseMicro).foregroundStyle(Theme.ai)
                if let left = session.analysisRemaining[asset.id] {
                    Text("· " + DurationText.remaining(left)).font(.pulseMicro).foregroundStyle(Theme.textSecondary)
                }
            }
        } else if let analysis = session.analyses[asset.id] {
            HStack(spacing: 8) {
                // What the analysis found, as quiet tags: a row of green pills said "done" five times over.
                if let t = analysis.transcript { TagChip(text: "\(t.words.count) words", symbol: "text.quote") }
                if analysis.audio != nil { TagChip(text: "Audio", symbol: "waveform") }
                if let v = analysis.visual { TagChip(text: "\(v.sceneCuts.count) cuts", symbol: "film") }
                if analysis.webcam != nil { TagChip(text: "Facecam", symbol: "person.crop.square") }
                if let chat = analysis.chat { TagChip(text: "\(chat.messages.count) chat", symbol: "bubble.left.and.bubble.right") }
                TagChip(text: analysis.profile.displayName)
            }
        } else {
            Text("Not analyzed").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
        }
    }

    func pickChat() {
        let panel = NSOpenPanel()
        panel.message = "Choose a chat replay: TwitchDownloader JSON, chat-downloader JSON/CSV, YouTube .live_chat.json, or a text log."
        panel.allowedContentTypes = ["json", "csv", "txt", "log"].compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK, let url = panel.url { session.importChat(url, for: asset.id) }
    }

    /// Exact timestamps from the game's own API (#488).
    func pickGameEvents() {
        let panel = NSOpenPanel()
        panel.message = "Choose a game event log: Riot Live Client Data JSON (eventdata), a CSV with time,kind,text lines, or a JSON list of {time, kind, text}."
        panel.allowedContentTypes = ["json", "csv", "txt", "log"].compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK, let url = panel.url { session.importGameEvents(url, for: asset.id) }
    }

    func pickTranscript() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["srt", "vtt", "json"].compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK, let url = panel.url { session.importTranscript(url, for: asset.id) }
    }

    func relink() {
        let panel = NSOpenPanel()
        panel.message = "Locate “\(asset.name)”"
        if panel.runModal() == .OK, let url = panel.url { session.relink(assetID: asset.id, to: url) }
    }
}


/// Projects as columns on their way out the door (#474). Drag a card to another column; a project that was
/// never placed shows where its contents put it (exported or editing).
struct ProjectBoard: View {
    @EnvironmentObject var app: AppModel
    let projects: [ProjectSummary]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(WorkflowStage.allCases, id: \.self) { stage in column(stage) }
        }
        .padding(16)
    }

    func column(_ stage: WorkflowStage) -> some View {
        let items = projects.filter { $0.boardStage == stage }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: stage.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                Text(stage.displayName).font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
                Text("\(items.count)").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 4)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(items) { project in
                        ProjectCard(project: project)
                            .draggable(project.id.uuidString)
                    }
                    if items.isEmpty {
                        Text(stage == .ready ? "Drag an edit here when it's ready to export" : (stage == .posted ? "Drag here once it's up" : "Nothing here"))
                            .font(.pulseMicro).foregroundStyle(Theme.textTertiary).padding(12)
                    }
                }
                .padding(4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous).strokeBorder(Theme.border))
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first, let id = UUID(uuidString: first), let project = app.projects.first(where: { $0.id == id }) else { return false }
            app.setWorkflowStage(project, stage)
            return true
        }
    }
}
