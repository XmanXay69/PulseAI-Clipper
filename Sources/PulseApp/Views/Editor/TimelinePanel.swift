import PulseCore
import PulseEngine
import SwiftUI

enum TimelineMetrics {
    static let headerWidth: CGFloat = 158
    static let rulerHeight: CGFloat = 26
    static func laneHeight(_ kind: TrackKind) -> CGFloat {
        switch kind {
        case .video: return 58
        case .audio: return 46
        case .text: return 32
        }
    }
}

struct TimelinePanel: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
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
            Divider().frame(height: 16).padding(.horizontal, 4)
            IconButton(symbol: "arrow.uturn.backward", help: session.undoLabel.map { "Undo \($0) (⌘Z)" } ?? "Undo (⌘Z)") { session.undo() }
                .disabled(!session.canUndo)
            IconButton(symbol: "arrow.uturn.forward", help: session.redoLabel.map { "Redo \($0) (⇧⌘Z)" } ?? "Redo (⇧⌘Z)") { session.redo() }
                .disabled(!session.canRedo)
            Divider().frame(height: 16).padding(.horizontal, 4)
            IconButton(symbol: "arrow.right.and.line.vertical.and.arrow.left", help: "Snapping (S)", isActive: app.settings.snapping) { app.settings.snapping.toggle() }
            IconButton(symbol: "rectangle.compress.vertical", help: "Magnetic timeline — deleting closes gaps", isActive: app.settings.magneticTimeline) { app.settings.magneticTimeline.toggle() }
            Spacer()
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
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    func zoomToFit() {
        guard let t = session.activeTimeline, t.duration > 0 else { return }
        let width = (NSApp.keyWindow?.frame.width ?? 1400) - TimelineMetrics.headerWidth - 360
        session.pixelsPerSecond = max(2, min(600, Double(width) / t.duration))
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
            Spacer(minLength: 2)
            if track.kind != .text {
                toggle("eye", "eye.slash", on: !track.isHidden, help: "Show/hide") { t in t.isHidden.toggle() }
                    .opacity(track.kind == .video ? 1 : 0)
                toggle("speaker.wave.2", "speaker.slash", on: !track.isMuted, help: "Mute") { t in t.isMuted.toggle() }
                    .opacity(track.kind == .audio ? 1 : 0)
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

    var pps: CGFloat { CGFloat(session.pixelsPerSecond) }
    var contentWidth: CGFloat { max(CGFloat(max(timeline.duration, playback.duration) + 20) * pps, 900) }

    var body: some View {
        ScrollView(.horizontal) {
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    TimelineRuler(session: session, playback: playback, timeline: timeline, pps: pps, width: contentWidth)
                    ForEach(timeline.tracks) { track in
                        TrackLane(session: session, playback: playback, timeline: timeline, track: track, pps: pps, width: contentWidth)
                    }
                }
                if let a = session.inPoint, let b = session.outPoint, b > a {
                    Rectangle()
                        .fill(Theme.info.opacity(0.08))
                        .frame(width: CGFloat(b - a) * pps)
                        .offset(x: CGFloat(a) * pps)
                        .allowsHitTesting(false)
                }
                // Playhead.
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: 1.5)
                    .offset(x: CGFloat(playback.currentTime) * pps)
                    .allowsHitTesting(false)
            }
            .frame(width: contentWidth, alignment: .topLeading)
        }
        .background(Theme.window)
    }
}

struct TimelineRuler: View {
    @ObservedObject var session: ProjectSession
    @ObservedObject var playback: PlaybackController
    let timeline: Timeline
    let pps: CGFloat
    let width: CGFloat

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
            // Playhead head.
            let px = CGFloat(playback.currentTime) * pps
            var head = Path()
            head.move(to: CGPoint(x: px - 6, y: 0))
            head.addLine(to: CGPoint(x: px + 6, y: 0))
            head.addLine(to: CGPoint(x: px + 6, y: 12))
            head.addLine(to: CGPoint(x: px, y: 20))
            head.addLine(to: CGPoint(x: px - 6, y: 12))
            head.closeSubpath()
            ctx.fill(head, with: .color(Theme.accent))
        }
        .frame(width: width, height: TimelineMetrics.rulerHeight)
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            var t = Double(value.location.x / pps)
            if session.app.settings.snapping {
                t = Timeline.snap(t, to: timeline.snapPoints(), tolerance: Double(6 / pps))
            }
            playback.pause()
            playback.seek(to: max(0, t))
        })
        .help("Drag to scrub")
    }
}

struct TrackLane: View {
    @ObservedObject var session: ProjectSession
    @ObservedObject var playback: PlaybackController
    let timeline: Timeline
    let track: Track
    let pps: CGFloat
    let width: CGFloat

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
            ForEach(track.clips) { clip in
                TimelineClipView(session: session, playback: playback, timeline: timeline, track: track, clip: clip, pps: pps)
            }
        }
        .frame(width: width, height: TimelineMetrics.laneHeight(track.kind), alignment: .topLeading)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
        .opacity(track.isHidden || track.isMuted ? 0.5 : 1)
    }
}

struct TimelineClipView: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    @ObservedObject var playback: PlaybackController
    let timeline: Timeline
    let track: Track
    let clip: TimelineClip
    let pps: CGFloat

    @State private var moveOffset: CGSize = .zero
    @State private var trimLeading: CGFloat = 0
    @State private var trimTrailing: CGFloat = 0
    @State private var hovering = false

    var isSelected: Bool { session.selectedClipIDs.contains(clip.id) }
    var height: CGFloat { TimelineMetrics.laneHeight(track.kind) - 6 }
    var color: Color { Theme.clipColor(for: clip, track: track) }

    var body: some View {
        let x = CGFloat(clip.start) * pps + moveOffset.width + trimLeading
        let w = max(CGFloat(clip.duration) * pps - trimLeading + trimTrailing, 3)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4).fill(color.opacity(clip.isEnabled ? 0.28 : 0.1))
            clipContent(width: w)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            HStack(spacing: 4) {
                if clip.aiGenerated { Image(systemName: "sparkles").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.ai) }
                Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.92)).lineLimit(1)
                if clip.speed != 1 { Text(String(format: "%.2g×", clip.speed)).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.warning) }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(.black.opacity(0.35)))
            .padding(3)
            if isSelected { keyframeMarks(width: w) }
            transitionMarks(width: w)
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(isSelected ? Color.white : color.opacity(0.9), lineWidth: isSelected ? 2 : 1)
            // Trim handles.
            if !track.isLocked {
                trimHandle(leading: true).frame(width: 7, height: height).offset(x: 0)
                trimHandle(leading: false).frame(width: 7, height: height).offset(x: w - 7)
            }
        }
        .frame(width: w, height: height)
        .offset(x: x, y: 3 + moveOffset.height)
        .zIndex(moveOffset == .zero ? 0 : 10)
        .onHover { hovering = $0 }
        .gesture(moveGesture, including: track.isLocked ? .none : .all)
        .simultaneousGesture(SpatialTapGesture().onEnded { value in select(atX: value.location.x) })
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if clip.content.compoundID != nil { session.openCompound(clipID: clip.id) }
        })
        .contextMenu { contextMenu }
        .help(helpText)
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
            if let asset = session.document.asset(id: assetID) {
                if track.kind == .audio {
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
                let lanes = Int((value.translation.height / TimelineMetrics.laneHeight(track.kind)).rounded())
                if lanes != 0, let index = timeline.trackIndex(id: track.id) {
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
        if case .media = clip.content, track.kind == .video {
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
