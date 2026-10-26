import PulseCore
import PulseEngine
import SwiftUI

enum TimelineMetrics {
    static let headerWidth: CGFloat = 172
    static let rulerHeight: CGFloat = 26
    /// Tighter rows for long timelines (#182): set from Settings, or on its own past 300 clips.
    nonisolated(unsafe) static var compact = false

    static func laneHeight(_ kind: TrackKind) -> CGFloat {
        switch kind {
        case .video: return compact ? 40 : 58
        case .audio: return compact ? 30 : 46
        case .text: return compact ? 24 : 32
        }
    }
}

struct TimelinePanel: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    /// Row heights follow Settings → General → Compact tracks, and tighten on their own past 300 clips (#182).
    var compactRows: Bool { app.settings.compactTimeline || (session.activeTimeline?.allClips.count ?? 0) > 300 }
    @ObservedObject var playback: PlaybackController

    init(session: ProjectSession) {
        self.session = session
        self.playback = session.playback
    }

    var body: some View {
        VStack(spacing: 0) {
            TimelineToolbar(session: session, playback: playback)
            if let timeline = session.activeTimeline {
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            Rectangle().fill(Theme.panel).frame(height: TimelineMetrics.rulerHeight)
                                .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
                            ForEach(timeline.tracks) { track in
                                TrackHeader(session: session, track: track)
                            }
                        }
                        .frame(width: TimelineMetrics.headerWidth)
                        Rectangle().fill(Theme.divider).frame(width: 1)
                        TimelineCanvas(session: session, playback: playback, timeline: timeline)
                    }
                }
                .background(Theme.panel)
            } else {
                EmptyStateView(symbol: "timeline.selection", title: "No timeline", message: "Open an AI clip or create a timeline to start editing.")
            }
        }
    }
}

struct TimelineToolbar: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    @ObservedObject var playback: PlaybackController
    @State private var showMarkers = false
    @State private var showSearch = false
    @State private var showPauses = false
    @State private var showNotes = false
    @State private var showHistory = false
    @State private var showReport = false
    @AppStorage("timeline.energyStrip") private var showEnergy = true

    var body: some View {
        HStack(spacing: 4) {
            ForEach(EditTool.allCases, id: \.self) { tool in
                IconButton(symbol: tool.symbol, help: "\(tool.rawValue.capitalized) tool (\(tool.shortcut))", isActive: session.tool == tool) { session.tool = tool }
            }
            Divider().frame(height: 16).padding(.horizontal, 4)
            IconButton(symbol: "scissors.badge.ellipsis", help: "Split at playhead (⌘K)") { session.splitAtPlayhead() }
            IconButton(symbol: "delete.left", help: "Ripple delete (⇧⌫)") { session.deleteSelection(ripple: true) }
            IconButton(symbol: "plus.square.on.square", help: "Duplicate (⌘D)") { session.duplicateSelection() }
            IconButton(symbol: "textformat", help: "Add text (⌥⌘T)") { session.addText() }
            IconButton(symbol: "bookmark", help: "Add marker (M)") { session.addMarker() }
            IconButton(symbol: "list.bullet.rectangle", help: "Markers list", isActive: showMarkers) { showMarkers.toggle() }
                .popover(isPresented: $showMarkers, arrowEdge: .bottom) { MarkersListView(session: session, playback: playback).frame(width: 360) }
            IconButton(symbol: "magnifyingglass", help: "Find on the timeline — a clip, a marker or a word spoken", isActive: showSearch) { showSearch.toggle() }
                .popover(isPresented: $showSearch, arrowEdge: .bottom) { TimelineSearchView(session: session, playback: playback).frame(width: 380) }
            IconButton(symbol: "waveform.badge.minus", help: "Tighten pauses — speed up the gaps between sentences", isActive: showPauses) { showPauses.toggle() }
                .popover(isPresented: $showPauses, arrowEdge: .bottom) { PausesPopover(session: session).frame(width: 320) }
            let progress = NotesChecklist.progress(in: session.document.notes)
            IconButton(symbol: progress.total > 0 && progress.done == progress.total ? "checklist.checked" : "note.text",
                       help: progress.total > 0 ? "Project notes — \(progress.done) of \(progress.total) done" : "Project notes and to-dos", isActive: showNotes) { showNotes.toggle() }
                .popover(isPresented: $showNotes, arrowEdge: .bottom) { ProjectNotesPopover(session: session).frame(width: 360) }
            Divider().frame(height: 16).padding(.horizontal, 4)
            IconButton(symbol: "arrow.uturn.backward", help: session.undoLabel.map { "Undo \($0) (⌘Z)" } ?? "Undo (⌘Z)") { session.undo() }
                .disabled(!session.canUndo)
            IconButton(symbol: "arrow.uturn.forward", help: session.redoLabel.map { "Redo \($0) (⇧⌘Z)" } ?? "Redo (⇧⌘Z)") { session.redo() }
                .disabled(!session.canRedo)
            IconButton(symbol: "clock.arrow.circlepath", help: "History — every edit, click one to jump back there", isActive: showHistory) { showHistory.toggle() }
                .popover(isPresented: $showHistory, arrowEdge: .bottom) { UndoHistoryView(session: session).frame(width: 300) }
            IconButton(symbol: "doc.text.magnifyingglass", help: "Edit report — what was cut, what was added, with jump links", isActive: showReport) { showReport.toggle() }
                .popover(isPresented: $showReport, arrowEdge: .bottom) { EditReportView(session: session, playback: playback).frame(width: 420) }
            IconButton(symbol: TimelineMetrics.compact ? "rectangle.compress.vertical" : "rectangle.expand.vertical", help: "Compact tracks (#182)", isActive: app.settings.compactTimeline) {
                app.settings.compactTimeline.toggle()
                TimelineMetrics.compact = app.settings.compactTimeline || (session.activeTimeline?.allClips.count ?? 0) > 300
            }
            Divider().frame(height: 16).padding(.horizontal, 4)
            IconButton(symbol: "arrow.right.and.line.vertical.and.arrow.left", help: "Snapping (S)", isActive: app.settings.snapping) { app.settings.snapping.toggle() }
            IconButton(symbol: "rectangle.compress.vertical", help: "Magnetic timeline — deleting closes gaps", isActive: app.settings.magneticTimeline) { app.settings.magneticTimeline.toggle() }
            IconButton(symbol: "waveform.path.ecg", help: "Excitement strip on the ruler — where the energy is", isActive: showEnergy) { showEnergy.toggle() }
            Spacer()
            if let timeline = session.activeTimeline {
                let over = timeline.targetDuration.map { timeline.duration > $0 * 1.1 } ?? false
                Text(Timecode.duration(timeline.duration) + (timeline.targetDuration.map { " / \(Timecode.duration($0)) target" } ?? ""))
                    .font(.pulseMono).foregroundStyle(over ? Theme.warning : Theme.textSecondary)
                    .help(timeline.targetDuration.map { "The length this edit was built for: \(Timecode.duration($0))" } ?? "Timeline length")
                    .padding(.trailing, 6)
            }
            Button { session.makeMoreEntertaining() } label: { Label("Make More Entertaining", systemImage: "wand.and.stars") }
                .buttonStyle(.pulse(.ai, compact: true))
                .help("Adds jump cuts, filler removal, punch-ins and caption emphasis — every change stays editable")
            Divider().frame(height: 16).padding(.horizontal, 4)
            Image(systemName: "minus.magnifyingglass").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
            Slider(value: Binding(get: { log(session.pixelsPerSecond) }, set: { session.pixelsPerSecond = exp($0) }), in: log(2)...log(600))
                .controlSize(.mini)
                .frame(width: 110)
            Image(systemName: "plus.magnifyingglass").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
            IconButton(symbol: "arrow.left.and.right.square", help: "Zoom to fit") { zoomToFit() }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Theme.panelRaised)
        .onAppear { TimelineMetrics.compact = app.settings.compactTimeline || (session.activeTimeline?.allClips.count ?? 0) > 300 }
        .onChange(of: app.settings.compactTimeline) { _, on in TimelineMetrics.compact = on || (session.activeTimeline?.allClips.count ?? 0) > 300 }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    func zoomToFit() { session.zoomTimelineToFit() }
}

/// What the edit did (#107): sections with lines you can click to jump to.
struct EditReportView: View {
    @ObservedObject var session: ProjectSession
    @ObservedObject var playback: PlaybackController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader("Edit Report", subtitle: session.activeTimeline?.name ?? "") {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.editReport?.text ?? "", forType: .string)
                }
                .buttonStyle(.pulse(.ghost, compact: true))
            }
            if let report = session.editReport {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(report.sections) { section in
                            VStack(alignment: .leading, spacing: 3) {
                                SectionLabel(text: section.title)
                                ForEach(section.lines) { line in
                                    HStack(alignment: .top, spacing: 6) {
                                        if line.time != nil { Image(systemName: "arrow.turn.down.right").font(.system(size: 9)).foregroundStyle(Theme.ai).padding(.top, 3) }
                                        Text(line.text).font(.pulseCaption).foregroundStyle(line.time == nil ? Theme.textSecondary : Theme.textPrimary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture { if let t = line.time { playback.seek(to: t) } }
                                }
                            }
                        }
                    }
                    .padding(14)
                }
                .frame(maxHeight: 420)
            }
        }
    }
}

/// Every undo step with "jump back to" (#175).
struct UndoHistoryView: View {
    @ObservedObject var session: ProjectSession

    var body: some View {
        let labels = session.undoLabels
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader("History", subtitle: labels.isEmpty ? "No edits yet" : "\(labels.count) steps · newest at the top") { EmptyView() }
            if !labels.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(labels.enumerated().reversed()), id: \.offset) { index, label in
                            let back = labels.count - index
                            HStack(spacing: 8) {
                                Text("\(index + 1)").font(.pulseMono).foregroundStyle(Theme.textTertiary).frame(width: 28, alignment: .trailing)
                                Text(label).font(.pulseCaption).foregroundStyle(Theme.textPrimary).lineLimit(1)
                                Spacer()
                                Text(back == 1 ? "undo" : "back \(back)").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .contentShape(Rectangle())
                            .onTapGesture { session.undo(steps: back) }
                            .help("Undo this and everything after it")
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
    }
}

/// Notes for the project with a checklist (#476): "- [ ] grade the intro" lines become boxes you tick.
struct ProjectNotesPopover: View {
    @ObservedObject var session: ProjectSession
    @State private var draft = ""
    @State private var newItem = ""

    var items: [NotesChecklist.Item] { NotesChecklist.items(in: session.document.notes) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let progress = NotesChecklist.progress(in: session.document.notes)
            PanelHeader("Notes", subtitle: progress.total > 0 ? "\(progress.done) of \(progress.total) done" : "To-dos, links, what to remember") { EmptyView() }
            if !items.isEmpty {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        Toggle(isOn: Binding(get: { item.done }, set: { _ in toggle(item) })) {
                            Text(item.text).font(.pulseCaption).foregroundStyle(item.done ? Theme.textTertiary : Theme.textPrimary).strikethrough(item.done)
                        }
                        .toggleStyle(.checkbox)
                        .padding(.horizontal, 12).padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 6)
            }
            HStack(spacing: 6) {
                TextField("Add a to-do", text: $newItem, onCommit: addItem).textFieldStyle(.roundedBorder).font(.pulseCaption)
                Button("Add") { addItem() }.buttonStyle(.pulse(.secondary, compact: true)).disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12).padding(.bottom, 8)
            TextEditor(text: $draft)
                .font(.pulseCaption)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 140)
                .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.well))
                .padding(.horizontal, 12).padding(.bottom, 12)
                .onAppear { draft = session.document.notes }
                .onChange(of: session.document.notes) { _, new in if new != draft { draft = new } }
                .onChange(of: draft) { _, new in
                    guard new != session.document.notes else { return }
                    session.edit("Edit Notes", coalesce: "notes") { $0.notes = new }
                }
        }
    }

    func toggle(_ item: NotesChecklist.Item) {
        let updated = NotesChecklist.toggle(session.document.notes, line: item.line)
        session.edit(item.done ? "Untick To-do" : "Tick To-do") { $0.notes = updated }
        draft = updated
    }

    func addItem() {
        let updated = NotesChecklist.add(newItem, to: session.document.notes)
        guard updated != session.document.notes else { return }
        session.edit("Add To-do") { $0.notes = updated }
        draft = updated
        newItem = ""
    }
}

/// Find a clip by name, a marker, or a word spoken, and jump there (#174).
struct TimelineSearchView: View {
    @ObservedObject var session: ProjectSession
    @ObservedObject var playback: PlaybackController
    @State private var query = ""

    var hits: [TimelineHit] { session.activeTimeline?.find(query) ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader("Find", subtitle: query.count < 2 ? "A clip name, a marker, or words that were said" : "\(hits.count) found · click to jump") { EmptyView() }
            TextField("Search the timeline…", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12).padding(.vertical, 8)
            if query.count >= 2, hits.isEmpty {
                Text("Nothing on this timeline matches.").font(.pulseCaption).foregroundStyle(Theme.textTertiary).padding(14)
            } else if !hits.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(hits) { hit in
                            HStack(spacing: 8) {
                                Image(systemName: hit.kind.symbolName).font(.system(size: 11)).foregroundStyle(Theme.ai).frame(width: 16)
                                Text(Timecode.short(hit.time)).font(.pulseMono).foregroundStyle(Theme.textTertiary).frame(width: 56, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(hit.title).font(.pulseCaption).foregroundStyle(Theme.textPrimary).lineLimit(1)
                                    if !hit.detail.isEmpty { Text(hit.detail).font(.pulseMicro).foregroundStyle(Theme.textTertiary).lineLimit(1) }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .contentShape(Rectangle())
                            .onTapGesture { playback.seek(to: hit.time) }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
    }
}

/// Speed up the pauses between sentences with a live readout of what it would save (#82).
struct PausesPopover: View {
    @ObservedObject var session: ProjectSession
    @State private var minimum: Seconds = 1.2

    var body: some View {
        let estimate = session.pauseEstimate(minimum: minimum)
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader("Tighten Pauses", subtitle: "Gaps between sentences play at 1.6× — speech is never touched") { EmptyView() }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Pauses longer than").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(String(format: "%.1f s", minimum)).font(.pulseMono).foregroundStyle(Theme.textPrimary)
                }
                Slider(value: $minimum, in: 0.6...3, step: 0.1)
                Text(estimate.pauses == 0 ? "No pauses that long on this timeline" : "\(estimate.pauses) pause\(estimate.pauses == 1 ? "" : "s") · \(String(format: "%.1f", estimate.saved)) s shorter")
                    .font(.pulseCaption).foregroundStyle(estimate.pauses == 0 ? Theme.textTertiary : Theme.ai)
                HStack {
                    Spacer()
                    Button { session.tightenPauses(minimum: minimum) } label: { Label("Tighten", systemImage: "waveform.badge.minus") }
                        .buttonStyle(.pulse(.ai, compact: true))
                        .disabled(estimate.pauses == 0)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 12)
        }
    }
}

/// Every marker on the timeline: click to jump, rename inline, delete.
struct MarkersListView: View {
    @ObservedObject var session: ProjectSession
    @ObservedObject var playback: PlaybackController
    @State private var renaming: UUID?
    @State private var newName = ""

    var markers: [Marker] { (session.activeTimeline?.markers ?? []).sorted { $0.time < $1.time } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader("Markers", subtitle: markers.isEmpty ? "None yet — press M at the playhead" : "\(markers.count) · click to jump") {
                Button("Add") { session.addMarker() }.buttonStyle(.pulse(.ghost, compact: true))
            }
            if markers.isEmpty {
                Text("Chapters from Edit My VOD and your own markers show up here.").font(.pulseCaption).foregroundStyle(Theme.textTertiary).padding(14)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(markers) { marker in
                            HStack(spacing: 8) {
                                Circle().fill(Color(marker.color.rgba)).frame(width: 7, height: 7)
                                Text(Timecode.short(marker.time)).font(.pulseMono).foregroundStyle(Theme.textTertiary).frame(width: 52, alignment: .leading)
                                if renaming == marker.id {
                                    TextField("Name", text: $newName, onCommit: { rename(marker) })
                                        .textFieldStyle(.plain).font(.pulseBody).foregroundStyle(Theme.textPrimary)
                                } else {
                                    Text(marker.name).font(.pulseBody).foregroundStyle(Theme.textPrimary).lineLimit(1)
                                    if !marker.note.isEmpty { Text(marker.note).font(.pulseMicro).foregroundStyle(Theme.textTertiary).lineLimit(1) }
                                }
                                Spacer(minLength: 4)
                                IconButton(symbol: "pencil", help: "Rename", size: 20) { newName = marker.name; renaming = marker.id }
                                IconButton(symbol: "trash", help: "Delete", size: 20) { delete(marker) }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .contentShape(Rectangle())
                            .onTapGesture { playback.seek(to: marker.time) }
                            .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
                        }
                    }
                }
                .frame(maxHeight: 380)
            }
        }
        .background(Theme.panel)
    }

    func rename(_ marker: Marker) {
        let name = newName.trimmingCharacters(in: .whitespaces)
        renaming = nil
        guard !name.isEmpty, name != marker.name else { return }
        session.editTimeline("Rename Marker") { t in
            if let i = t.markers.firstIndex(where: { $0.id == marker.id }) { t.markers[i].name = name }
        }
    }

    func delete(_ marker: Marker) {
        session.editTimeline("Delete Marker") { t in t.markers.removeAll { $0.id == marker.id } }
    }
}

struct TrackHeader: View {
    @ObservedObject var session: ProjectSession
    let track: Track

    var body: some View {
        HStack(spacing: 6) {
            Text(track.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(track.name)
            Spacer(minLength: 2)
            if track.kind == .video {
                toggle("eye", "eye.slash", on: !track.isHidden, help: "Show/hide") { t in t.isHidden.toggle() }
            } else if track.kind == .audio {
                toggle("speaker.wave.2", "speaker.slash", on: !track.isMuted, help: "Mute") { t in t.isMuted.toggle() }
            }
            if track.kind == .audio {
                Button { update { $0.isSolo.toggle() } } label: {
                    Text("S").font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 16)
                        .background(RoundedRectangle(cornerRadius: 3).fill(track.isSolo ? Theme.warning : Theme.control))
                        .foregroundStyle(track.isSolo ? .black : Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Solo")
            }
            toggle("lock.open", "lock.fill", on: !track.isLocked, help: "Lock") { t in t.isLocked.toggle() }
        }
        .padding(.horizontal, 10)
        .frame(height: TimelineMetrics.laneHeight(track.kind))
        .background(Theme.panelRaised)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5).fill(kindColor.opacity(track.isHidden || track.isMuted ? 0.3 : 0.9)).frame(width: 3).padding(.vertical, 6)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
        .contextMenu {
            Button("Add Video Track") { session.editTimeline("Add Track") { $0.addTrack(kind: .video) } }
            Button("Add Audio Track") { session.editTimeline("Add Track") { $0.addTrack(kind: .audio) } }
            Button("Add Text Track") { session.editTimeline("Add Track") { $0.addTrack(kind: .text) } }
            Divider()
            Button("Delete Track", role: .destructive) {
                let id = track.id
                session.editTimeline("Delete Track") { $0.removeTrack(id: id) }
            }
            .disabled(!track.clips.isEmpty)
        }
    }

    var kindColor: Color {
        switch track.kind {
        case .video: return Theme.videoClip
        case .audio: return Theme.audioClip
        case .text: return Theme.textClip
        }
    }

    func update(_ body: @escaping (inout Track) -> Void) {
        let id = track.id
        session.editTimeline("Track Setting") { t in
            if let i = t.trackIndex(id: id) { body(&t.tracks[i]) }
        }
    }

    func toggle(_ onSymbol: String, _ offSymbol: String, on: Bool, help: String, _ body: @escaping (inout Track) -> Void) -> some View {
        Button { update(body) } label: {
            Image(systemName: on ? onSymbol : offSymbol)
                .font(.system(size: 10))
                .foregroundStyle(on ? Theme.textTertiary : Theme.warning)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Ruler + lanes + playhead.
struct TimelineCanvas: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    @ObservedObject var playback: PlaybackController
    let timeline: Timeline

    /// The visible stretch of the timeline (seconds), widened by a margin and snapped to coarse steps so
    /// scrolling doesn't re-render the lanes on every pixel.
    @State private var window: ClosedRange<Double> = 0...120
    @State private var scrollX: CGFloat = 0
    @State private var viewportWidth: CGFloat = 1200

    var pps: CGFloat { CGFloat(session.pixelsPerSecond) }
    var contentWidth: CGFloat { max(CGFloat(max(timeline.duration, playback.duration) + 20) * pps, 900) }

    var body: some View {
        ScrollView(.horizontal) {
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    TimelineRuler(session: session, playback: playback, timeline: timeline, pps: pps, width: contentWidth)
                    ForEach(timeline.tracks) { track in
                        TrackLane(session: session, playback: playback, track: track, pps: pps, width: contentWidth, window: window)
                    }
                }
                if let a = session.inPoint, let b = session.outPoint, b > a {
                    Rectangle()
                        .fill(Theme.info.opacity(0.08))
                        .frame(width: CGFloat(b - a) * pps)
                        .offset(x: CGFloat(a) * pps)
                        .allowsHitTesting(false)
                }
                // Playhead: the only part of the timeline that redraws while playing.
                PlayheadLine(clock: playback.clock, pps: pps)
            }
            .frame(width: contentWidth, alignment: .topLeading)
            .background(GeometryReader { geo in
                Color.clear.preference(key: TimelineScrollKey.self, value: -geo.frame(in: .named("timelineScroll")).minX)
            })
        }
        .coordinateSpace(name: "timelineScroll")
        .background(GeometryReader { geo in Color.clear.preference(key: TimelineViewportKey.self, value: geo.size.width) })
        .onPreferenceChange(TimelineScrollKey.self) { x in scrollX = x; updateWindow() }
        .onPreferenceChange(TimelineViewportKey.self) { w in viewportWidth = w; updateWindow() }
        .onChange(of: session.pixelsPerSecond) { _, _ in updateWindow() }
        .onAppear { updateWindow() }
        .background(Theme.window)
    }

    private func updateWindow() {
        guard pps > 0 else { return }
        let visible = Double(viewportWidth / pps)
        let step = max(visible / 2, 1)
        // Snap the window to half-viewport steps, with a full viewport of margin either side.
        let lo = (Double(max(0, scrollX) / pps) / step).rounded(.down) * step - visible
        let hi = lo + visible * 3 + step
        let next = max(0, lo)...max(1, hi)
        if next != window { window = next }
    }
}

private struct TimelineScrollKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct TimelineViewportKey: PreferenceKey {
    static let defaultValue: CGFloat = 1200
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct PlayheadLine: View {
    @ObservedObject var clock: PlayheadClock
    let pps: CGFloat

    var body: some View {
        Rectangle()
            .fill(Theme.accent)
            .frame(width: 1.5)
            .shadow(color: Theme.accent.opacity(0.7), radius: 3)
            .offset(x: CGFloat(clock.time) * pps)
            .allowsHitTesting(false)
    }
}

struct PlayheadHead: View {
    @ObservedObject var clock: PlayheadClock
    let pps: CGFloat

    var body: some View {
        Path { head in
            head.move(to: CGPoint(x: -6, y: 0))
            head.addLine(to: CGPoint(x: 6, y: 0))
            head.addLine(to: CGPoint(x: 6, y: 12))
            head.addLine(to: CGPoint(x: 0, y: 20))
            head.addLine(to: CGPoint(x: -6, y: 12))
            head.closeSubpath()
        }
        .fill(Theme.accentGradient)
        .frame(width: 12, height: 20)
        .shadow(color: Theme.accent.opacity(0.6), radius: 4, y: 1)
        .offset(x: CGFloat(clock.time) * pps - 6)
        .allowsHitTesting(false)
    }
}

struct TimelineRuler: View {
    let session: ProjectSession
    let playback: PlaybackController
    let timeline: Timeline
    let pps: CGFloat
    let width: CGFloat
    @AppStorage("timeline.energyStrip") private var showEnergy = true

    var body: some View {
        Canvas { ctx, size in
            // Pick a tick spacing that keeps labels ~90 px apart.
            let steps: [Double] = [0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1800, 3600]
            let major = steps.first { CGFloat($0) * pps >= 90 } ?? 3600
            let minor = major / 5
            var t = 0.0
            while CGFloat(t) * pps < size.width {
                let x = CGFloat(t) * pps
                let isMajor = abs(t / major - (t / major).rounded()) < 0.001
                ctx.fill(Path(CGRect(x: x, y: isMajor ? 12 : 19, width: 1, height: isMajor ? 14 : 7)), with: .color(Theme.textTertiary.opacity(isMajor ? 0.9 : 0.5)))
                if isMajor {
                    let label = major < 1 ? String(format: "%.2fs", t) : Timecode.short(t)
                    ctx.draw(Text(label).font(.system(size: 9, design: .monospaced)).foregroundColor(Theme.textTertiary), at: CGPoint(x: x + 3, y: 7), anchor: .leading)
                }
                t += minor
            }
            for marker in timeline.markers {
                let x = CGFloat(marker.time) * pps
                var p = Path()
                p.move(to: CGPoint(x: x - 5, y: 0))
                p.addLine(to: CGPoint(x: x + 5, y: 0))
                p.addLine(to: CGPoint(x: x + 5, y: 8))
                p.addLine(to: CGPoint(x: x, y: 13))
                p.addLine(to: CGPoint(x: x - 5, y: 8))
                p.closeSubpath()
                ctx.fill(p, with: .color(Color(marker.color.rgba)))
            }
            // In → out range (I / O) as a band on the ruler (#199).
            if let a = session.inPoint, let b = session.outPoint, b > a {
                let x0 = CGFloat(a) * pps, x1 = CGFloat(b) * pps
                ctx.fill(Path(CGRect(x: x0, y: 0, width: x1 - x0, height: size.height)), with: .color(Theme.info.opacity(0.16)))
                ctx.fill(Path(CGRect(x: x0, y: 0, width: 1.5, height: size.height)), with: .color(Theme.info))
                ctx.fill(Path(CGRect(x: x1 - 1.5, y: 0, width: 1.5, height: size.height)), with: .color(Theme.info))
            }
            // Excitement strip along the bottom: the recording's energy, mapped through the cuts.
            if showEnergy, let v = timeline.tracks.first(where: { $0.kind == .video }) {
                let bottom = size.height - 1
                let h: CGFloat = 9
                for clip in v.clips where clip.isEnabled && clip.role != .graphic {
                    guard let assetID = clip.content.assetID, let signals = session.energySignal(for: assetID), signals.step > 0 else { continue }
                    let x0 = CGFloat(clip.start) * pps, x1 = CGFloat(clip.end) * pps
                    guard x1 > 0, x0 < size.width else { continue }
                    var path = Path()
                    path.move(to: CGPoint(x: x0, y: bottom))
                    var x = max(x0, 0)
                    while x <= min(x1, size.width) {
                        let sourceT = clip.sourceIn + Double((x - x0) / pps) * clip.speed
                        let i = Int(sourceT / signals.step)
                        let e = i >= 0 && i < signals.excitement.count ? CGFloat(signals.excitement[i]) : 0
                        path.addLine(to: CGPoint(x: x, y: bottom - h * min(max(e, 0), 1)))
                        x += 2
                    }
                    path.addLine(to: CGPoint(x: min(x1, size.width), y: bottom))
                    path.closeSubpath()
                    ctx.fill(path, with: .linearGradient(Gradient(colors: [Theme.accent.opacity(0.75), Theme.ai.opacity(0.35)]),
                                                         startPoint: CGPoint(x: 0, y: bottom - h), endPoint: CGPoint(x: 0, y: bottom)))
                }
            }
            // Layout morphs: a violet bar spanning each morph on the ruler's bottom edge.
            for change in timeline.layoutChanges {
                let x0 = CGFloat(change.time) * pps
                let w = max(CGFloat(change.duration) * pps, 3)
                ctx.fill(Path(roundedRect: CGRect(x: x0, y: 22, width: w, height: 5), cornerRadius: 2), with: .color(Theme.ai))
            }
        }
        .frame(width: width, height: TimelineMetrics.rulerHeight)
        .overlay(alignment: .topLeading) { PlayheadHead(clock: playback.clock, pps: pps) }
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                playback.pause()
                playback.scrub(to: max(0, time(at: value.location.x)))
            }
            .onEnded { value in
                // Land exactly on the frame under the mouse.
                playback.seek(to: max(0, time(at: value.location.x)))
            })
        .help("Drag to scrub")
    }

    private func time(at x: CGFloat) -> Double {
        var t = Double(x / pps)
        if session.app.settings.snapping {
            t = Timeline.snap(t, to: timeline.snapPoints(), tolerance: Double(6 / pps))
        }
        return t
    }
}

struct TrackLane: View {
    @ObservedObject var session: ProjectSession
    let playback: PlaybackController
    let track: Track
    let pps: CGFloat
    let width: CGFloat
    /// Only clips overlapping this stretch (seconds) are built.
    let window: ClosedRange<Double>

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(track.isLocked ? Theme.panel.opacity(0.6) : Theme.window)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    session.selectedClipIDs = []
                    playback.seek(to: Double(location.x / pps))
                }
                .dropDestination(for: String.self) { items, location in
                    guard let first = items.first, let id = UUID(uuidString: first) else { return false }
                    session.placeAsset(id, at: max(0, Double(location.x / pps)), trackID: track.id)
                    return true
                }
            ForEach(track.clips.filter { $0.end >= window.lowerBound && $0.start <= window.upperBound }) { clip in
                TimelineClipView(session: session, playback: playback, trackID: track.id, trackKind: track.kind, trackLocked: track.isLocked,
                                 clip: clip, pps: pps, isSelected: session.selectedClipIDs.contains(clip.id),
                                 asset: clip.assetID.flatMap { session.document.asset(id: $0) },
                                 color: Theme.clipColor(for: clip, track: track))
                    .equatable()
            }
        }
        .frame(width: width, height: TimelineMetrics.laneHeight(track.kind), alignment: .topLeading)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
        .opacity(track.isHidden || track.isMuted ? 0.5 : 1)
    }
}

/// One clip block. Deliberately doesn't observe the session or the player: the lane passes in
/// everything it shows, and `Equatable` lets SwiftUI skip clips that didn't change.
struct TimelineClipView: View, Equatable {
    let session: ProjectSession
    let playback: PlaybackController
    let trackID: UUID
    let trackKind: TrackKind
    let trackLocked: Bool
    let clip: TimelineClip
    let pps: CGFloat
    let isSelected: Bool
    let asset: MediaAsset?
    let color: Color

    nonisolated static func == (a: TimelineClipView, b: TimelineClipView) -> Bool {
        a.clip == b.clip && a.pps == b.pps && a.isSelected == b.isSelected && a.trackLocked == b.trackLocked
            && a.trackKind == b.trackKind && a.asset?.id == b.asset?.id && a.asset?.path == b.asset?.path && a.color == b.color
    }

    var app: AppModel { session.app }
    /// The live timeline, read when a gesture needs it (not stored, so clips don't re-render on every edit).
    var timeline: Timeline { session.activeTimeline ?? Timeline(name: "", canvas: .landscape1080, tracks: []) }

    @State private var moveOffset: CGSize = .zero
    @State private var trimLeading: CGFloat = 0
    @State private var trimTrailing: CGFloat = 0
    @State private var hovering = false

    var height: CGFloat { TimelineMetrics.laneHeight(trackKind) - 6 }

    var body: some View {
        let x = CGFloat(clip.start) * pps + moveOffset.width + trimLeading
        let w = max(CGFloat(clip.duration) * pps - trimLeading + trimTrailing, 3)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(LinearGradient(colors: [color.opacity(clip.isEnabled ? 0.44 : 0.14), color.opacity(clip.isEnabled ? 0.22 : 0.08)],
                                     startPoint: .top, endPoint: .bottom))
            clipContent(width: w)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            HStack(spacing: 4) {
                if clip.aiGenerated { Image(systemName: "sparkles").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.ai) }
                Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.94)).lineLimit(1)
                if clip.speed != 1 { Text(String(format: "%.2g×", clip.speed)).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.warning) }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(.black.opacity(0.42)))
            .padding(3)
            if isSelected { keyframeMarks(width: w) }
            transitionMarks(width: w)
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.2), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(isSelected ? Color.white : (hovering ? color : color.opacity(0.75)), lineWidth: isSelected ? 1.5 : 1)
            // Trim handles.
            if !trackLocked {
                trimHandle(leading: true).frame(width: 7, height: height).offset(x: 0)
                trimHandle(leading: false).frame(width: 7, height: height).offset(x: w - 7)
            }
        }
        .frame(width: w, height: height)
        .shadow(color: clipShadow, radius: 6, y: moveOffset == .zero ? 0 : 4)
        .offset(x: x, y: 3 + moveOffset.height)
        .zIndex(moveOffset == .zero ? 0 : 10)
        .onHover { hovering = $0 }
        .gesture(moveGesture, including: trackLocked ? .none : .all)
        .simultaneousGesture(SpatialTapGesture().onEnded { value in select(atX: value.location.x) })
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if clip.content.compoundID != nil { session.openCompound(clipID: clip.id) }
        })
        .contextMenu { contextMenu }
        .help(helpText)
    }

    /// A soft white glow when selected; a drop shadow while being dragged.
    var clipShadow: Color {
        if isSelected { return Color.white.opacity(0.22) }
        return moveOffset == .zero ? Color.clear : Color.black.opacity(0.5)
    }

    var label: String {
        switch clip.content {
        case .text(let e): return e.text
        case .solid: return "Color"
        case .media, .compound: return clip.name
        }
    }

    var helpText: String {
        "\(clip.name) · \(Timecode.short(clip.start)) → \(Timecode.short(clip.end))" + (clip.aiGenerated ? " · Created by PULSE AI (editable)" : "")
    }

    @ViewBuilder
    func clipContent(width: CGFloat) -> some View {
        switch clip.content {
        case .media(let assetID):
            if let asset, asset.id == assetID {
                if trackKind == .audio {
                    WaveformStrip(url: session.url(for: asset), sourceRange: clip.sourceRange, color: color)
                        .padding(.top, 14)
                } else if asset.kind == .video || asset.kind == .image {
                    FilmstripStrip(url: session.url(for: asset), sourceRange: clip.sourceRange, width: width, height: height)
                        .opacity(0.8)
                }
            }
        case .text:
            LinearGradient(colors: [color.opacity(0.5), color.opacity(0.25)], startPoint: .top, endPoint: .bottom)
        case .solid(let c):
            Color(c)
        case .compound:
            ZStack(alignment: .leading) {
                LinearGradient(colors: [color.opacity(0.55), color.opacity(0.3)], startPoint: .top, endPoint: .bottom)
                HStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.up.fill").font(.system(size: 11))
                    Text("Compound").font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.75))
                .padding(.leading, 6)
                .padding(.top, 12)
            }
        }
    }

    func keyframeMarks(width: CGFloat) -> some View {
        let t = clip.transform
        let all = [t.positionX, t.positionY, t.scale, t.rotation, t.opacity, t.zoom, t.panX, t.panY].flatMap(\.keyframes) + clip.audio.volume.keyframes
        return ZStack(alignment: .bottomLeading) {
            ForEach(all) { k in
                Image(systemName: "diamond.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(k.aiGenerated ? Theme.ai : Theme.warning)
                    .offset(x: CGFloat(k.time) * pps - 3.5 - trimLeading, y: -3)
            }
        }
        .frame(width: width, height: height, alignment: .bottomLeading)
        .allowsHitTesting(false)
    }

    func transitionMarks(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if let tin = clip.transitionIn {
                Path { p in
                    p.move(to: .zero)
                    p.addLine(to: CGPoint(x: min(CGFloat(tin.duration) * pps, width / 2), y: 0))
                    p.addLine(to: CGPoint(x: 0, y: height))
                    p.closeSubpath()
                }
                .fill(Color.white.opacity(0.25))
            }
            if let tout = clip.transitionOut {
                Path { p in
                    let tw = min(CGFloat(tout.duration) * pps, width / 2)
                    p.move(to: CGPoint(x: width, y: 0))
                    p.addLine(to: CGPoint(x: width - tw, y: 0))
                    p.addLine(to: CGPoint(x: width, y: height))
                    p.closeSubpath()
                }
                .fill(Color.white.opacity(0.25))
            }
        }
        .allowsHitTesting(false)
    }

    func trimHandle(leading: Bool) -> some View {
        Rectangle()
            .fill(hovering ? Color.white.opacity(0.35) : Color.clear)
            .contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        var dx = value.translation.width
                        if app.settings.snapping {
                            let edgeTime = Double(leading ? clip.start : clip.end) + Double(dx / pps)
                            let snapped = Timeline.snap(edgeTime, to: timeline.snapPoints(excluding: Set(timeline.linkedClipIDs(of: clip.id))) + [playback.currentTime], tolerance: Double(8 / pps))
                            dx = CGFloat(snapped - (leading ? clip.start : clip.end)) * pps
                        }
                        if leading { trimLeading = dx } else { trimTrailing = dx }
                    }
                    .onEnded { _ in
                        let id = clip.id
                        let mediaDuration = clip.assetID.flatMap { session.document.asset(id: $0)?.metadata.duration }
                            ?? clip.content.compoundID.flatMap { session.document.timeline(id: $0)?.duration }
                        if leading {
                            let newStart = clip.start + Double(trimLeading / pps)
                            session.editTimeline("Trim Start") { try $0.trimStart(clipID: id, to: newStart) }
                        } else {
                            let newEnd = clip.end + Double(trimTrailing / pps)
                            session.editTimeline("Trim End") { try $0.trimEnd(clipID: id, to: newEnd, mediaDuration: mediaDuration) }
                        }
                        trimLeading = 0
                        trimTrailing = 0
                    }
            )
    }

    var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if session.tool == .blade { return }
                if !isSelected { session.selectedClipIDs = [clip.id] }
                var dx = value.translation.width
                if app.settings.snapping {
                    let proposed = clip.start + Double(dx / pps)
                    let points = timeline.snapPoints(excluding: Set(timeline.linkedClipIDs(of: clip.id))) + [playback.currentTime]
                    let snappedStart = Timeline.snap(proposed, to: points, tolerance: Double(8 / pps))
                    let snappedEnd = Timeline.snap(proposed + clip.duration, to: points, tolerance: Double(8 / pps)) - clip.duration
                    let s = abs(snappedStart - proposed) <= abs(snappedEnd - proposed) ? snappedStart : snappedEnd
                    dx = CGFloat(s - clip.start) * pps
                }
                moveOffset = CGSize(width: dx, height: value.translation.height)
            }
            .onEnded { value in
                defer { moveOffset = .zero }
                guard session.tool != .blade else { return }
                let newStart = max(0, clip.start + Double(moveOffset.width / pps))
                // Vertical drag → move to a neighbouring compatible track.
                var destination: UUID?
                let lanes = Int((value.translation.height / TimelineMetrics.laneHeight(trackKind)).rounded())
                if lanes != 0, let index = timeline.trackIndex(id: trackID) {
                    let target = index + lanes
                    if timeline.tracks.indices.contains(target), timeline.tracks[target].kind.accepts(clip.content) {
                        destination = timeline.tracks[target].id
                    }
                }
                guard abs(newStart - clip.start) > 1e-4 || destination != nil else { return }
                let id = clip.id
                session.editTimeline("Move Clip") { try $0.move(clipID: id, toStart: newStart, toTrack: destination) }
            }
    }

    func select(atX x: CGFloat) {
        if session.tool == .blade {
            // Blade: cut exactly where the clip was clicked (linked clips are cut too).
            let id = clip.id
            let t = clip.start + Double(x / pps)
            session.editTimeline("Blade") { try $0.split(at: t, clipIDs: [id]) }
            return
        }
        if NSEvent.modifierFlags.contains(.shift) || NSEvent.modifierFlags.contains(.command) {
            if isSelected { session.selectedClipIDs.remove(clip.id) } else { session.selectedClipIDs.insert(clip.id) }
        } else {
            session.selectedClipIDs = [clip.id]
        }
    }

    @ViewBuilder
    var contextMenu: some View {
        Button("Split at Playhead") { session.selectedClipIDs = [clip.id]; session.splitAtPlayhead() }
        Button("Delete") { session.selectedClipIDs = [clip.id]; session.deleteSelection(ripple: false) }
        Button("Ripple Delete") { session.selectedClipIDs = [clip.id]; session.deleteSelection(ripple: true) }
        Button("Duplicate") { session.selectedClipIDs = [clip.id]; session.duplicateSelection() }
        Divider()
        if clip.content.compoundID != nil {
            Button("Open Compound Clip") { session.openCompound(clipID: clip.id) }
            Button("Break Apart Compound Clip") { session.breakApartCompound(clipID: clip.id) }
        } else {
            Button("New Compound Clip") {
                if !session.selectedClipIDs.contains(clip.id) { session.selectedClipIDs = [clip.id] }
                session.createCompoundClip()
            }
        }
        Divider()
        Menu("Speed") {
            ForEach([0.25, 0.5, 0.75, 1, 1.25, 1.5, 2], id: \.self) { s in
                Button(String(format: "%.2g×", s)) { session.selectedClipIDs = [clip.id]; session.setSpeed(s) }
            }
        }
        if clip.linkGroup != nil {
            Button("Detach Audio / Unlink") { session.selectedClipIDs = [clip.id]; session.detachAudio() }
        }
        Button(clip.isEnabled ? "Disable Clip" : "Enable Clip") {
            session.editClip(clip.id, "Toggle Clip") { $0.isEnabled.toggle() }
        }
        Divider()
        if case .media = clip.content, trackKind == .video {
            Button("Auto Reframe (follow face)") { autoReframe() }
            Button("Remove AI Keyframes") { session.editClip(clip.id, "Remove AI Keyframes") { $0.transform.removeAIKeyframes() } }
        }
        Button("Add Marker at Playhead") { session.addMarker() }
    }

    func autoReframe() {
        guard let assetID = clip.assetID, let faces = session.analyses[assetID]?.visual?.faces, !faces.isEmpty else {
            app.presentMessage(title: "No faces detected", message: "Analyze the recording first so PULSE knows where faces are.")
            return
        }
        session.editClip(clip.id, "Auto Reframe") { c in AutoReframer.applyFaceTracking(to: &c, faces: faces) }
    }
}

/// Audio waveform drawn from cached peaks.
struct WaveformStrip: View {
    let url: URL
    let sourceRange: TimeRange
    var color: Color = Theme.audioClip
    @State private var peaks: [Float] = []

    var body: some View {
        Canvas { ctx, size in
            guard !peaks.isEmpty else { return }
            let buckets = max(1, Int(size.width / 2))
            let values = WaveformService.downsample(peaks, range: sourceRange, buckets: buckets)
            let mid = size.height / 2
            var path = Path()
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) * size.width / CGFloat(buckets)
                let h = max(1, CGFloat(sqrt(v)) * size.height * 0.95)
                path.addRect(CGRect(x: x, y: mid - h / 2, width: max(1, size.width / CGFloat(buckets) - 0.5), height: h))
            }
            ctx.fill(path, with: .color(color.opacity(0.9)))
        }
        .task(id: url) { peaks = await WaveformService.shared.peaks(for: url) }
    }
}

/// Row of thumbnails across a clip.
struct FilmstripStrip: View {
    let url: URL
    let sourceRange: TimeRange
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let frameWidth = max(height * 16 / 9, 40)
        let count = max(1, min(40, Int(ceil(width / frameWidth))))
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                ThumbnailView(url: url, time: sourceRange.start + sourceRange.duration * (Double(i) + 0.5) / Double(count), maxWidth: 160)
                    .frame(width: frameWidth, height: height)
            }
        }
        .frame(width: width, height: height, alignment: .leading)
        .clipped()
    }
}
