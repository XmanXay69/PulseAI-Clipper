import UniformTypeIdentifiers
import PulseCore
import PulseEngine
import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject var app: AppModel
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var sort: Sort = .modified

    enum Filter: String, CaseIterable { case all = "All", favorites = "Favorites", trash = "Trash" }
    enum Sort: String, CaseIterable { case modified = "Last Edited", name = "Name", duration = "Duration", clips = "Clips" }

    var filtered: [ProjectSummary] {
        var list: [ProjectSummary]
        switch filter {
        case .all: list = app.projects.filter { !$0.isTrashed }
        case .favorites: list = app.projects.filter { $0.isFavorite && !$0.isTrashed }
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

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                TextField("Filter projects", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Spacer()
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: { Label("Sort: \(sort.rawValue)", systemImage: "arrow.up.arrow.down") }
                    .menuStyle(.borderlessButton)
                    .frame(width: 170)
                Button { app.showOpenPanel() } label: { Label("Open…", systemImage: "folder") }.buttonStyle(.pulseSecondary)
                Button { app.showNewProjectSheet = true } label: { Label("New Project", systemImage: "plus") }.buttonStyle(.pulsePrimary)
            }
            .padding(14)
            .background(Theme.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }

            if filtered.isEmpty {
                EmptyStateView(symbol: filter == .trash ? "trash" : "square.grid.2x2",
                               title: filter == .trash ? "Trash is empty" : "No projects",
                               message: filter == .trash ? "Projects you move to the Trash appear here until you delete them." : "Projects live in \(app.projectsFolder.path). Create one or open the sample project.",
                               actionTitle: filter == .trash ? nil : "New Project") { app.showNewProjectSheet = true }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 16)], spacing: 16) {
                        ForEach(filtered) { ProjectCard(project: $0) }
                    }
                    .padding(20)
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
            Text("New Project").font(.pulseTitle).foregroundStyle(Theme.textPrimary)
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
            VStack(spacing: 18) {
                DropZone(targeted: $targeted) { app.importMedia($0) }
                    .frame(maxWidth: 720, maxHeight: 320)
                HStack(spacing: 10) {
                    Button { app.showImportPanel() } label: { Label("Choose Files…", systemImage: "folder") }.buttonStyle(.pulsePrimary)
                    Button { app.openDemoProject() } label: { Label("Use Sample Project", systemImage: "play.rectangle") }.buttonStyle(.pulseSecondary)
                }
            }
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct DropZone: View {
    @Binding var targeted: Bool
    let onDrop: ([URL]) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(targeted ? Theme.accent : Theme.textTertiary)
            Text("Drop a long video here").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text("Twitch VODs, YouTube videos, podcasts, gameplay. Add separate webcam, gameplay and microphone recordings together and PULSE will sync them.")
                .font(.pulseBody).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 460)
            HStack(spacing: 6) {
                ForEach(["MP4", "MOV", "MKV", "WebM", "WAV", "MP3", "SRT"], id: \.self) { TagChip(text: $0) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(targeted ? Theme.accentSoft : Theme.panelRaised))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(targeted ? Theme.accent : Theme.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])))
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
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                DropZone(targeted: $targeted) { session.importMedia($0) }
                    .frame(height: 190)
                Text("Media in this project").font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
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
        .padding(20)
        .onAppear {
            lengthPreset = app.settings.ai.defaultClipLength
            customLength = app.settings.ai.customClipLength
            aggressiveness = app.settings.ai.clipAggressiveness
        }
    }

    var analyzePanel: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Analyze Video").font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    AIBadge()
                }
                Text("PULSE transcribes speech, measures loudness, laughter and reactions, detects scene changes and faces, then proposes clips with a hook, context and payoff.")
                    .font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Clip length")
                    Picker("", selection: $lengthPreset) {
                        ForEach(ClipLengthPreset.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if lengthPreset == .custom {
                        LabeledSlider(label: "Seconds", value: $customLength, range: 10...90, format: "%.0f", unit: "s")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "How many clips")
                    LabeledSlider(label: aggressiveness < 0.34 ? "Best only" : (aggressiveness < 0.67 ? "Balanced" : "Lots"), value: $aggressiveness, range: 0...1, format: "%.0f", unit: "")
                }
                HStack(spacing: 6) {
                    ProcessingBadge(location: .local)
                    Text(TranscriptionEngineFactory.availabilitySummary(settings: app.settings.ai))
                        .font(.pulseMicro).foregroundStyle(Theme.textTertiary).lineLimit(2)
                }
                if let asset = session.document.primaryAsset {
                    if let progress = session.analysisProgress[asset.id] {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(progress.stage).font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                            ThinProgressBar(progress: progress.fraction, color: Theme.ai)
                        }
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
                    .buttonStyle(.pulseAI)
                    .disabled(session.analysisProgress[asset.id] != nil)
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
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(alignment: .center) {
                    if asset.kind == .audio { Image(systemName: "waveform").foregroundStyle(Theme.audioClip) }
                }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(asset.name).font(.pulseBody).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    if session.document.primaryAssetID == asset.id { TagChip(text: "Main", color: Theme.accent) }
                    if asset.availability == .missing { TagChip(text: "Offline", color: Theme.danger, symbol: "exclamationmark.triangle.fill") }
                    if asset.preparation.proxyPath != nil { TagChip(text: "Proxy", color: Theme.info) }
                }
                Text("\(asset.kind.displayName) · \(Timecode.duration(asset.metadata.duration)) · \(asset.metadata.resolutionLabel) · \(asset.metadata.frameRateLabel)\(asset.metadata.videoCodec.map { " · \($0)" } ?? "")")
                    .font(.pulseCaption).foregroundStyle(Theme.textTertiary)
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
                Button("Generate Proxy") { session.generateProxy(assetID: asset.id) }
                Button("Add to Timeline") { session.placeAsset(asset.id) }
                if asset.availability == .missing { Button("Relink…") { relink() } }
                Divider()
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([session.url(for: asset)]) }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .frame(width: 30)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.panelRaised))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
    }

    @ViewBuilder
    var analysisState: some View {
        if let progress = session.analysisProgress[asset.id] {
            HStack(spacing: 6) {
                ProgressRing(progress: progress.fraction, size: 12, color: Theme.ai)
                Text(progress.stage).font(.pulseMicro).foregroundStyle(Theme.ai)
            }
        } else if let analysis = session.analyses[asset.id] {
            HStack(spacing: 8) {
                if let t = analysis.transcript { TagChip(text: "\(t.words.count) words", color: Theme.success, symbol: "text.quote") }
                if analysis.audio != nil { TagChip(text: "Audio", color: Theme.success, symbol: "waveform") }
                if let v = analysis.visual { TagChip(text: "\(v.sceneCuts.count) cuts", color: Theme.success, symbol: "film") }
                if analysis.webcam != nil { TagChip(text: "Facecam", color: Theme.success, symbol: "person.crop.square") }
                TagChip(text: analysis.profile.displayName, color: Theme.ai)
            }
        } else {
            Text("Not analyzed").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
        }
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

