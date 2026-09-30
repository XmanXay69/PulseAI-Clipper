import PulseCore
import PulseEngine
import SwiftUI

/// Professional NLE layout: left tools · center viewer · right inspector · bottom timeline.
/// Panel sizes are draggable and saved per workspace preset.
struct EditorView: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession

    var layout: WorkspaceLayout { app.settings.layout(for: app.settings.currentWorkspace) }

    func updateLayout(_ body: (inout WorkspaceLayout) -> Void) {
        var l = layout
        body(&l)
        app.settings.workspaces[app.settings.currentWorkspace.rawValue] = l
    }

    var body: some View {
        if session.activeTimeline == nil {
            EmptyStateView(symbol: "timeline.selection", title: "Nothing to edit yet",
                           message: session.document.visibleCandidates.isEmpty ? "Analyze a recording to get AI clips, or start an empty timeline." : "Open one of your AI clips, or start an empty timeline.",
                           actionTitle: session.document.visibleCandidates.isEmpty ? "New Vertical Timeline" : "Go to AI Clips") {
                if session.document.visibleCandidates.isEmpty {
                    session.newTimeline(canvas: .vertical1080, name: "Vertical Edit")
                } else {
                    app.section = .aiClips
                }
            }
        } else {
            VStack(spacing: 0) {
                WorkspaceBar()
                HStack(spacing: 0) {
                    if layout.showLeftPanel {
                        LeftPanel(session: session)
                            .frame(width: layout.leftPanelWidth)
                        ResizeHandle(axis: .horizontal) { delta in
                            updateLayout { $0.leftPanelWidth = min(max($0.leftPanelWidth + delta, 220), 520) }
                        }
                    }
                    ViewerView(session: session)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if layout.showRightPanel {
                        ResizeHandle(axis: .horizontal) { delta in
                            updateLayout { $0.rightPanelWidth = min(max($0.rightPanelWidth - delta, 260), 520) }
                        }
                        InspectorView(session: session)
                            .frame(width: layout.rightPanelWidth)
                    }
                }
                if layout.showTimeline {
                    ResizeHandle(axis: .vertical) { delta in
                        updateLayout { $0.timelineHeight = min(max($0.timelineHeight - delta, 150), 620) }
                    }
                    TimelinePanel(session: session)
                        .frame(height: layout.timelineHeight)
                }
            }
        }
    }
}

struct WorkspaceBar: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(WorkspacePreset.allCases, id: \.self) { preset in
                Button {
                    app.settings.currentWorkspace = preset
                    if preset == .aiClips { app.section = .aiClips }
                    if preset == .captions { app.section = .captions }
                    if preset == .export { app.section = .exports }
                } label: {
                    Text(preset.displayName)
                        .font(.system(size: 11, weight: app.settings.currentWorkspace == preset ? .semibold : .regular))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .foregroundStyle(app.settings.currentWorkspace == preset ? Theme.textPrimary : Theme.textTertiary)
                        .background(RoundedRectangle(cornerRadius: 4).fill(app.settings.currentWorkspace == preset ? Theme.control : .clear))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            let layout = app.settings.layout(for: app.settings.currentWorkspace)
            IconButton(symbol: "sidebar.left", help: "Toggle left panel", isActive: layout.showLeftPanel) { toggle(\.showLeftPanel) }
            IconButton(symbol: "rectangle.bottomthird.inset.filled", help: "Toggle timeline", isActive: layout.showTimeline) { toggle(\.showTimeline) }
            IconButton(symbol: "sidebar.right", help: "Toggle inspector", isActive: layout.showRightPanel) { toggle(\.showRightPanel) }
            IconButton(symbol: "arrow.counterclockwise", help: "Reset workspace") {
                app.settings.workspaces[app.settings.currentWorkspace.rawValue] = nil
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    func toggle(_ keyPath: WritableKeyPath<WorkspaceLayout, Bool>) {
        var l = app.settings.layout(for: app.settings.currentWorkspace)
        l[keyPath: keyPath].toggle()
        app.settings.workspaces[app.settings.currentWorkspace.rawValue] = l
    }
}

/// Thin draggable divider between panels.
struct ResizeHandle: View {
    enum Axis { case horizontal, vertical }
    let axis: Axis
    let onDrag: (Double) -> Void
    @State private var last: CGFloat = 0
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering ? Theme.accent.opacity(0.6) : Theme.divider)
            .frame(width: axis == .horizontal ? 1 : nil, height: axis == .vertical ? 1 : nil)
            .overlay(
                Rectangle().fill(Color.white.opacity(0.001))
                    .frame(width: axis == .horizontal ? 7 : nil, height: axis == .vertical ? 7 : nil)
                    .onHover { inside in
                        hovering = inside
                        if inside { (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() } else { NSCursor.pop() }
                    }
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { value in
                            let current = axis == .horizontal ? value.translation.width : value.translation.height
                            onDrag(Double(current - last))
                            last = current
                        }
                        .onEnded { _ in last = 0 })
            )
    }
}

// MARK: Left panel

struct LeftPanel: View {
    @ObservedObject var session: ProjectSession

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(LeftPanelTab.allCases) { tab in
                    Button { session.leftTab = tab } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tab.symbol).font(.system(size: 12))
                            Text(tab.title).font(.system(size: 9.5, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundStyle(session.leftTab == tab ? Theme.accent : Theme.textTertiary)
                        .background(RoundedRectangle(cornerRadius: 4).fill(session.leftTab == tab ? Theme.control : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Theme.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
            switch session.leftTab {
            case .media: MediaPanel(session: session)
            case .transcript: TranscriptPanel(session: session)
            case .angles: AnglesPanel(session: session)
            case .effects: EffectsPanel(session: session)
            case .ai: AIToolsPanel(session: session)
            }
        }
        .background(Theme.panel)
    }
}

struct MediaPanel: View {
    @ObservedObject var session: ProjectSession
    @EnvironmentObject var app: AppModel
    @State private var query = ""

    var assets: [MediaAsset] {
        session.document.media.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search media", text: $query).textFieldStyle(.roundedBorder).controlSize(.small)
                IconButton(symbol: "plus", help: "Import media (⌘I)") { app.showImportPanel() }
            }
            .padding(8)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                    ForEach(assets) { asset in
                        VStack(alignment: .leading, spacing: 3) {
                            ZStack(alignment: .bottomTrailing) {
                                if asset.kind == .audio {
                                    WaveformStrip(url: session.url(for: asset), sourceRange: TimeRange(start: 0, end: asset.metadata.duration), color: asset.role == .music ? Theme.musicClip : Theme.audioClip)
                                        .background(Theme.well)
                                } else {
                                    ThumbnailView(url: session.url(for: asset), time: min(3, asset.metadata.duration / 3), maxWidth: 220)
                                }
                                Text(Timecode.short(asset.metadata.duration)).font(.system(size: 9, weight: .semibold).monospacedDigit())
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(RoundedRectangle(cornerRadius: 3).fill(.black.opacity(0.6))).foregroundStyle(.white)
                                    .padding(4)
                            }
                            .frame(height: 62)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            HStack(spacing: 3) {
                                Image(systemName: asset.role.symbolName).font(.system(size: 8)).foregroundStyle(Theme.textTertiary)
                                Text(asset.name).font(.system(size: 10)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                            }
                        }
                        .draggable(asset.id.uuidString)
                        .onTapGesture(count: 2) { session.placeAsset(asset.id) }
                        .contextMenu {
                            Button("Add at Playhead") { session.placeAsset(asset.id) }
                            Button("Analyze") { session.analyze(assetID: asset.id) }
                        }
                        .help("Double-click or drag onto the timeline")
                    }
                }
                .padding(8)
            }
        }
    }
}

struct EffectsPanel: View {
    @ObservedObject var session: ProjectSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Effects")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], spacing: 6) {
                    ForEach(EffectKind.allCases, id: \.self) { kind in
                        Button { apply(kind) } label: {
                            VStack(spacing: 4) {
                                Image(systemName: kind.symbolName).font(.system(size: 15))
                                Text(kind.displayName).font(.system(size: 10)).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(Theme.textSecondary)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.control))
                        }
                        .buttonStyle(.plain)
                        .help("Apply to the selected clip")
                    }
                }
                SectionLabel(text: "Transitions")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], spacing: 6) {
                    ForEach(TransitionKind.allCases.filter { $0 != .cut }, id: \.self) { kind in
                        Button { applyTransition(kind) } label: {
                            Text(kind.displayName).font(.system(size: 10.5, weight: .medium))
                                .frame(maxWidth: .infinity, minHeight: 30)
                                .foregroundStyle(Theme.textSecondary)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.control))
                        }
                        .buttonStyle(.plain)
                        .help("Adds as the selected clip's in-transition")
                    }
                }
                Text(session.selectedClipIDs.isEmpty ? "Select a clip on the timeline first." : "Effects are non-destructive — tweak or remove them in the Inspector.")
                    .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            }
            .padding(10)
        }
    }

    func apply(_ kind: EffectKind) {
        let ids = session.selectedClipIDs
        guard !ids.isEmpty else { return }
        session.editTimeline("Add \(kind.displayName)") { t in
            for id in ids { t.updateClip(id: id) { $0.effects.append(EffectInstance(kind: kind)) } }
        }
    }

    func applyTransition(_ kind: TransitionKind) {
        let ids = session.selectedClipIDs
        guard !ids.isEmpty else { return }
        session.editTimeline("Add \(kind.displayName)") { t in
            for id in ids { t.updateClip(id: id) { $0.transitionIn = ClipTransition(kind: kind) } }
        }
    }
}

struct AIToolsPanel: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    @State private var options = EntertainmentOptions()
    @State private var silence: SilencePreset = .balanced

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Card(padding: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("Make More Entertaining").font(.pulseHeadline); Spacer(); AIBadge() }
                        ToggleRow(label: "Jump cuts (remove dead air)", isOn: $options.jumpCuts)
                        if options.jumpCuts {
                            Picker("", selection: $options.silencePreset) {
                                ForEach(SilencePreset.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                            .pickerStyle(.segmented).labelsHidden()
                            Text(options.silencePreset.summary).font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                        }
                        ToggleRow(label: "Remove um / uh / repeats", isOn: $options.removeFillers)
                        ToggleRow(label: "Punch-ins on emphasis", isOn: $options.punchIns)
                        ToggleRow(label: "Reaction zooms", isOn: $options.reactionZooms)
                        ToggleRow(label: "Caption emphasis", isOn: $options.captionEmphasis)
                        ToggleRow(label: "Sound effects (your library)", isOn: $options.soundEffects)
                        ToggleRow(label: "Music bed (your library)", isOn: $options.music)
                        ToggleRow(label: "Soft in/out transitions", isOn: $options.transitions)
                        Button { session.makeMoreEntertaining(options: options) } label: { Label("Apply", systemImage: "wand.and.stars").frame(maxWidth: .infinity) }
                            .buttonStyle(.pulseAI)
                    }
                }
                Card(padding: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Silence Removal").font(.pulseHeadline)
                        Picker("", selection: $silence) {
                            ForEach(SilencePreset.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        Text(silence.summary).font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                        Button("Remove Silences") { removeSilences() }.buttonStyle(.pulse(.secondary, compact: true))
                        Text("Removed sections are listed in the Inspector — restore any of them.").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                    }
                }
                Card(padding: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Framing").font(.pulseHeadline)
                        ForEach([LayoutPreset.splitScreen, .facecamCorner, .circleFacecam, .facecamDominant, .fullFrame, .dynamic], id: \.self) { preset in
                            Button { session.applyLayout(preset) } label: { Label(preset.displayName, systemImage: preset.symbolName).frame(maxWidth: .infinity, alignment: .leading) }
                                .buttonStyle(.pulse(session.activeTimeline?.layout == preset ? .primary : .ghost, compact: true))
                        }
                    }
                }
                Card(padding: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Undo anything").font(.pulseHeadline)
                        Button("Remove All AI Edits") { session.stripAI() }.buttonStyle(.pulse(.ghost, compact: true))
                        Text("Every AI action is a normal, undoable edit (⌘Z).").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .padding(10)
        }
    }

    func removeSilences() {
        guard let timeline = session.activeTimeline, let assetID = timeline.origin?.assetID ?? timeline.assetIDs.first else { return }
        let analysis = session.analyses[assetID]
        let preset = silence
        var total = 0
        session.editTimeline("Remove Silences") { t in
            var cuts: [TimeRange] = []
            for range in t.allClips.filter({ $0.assetID == assetID }).map(\.sourceRange).merged() {
                cuts += SilenceDetector.detect(audio: analysis?.audio, transcript: analysis?.transcript, in: range, preset: preset)
            }
            total = cuts.count
            if !cuts.isEmpty { t.removeSourceRanges(cuts, assetID: assetID, reason: .silence, aiGenerated: true) }
        }
        app.toast(total == 0 ? "No silences found" : "Removed \(total) silences")
    }
}
