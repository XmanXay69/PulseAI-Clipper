import AVFoundation
import PulseCore
import PulseEngine
import SwiftUI

/// AVPlayerLayer host (the custom compositor renders into it, so preview == export).
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerLayerNSView {
        let view = PlayerLayerNSView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: PlayerLayerNSView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}

final class PlayerLayerNSView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

enum ViewerZoom: String, CaseIterable {
    case fit = "Fit", p50 = "50%", p100 = "100%", p200 = "200%"

    func scale(canvas: CGSize, available: CGSize) -> CGFloat {
        switch self {
        case .fit: return min(available.width / max(canvas.width, 1), available.height / max(canvas.height, 1))
        case .p50: return 0.5
        case .p100: return 1
        case .p200: return 2
        }
    }
}

struct ViewerView: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    @ObservedObject var playback: PlaybackController
    @State private var zoom: ViewerZoom = .fit
    @AppStorage("viewer.grid") private var showGrid = false
    @AppStorage("viewer.scopes") private var showScopes = false
    @State private var fullscreen = false
    @State private var showCaptionEdit = false

    init(session: ProjectSession) {
        self.session = session
        self.playback = session.playback
    }

    var canvas: CanvasSettings { session.activeTimeline?.canvas ?? .vertical1080 }

    var body: some View {
        VStack(spacing: 0) {
            viewerHeader
            GeometryReader { geo in
                let available = CGSize(width: geo.size.width - 32, height: geo.size.height - 32)
                let canvasSize = CGSize(width: canvas.width, height: canvas.height)
                let scale = zoom.scale(canvas: canvasSize, available: available)
                let frameSize = CGSize(width: canvasSize.width * scale, height: canvasSize.height * scale)
                ScrollView([.horizontal, .vertical], showsIndicators: zoom != .fit) {
                    ZStack {
                        PlayerView(player: playback.player)
                        // The last picture, dimmed, while the composition rebuilds — no black flash (#204).
                        if playback.isBuilding, let frame = playback.lastFrame {
                            Image(decorative: frame, scale: 1).resizable().aspectRatio(contentMode: .fit).opacity(0.7)
                                .allowsHitTesting(false)
                        }
                        if app.settings.showSafeAreas, canvas.aspect < 1 {
                            SafeAreaOverlay(platform: session.document.overrides.safeAreaPlatform ?? app.settings.safeAreaPlatform, chrome: app.settings.showPlatformChrome)
                        }
                        if showGrid { GridOverlay() }
                        CanvasHandlesOverlay(session: session, playback: playback, frameSize: frameSize)
                        if playback.isBuilding {
                            ProgressView().controlSize(.small).padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        } else if playback.isEnhancingAudio {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 5) {
                                    Image(systemName: "waveform")
                                    Text("Leveling audio")
                                    Spacer(minLength: 6)
                                    Text("\(Int((playback.enhanceProgress * 100).rounded()))%").monospacedDigit()
                                }
                                ProgressView(value: playback.enhanceProgress).progressViewStyle(.linear).tint(Theme.accent).controlSize(.mini)
                            }
                            .font(.pulseMicro).foregroundStyle(.white.opacity(0.9))
                            .frame(width: 150)
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 7).fill(.black.opacity(0.6)))
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .allowsHitTesting(false)
                            .help("You can play and edit right away — the original audio plays until the leveled audio is ready")
                        }
                        if session.speedEdit {
                            SpeedEditHUD(session: session)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .padding(10)
                        }
                        if showScopes {
                            ScopesPanel(playback: playback)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                                .padding(8)
                        }
                        if !playback.missingAssetIDs.isEmpty {
                            MediaOfflineBanner(session: session, missing: playback.missingAssetIDs)
                        } else if let error = playback.lastError {
                            Label("Preview couldn't be built: \(error)", systemImage: "exclamationmark.triangle.fill")
                                .font(.pulseCaption)
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.75)))
                                .padding(12)
                        }
                    }
                    .frame(width: frameSize.width, height: frameSize.height)
                    .overlay(Rectangle().strokeBorder(Theme.borderStrong, lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 20)
                    .frame(width: max(geo.size.width, frameSize.width + 32), height: max(geo.size.height, frameSize.height + 32))
                }
                .background(Theme.well)
            }
            TransportBar(session: session, playback: playback)
        }
        .background(Theme.well)
    }

    var viewerHeader: some View {
        HStack(spacing: 8) {
            if session.isInsideCompound {
                Button { session.exitCompound() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.pulse(.ghost, compact: true))
                    .help("Back to the parent timeline")
                let crumbs = session.compoundBreadcrumb
                ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                    if index > 0 { Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Theme.textTertiary) }
                    if index < crumbs.count - 1 {
                        Button(crumb.name) { session.exitCompound(toLevel: index) }
                            .buttonStyle(.plain).font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    } else {
                        Label(crumb.name, systemImage: "square.stack.3d.up.fill").font(.pulseHeadline).foregroundStyle(Theme.compoundClip)
                    }
                }
            } else if let t = session.activeTimeline {
                Menu {
                    ForEach(session.document.timelines) { timeline in
                        Button(timeline.name) { session.open(timelineID: timeline.id) }
                    }
                    Divider()
                    Button("New Vertical Timeline") { session.newTimeline(canvas: .vertical1080, name: "Vertical Edit") }
                    Button("New Landscape Timeline") { session.newTimeline(canvas: .landscape1080, name: "Landscape Edit") }
                } label: {
                    Text(t.name).font(.pulseHeadline).lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .frame(minWidth: 60, maxWidth: 260, alignment: .leading)
                .layoutPriority(1)
                if t.hasAIContent { AIBadge(label: "AI edit").fixedSize() }
                if session.effectivePlaybackQuality == .full {
                    TagChip(text: "= EXPORT", color: Theme.textTertiary).fixedSize()
                        .help("The viewer runs the same renderer as the export — captions, colour and layouts match the file exactly (#197)")
                }
                IconButton(symbol: "grid", help: "Grid, center lines and thirds", isActive: showGrid) { showGrid.toggle() }
                IconButton(symbol: "waveform.path", help: "Scopes — luma waveform and vectorscope of the frame (#310)", isActive: showScopes) { showScopes.toggle() }
                IconButton(symbol: "crop", help: "Crop tool (#192): drag the selected layer's picture to pan it, the corner to zoom in, double-click to reset",
                           isActive: session.canvasTool == .crop) { session.canvasTool = session.canvasTool == .crop ? .transform : .crop }
                if t.captions?.isEnabled == true {
                    IconButton(symbol: "character.cursor.ibeam", help: "Edit the caption on screen (#231)", isActive: showCaptionEdit) {
                        playback.pause()
                        showCaptionEdit.toggle()
                    }
                    .popover(isPresented: $showCaptionEdit, arrowEdge: .bottom) {
                        CaptionQuickEdit(session: session, time: playback.currentTime)
                    }
                }
                if let review = session.activeReview {
                    Button { session.selectedClipIDs = [] } label: { PerformanceBadge(prediction: review.prediction) }
                        .buttonStyle(.plain).fixedSize()
                }
            }
            Spacer(minLength: 4)
            PlaybackQualityMenu(session: session)
            // Full readout when there's room, shorter when the viewer is narrow, nothing when it's very narrow.
            ViewThatFits(in: .horizontal) {
                Text("\(canvas.width)×\(canvas.height) · \(canvas.aspectLabel) · \(Int(canvas.frameRate)) fps")
                Text("\(canvas.aspectLabel) · \(Int(canvas.frameRate)) fps")
                Color.clear.frame(width: 0, height: 0)
            }
            .font(.pulseMono).foregroundStyle(Theme.textTertiary).lineLimit(1)
            Picker("", selection: $zoom) {
                ForEach(ViewerZoom.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(width: 80)
            Menu {
                Toggle("Show Safe Areas", isOn: $app.settings.showSafeAreas)
                Toggle("Show Platform Buttons & Caption", isOn: $app.settings.showPlatformChrome)
                Picker("Platform", selection: $app.settings.safeAreaPlatform) {
                    ForEach(SafeAreaPlatform.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            } label: { Image(systemName: "rectangle.dashed") }
                .menuStyle(.borderlessButton)
                .frame(width: 34)
                .help("Safe-area guides for TikTok, Shorts and Reels")
            IconButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Full screen") { toggleFullscreen() }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    func toggleFullscreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }
}

/// Shaded platform UI zones (captions, buttons) for vertical formats.
struct SafeAreaOverlay: View {
    let platform: SafeAreaPlatform
    /// Draw the platform's own buttons, username and caption block too (#67).
    var chrome = false

    var body: some View {
        GeometryReader { geo in
            let i = platform.insets
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                if chrome { PlatformChrome(platform: platform, width: w, height: h) }
                Rectangle().fill(Color.black.opacity(0.28)).frame(width: w, height: h * i.top)
                Rectangle().fill(Color.black.opacity(0.28)).frame(width: w, height: h * i.bottom).offset(y: h * (1 - i.bottom))
                Rectangle().fill(Color.black.opacity(0.18)).frame(width: w * i.right, height: h * (1 - i.top - i.bottom)).offset(x: w * (1 - i.right), y: h * i.top)
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .frame(width: w * (1 - i.left - i.right), height: h * (1 - i.top - i.bottom))
                    .offset(x: w * i.left, y: h * i.top)
                Text(platform.displayName + " safe area")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(4)
                    .offset(x: w * i.left, y: h * i.top)
                VStack(spacing: 10) {
                    ForEach(["heart.fill", "bubble.right.fill", "arrowshape.turn.up.right.fill"], id: \.self) { s in
                        Image(systemName: s).font(.system(size: max(10, w * 0.05))).foregroundStyle(.white.opacity(0.35))
                    }
                }
                .offset(x: w * (1 - i.right * 0.75), y: h * 0.55)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Selection box + drag/scale handles for the selected visual layer (move the facecam, resize titles…).
struct CanvasHandlesOverlay: View {
    @ObservedObject var session: ProjectSession
    @ObservedObject var playback: PlaybackController
    let frameSize: CGSize
    @State private var dragStart: (x: Double, y: Double, scale: Double)?

    var body: some View { ClockObserving(clock: playback.clock) { clockedBody } }

    @ViewBuilder var clockedBody: some View {
        GeometryReader { _ in
            if let timeline = session.activeTimeline, session.selectedClipIDs.count == 1, let id = session.selectedClipIDs.first,
               let clip = timeline.clip(id: id), let rect = layerRect(clip, timeline: timeline) {
                let local = playback.currentTime - clip.start
                if session.canvasTool == .crop, clip.content.assetID != nil {
                    cropBody(clip: clip, local: local, rect: rect)
                } else {
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .strokeBorder(Theme.accent, lineWidth: 1.5)
                        .background(Color.white.opacity(0.001))
                        .frame(width: rect.width, height: rect.height)
                        .rotationEffect(.degrees(clip.transform.rotation.value(at: local)))
                        .offset(x: rect.minX, y: rect.minY)
                        .gesture(moveGesture(clip: clip, local: local))
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .offset(x: rect.maxX - 5.5, y: rect.maxY - 5.5)
                        .gesture(scaleGesture(clip: clip, local: local, rect: rect))
                        .help("Drag to scale")
                    // Rotation knob above the box (#191): drag around the centre; ⇧ snaps to 15°; double-click resets.
                    Circle()
                        .fill(Theme.panelRaised)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Theme.accent, lineWidth: 1.5))
                        .overlay(Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 6, weight: .bold)).foregroundStyle(Theme.accent))
                        .offset(x: rect.midX - 5.5, y: rect.minY - 22)
                        .gesture(rotateGesture(clip: clip, local: local, rect: rect))
                        .onTapGesture(count: 2) {
                            session.editClip(clip.id, "Reset Rotation", coalesce: nil) { c in
                                if c.transform.rotation.isAnimated { c.transform.rotation.setKeyframe(at: local, value: 0) } else { c.transform.rotation.value = 0 }
                            }
                        }
                        .help("Drag to rotate (⇧ snaps to 15°); double-click to reset")
                }
                .frame(width: frameSize.width, height: frameSize.height, alignment: .topLeading)
                }
            }
        }
    }

    /// Crop mode (#192): the layer's frame stays put; dragging inside pans the picture (`panX`/`panY`), the
    /// corner knob zooms into it (`zoom`), a double-click shows the whole picture again.
    @ViewBuilder func cropBody(clip: TimelineClip, local: Seconds, rect: CGRect) -> some View {
        let zoom = clip.transform.zoom.value(at: local)
        ZStack(alignment: .topLeading) {
            Rectangle()
                .strokeBorder(Theme.warning, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .background(Color.white.opacity(0.001))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .gesture(panGesture(clip: clip, local: local, rect: rect))
                .onTapGesture(count: 2) {
                    session.editClip(clip.id, "Reset Crop", coalesce: nil) { c in
                        if c.transform.zoom.isAnimated { c.transform.zoom.setKeyframe(at: local, value: 1) } else { c.transform.zoom.value = 1 }
                        if c.transform.panX.isAnimated { c.transform.panX.setKeyframe(at: local, value: 0) } else { c.transform.panX.value = 0 }
                        if c.transform.panY.isAnimated { c.transform.panY.setKeyframe(at: local, value: 0) } else { c.transform.panY.value = 0 }
                    }
                }
                .help("Drag to pan the picture inside its frame; double-click to show all of it")
            Text(String(format: "CROP · %.0f%%", zoom * 100))
                .font(.system(size: 9, weight: .bold)).monospacedDigit()
                .foregroundStyle(.black)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Capsule().fill(Theme.warning))
                .offset(x: rect.minX + 6, y: rect.minY + 6)
                .allowsHitTesting(false)
            Circle()
                .fill(Theme.warning)
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                .offset(x: rect.maxX - 5.5, y: rect.maxY - 5.5)
                .gesture(zoomGesture(clip: clip, local: local, rect: rect))
                .help("Drag to zoom into the picture")
        }
        .frame(width: frameSize.width, height: frameSize.height, alignment: .topLeading)
    }

    func panGesture(clip: TimelineClip, local: Seconds, rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = (clip.transform.panX.value(at: local), clip.transform.panY.value(at: local), clip.transform.zoom.value(at: local))
                }
                guard let start = dragStart else { return }
                // Moving the picture right shows more of its left: the window moves the other way, in source units.
                let window = clip.transform.crop(at: local).scaled(by: 1 / max(start.scale, 0.05))
                let nx = start.x - Double(value.translation.width / max(rect.width, 1)) * window.width
                let ny = start.y - Double(value.translation.height / max(rect.height, 1)) * window.height
                session.editClip(clip.id, "Pan Crop", coalesce: "pan-\(clip.id)") { c in
                    if c.transform.panX.isAnimated { c.transform.panX.setKeyframe(at: local, value: nx) } else { c.transform.panX.value = nx }
                    if c.transform.panY.isAnimated { c.transform.panY.setKeyframe(at: local, value: ny) } else { c.transform.panY.value = ny }
                }
            }
            .onEnded { _ in
                dragStart = nil
                session.commitCoalescing()
            }
    }

    func zoomGesture(clip: TimelineClip, local: Seconds, rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = (clip.transform.panX.value(at: local), clip.transform.panY.value(at: local), clip.transform.zoom.value(at: local))
                }
                guard let start = dragStart else { return }
                let diagonal = max(hypot(rect.width, rect.height), 1)
                let delta = (value.translation.width + value.translation.height) / 2
                let newZoom = min(8, max(1, start.scale * Double(1 + delta / (diagonal / 2))))
                session.editClip(clip.id, "Zoom Crop", coalesce: "zoomcrop-\(clip.id)") { c in
                    if c.transform.zoom.isAnimated { c.transform.zoom.setKeyframe(at: local, value: newZoom) } else { c.transform.zoom.value = newZoom }
                }
            }
            .onEnded { _ in
                dragStart = nil
                session.commitCoalescing()
            }
    }

    func layerRect(_ clip: TimelineClip, timeline: Timeline) -> CGRect? {
        let local = playback.currentTime - clip.start
        guard clip.timelineRange.contains(playback.currentTime) || session.selectedClipIDs.contains(clip.id) else { return nil }
        let canvas = timeline.canvas.size
        let k = frameSize.width / CGFloat(canvas.width)
        switch clip.content {
        case .media(let assetID):
            guard let asset = session.document.asset(id: assetID), asset.kind != .audio else { return nil }
            var sourceSize = asset.metadata.size
            if sourceSize.isEmpty { sourceSize = Size2(1920, 1080) }
            let g = LayerGeometry.resolve(clip.transform, at: local, sourceSize: sourceSize, canvasSize: canvas)
            let f = g.frame
            return CGRect(x: f.x * k, y: f.y * k, width: f.width * k, height: f.height * k)
        case .text(let element):
            let s = clip.transform.scale.value(at: local)
            let w = element.maxWidth * canvas.width * 0.8 * s
            let h = element.style.fontSize * 1.4 * s * Double(max(1, element.text.count / 18 + 1))
            let cx = clip.transform.positionX.value(at: local) * canvas.width
            let cy = clip.transform.positionY.value(at: local) * canvas.height
            return CGRect(x: (cx - w / 2) * k, y: (cy - h / 2) * k, width: w * k, height: h * k)
        case .solid:
            return nil
        case .compound:
            let g = LayerGeometry.resolve(clip.transform, at: local, sourceSize: canvas, canvasSize: canvas)
            let f = g.frame
            return CGRect(x: f.x * k, y: f.y * k, width: f.width * k, height: f.height * k)
        }
    }

    func moveGesture(clip: TimelineClip, local: Seconds) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = (clip.transform.positionX.value(at: local), clip.transform.positionY.value(at: local), clip.transform.scale.value(at: local))
                }
                guard let start = dragStart else { return }
                let dx = Double(value.translation.width / frameSize.width)
                let dy = Double(value.translation.height / frameSize.height)
                var nx = start.x + dx
                var ny = start.y + dy
                // Snap to centre lines.
                if abs(nx - 0.5) < 0.012 { nx = 0.5 }
                if abs(ny - 0.5) < 0.012 { ny = 0.5 }
                session.editClip(clip.id, "Move Layer", coalesce: "move-\(clip.id)") { c in
                    if c.transform.positionX.isAnimated { c.transform.positionX.setKeyframe(at: local, value: nx) } else { c.transform.positionX.value = nx }
                    if c.transform.positionY.isAnimated { c.transform.positionY.setKeyframe(at: local, value: ny) } else { c.transform.positionY.value = ny }
                }
            }
            .onEnded { _ in
                dragStart = nil
                session.commitCoalescing()
            }
    }

    func rotateGesture(clip: TimelineClip, local: Seconds, rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let centre = CGPoint(x: rect.midX, y: rect.midY)
                let knob = CGPoint(x: rect.midX, y: rect.minY - 16)
                let point = CGPoint(x: knob.x + value.translation.width, y: knob.y + value.translation.height)
                var degrees = Double(atan2(point.x - centre.x, centre.y - point.y)) * 180 / .pi
                if NSEvent.modifierFlags.contains(.shift) { degrees = (degrees / 15).rounded() * 15 }
                if abs(degrees) < 1.5 { degrees = 0 }
                session.editClip(clip.id, "Rotate Layer", coalesce: "rotate-\(clip.id)") { c in
                    if c.transform.rotation.isAnimated { c.transform.rotation.setKeyframe(at: local, value: degrees) } else { c.transform.rotation.value = degrees }
                }
            }
            .onEnded { _ in session.commitCoalescing() }
    }

    func scaleGesture(clip: TimelineClip, local: Seconds, rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = (clip.transform.positionX.value(at: local), clip.transform.positionY.value(at: local), clip.transform.scale.value(at: local))
                }
                guard let start = dragStart else { return }
                let diagonal = max(hypot(rect.width, rect.height), 1)
                let delta = (value.translation.width + value.translation.height) / 2
                let newScale = max(0.05, start.scale * Double(1 + delta / (diagonal / 2)))
                session.editClip(clip.id, "Scale Layer", coalesce: "scale-\(clip.id)") { c in
                    if c.transform.scale.isAnimated { c.transform.scale.setKeyframe(at: local, value: newScale) } else { c.transform.scale.value = newScale }
                }
            }
            .onEnded { _ in
                dragStart = nil
                session.commitCoalescing()
            }
    }
}

struct MediaOfflineBanner: View {
    @ObservedObject var session: ProjectSession
    let missing: Set<UUID>

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 22)).foregroundStyle(Theme.warning)
            Text("Media Offline").font(.pulseHeadline).foregroundStyle(.white)
            Text(missing.compactMap { session.document.asset(id: $0)?.name }.joined(separator: ", "))
                .font(.pulseCaption).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
            Text("The file was moved, renamed or is on a disconnected drive. Relink it from the Media page.")
                .font(.pulseMicro).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center).frame(maxWidth: 240)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.75)))
    }
}

struct TransportBar: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    @ObservedObject var playback: PlaybackController
    @State private var editingTimecode = false
    @State private var typedTimecode = ""
    @FocusState private var timecodeFocused: Bool

    /// "2×", "8×" or "−4×" while shuttling; nothing at normal speed or when paused (#420).
    private var shuttleReadout: String? {
        let rate = playback.playbackRate
        guard rate != 0, rate != 1 else { return nil }
        let magnitude = abs(rate)
        let text = magnitude == magnitude.rounded() ? String(Int(magnitude)) : String(format: "%.2g", magnitude)
        return (rate < 0 ? "−" : "") + text + "×"
    }

    var body: some View {
        HStack(spacing: 8) {
            if editingTimecode {
                TextField("mm:ss", text: $typedTimecode)
                    .textFieldStyle(.plain)
                    .font(.pulseTimecode)
                    .foregroundStyle(Theme.textPrimary)
                    .focused($timecodeFocused)
                    .onSubmit { commitTimecode() }
                    .onExitCommand { editingTimecode = false }
                    .padding(.horizontal, 8)
                    .frame(minWidth: 120, maxWidth: 136, alignment: .leading)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.well))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.accent))
                    .onAppear { timecodeFocused = true }
            } else {
                ClockObserving(clock: playback.clock) {
                    Text(Timecode.display(playback.currentTime, fps: playback.frameRate, style: app.settings.timecodeStyle))
                        .font(.pulseTimecode)
                        .foregroundStyle(Theme.accent)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .frame(minWidth: 120, maxWidth: 136, alignment: .leading)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.well))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
                        .contentShape(Rectangle())
                        .onTapGesture { typedTimecode = ""; editingTimecode = true }
                        .help("Click to type a time (12:34, 1:02:03 or 12:34:15 for frames) and press return")
                }
            }
            Spacer(minLength: 4)
            IconButton(symbol: "backward.end.fill", help: "Go to start (Home)") { playback.goToStart() }
            IconButton(symbol: "backward.frame.fill", help: "Previous frame (←)") { playback.step(frames: -1); app.tick() }
            Button { playback.togglePlayPause() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radius)
                            .fill(playback.isPlaying ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.control))
                    )
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.edgeHighlight, lineWidth: 1))
                    .shadow(color: playback.isPlaying ? Theme.accent.opacity(0.35) : .clear, radius: 8, y: 2)
                    .foregroundStyle(playback.isPlaying ? Color.white : Theme.textPrimary)
            }
            .buttonStyle(.plain)
            .help("Play / Pause (Space)")
            IconButton(symbol: "forward.frame.fill", help: "Next frame (→)") { playback.step(frames: 1); app.tick() }
            IconButton(symbol: "forward.end.fill", help: "Go to end (End)") { playback.goToEnd() }
            IconButton(symbol: "repeat", help: "Loop", isActive: playback.loopEnabled && playback.loopRange == nil) { playback.loopRange = nil; playback.loopEnabled.toggle() }
            IconButton(symbol: "repeat.1", help: "Loop in → out", shortcut: app.settings.shortcuts.combo(for: .loopInOut),
                       isActive: playback.loopEnabled && playback.loopRange != nil) { session.toggleLoopInOut() }
            MasterMeter(session: session, playback: playback).padding(.leading, 4)
            if let speed = shuttleReadout {
                TagChip(text: speed, color: Theme.accent, symbol: playback.playbackRate < 0 ? "backward.fill" : "forward.fill")
                    .help("Shuttle speed — J/L to go faster, K to stop")
                    .transition(.opacity)
            }
            Spacer(minLength: 4)
            // In/out chips drop out first when the viewer is narrow; the duration always shows.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    if let i = session.inPoint { TagChip(text: "IN \(Timecode.short(i))", color: Theme.info) }
                    if let o = session.outPoint { TagChip(text: "OUT \(Timecode.short(o))", color: Theme.info) }
                    duration
                }
                duration
            }
            .frame(minWidth: 90, maxWidth: 220, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Theme.panel)
        .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    /// "12:34", "1:02:03", "12:34:15" (frames) or plain seconds.
    func commitTimecode() {
        defer { editingTimecode = false }
        let parts = typedTimecode.trimmingCharacters(in: .whitespaces).split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return }
        let numbers = parts.compactMap { $0 }
        var seconds: Seconds
        switch numbers.count {
        case 1: seconds = numbers[0]
        case 2: seconds = numbers[0] * 60 + numbers[1]
        case 3:
            // h:mm:ss when the first part is small and the whole is under 10 h; otherwise mm:ss:ff.
            if numbers[0] * 3600 + numbers[1] * 60 + numbers[2] <= playback.duration + 1 && numbers[2] < 60 && numbers[0] < 10 {
                seconds = numbers[0] * 3600 + numbers[1] * 60 + numbers[2]
            } else {
                seconds = numbers[0] * 60 + numbers[1] + numbers[2] / max(playback.frameRate, 1)
            }
        default: seconds = numbers[0] * 3600 + numbers[1] * 60 + numbers[2] + numbers[3] / max(playback.frameRate, 1)
        }
        playback.seek(to: min(max(0, seconds), playback.duration))
    }

    var duration: some View {
        Text(Timecode.display(playback.duration, fps: playback.frameRate, style: app.settings.timecodeStyle))
            .font(.pulseMono)
            .foregroundStyle(Theme.textTertiary)
            .fixedSize()
    }
}

/// Thirds, center lines and a center mark over the picture (#190).
struct GridOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            let line = Color.white.opacity(0.35)
            for f in [1.0 / 3, 2.0 / 3] {
                ctx.stroke(Path { p in p.move(to: CGPoint(x: size.width * f, y: 0)); p.addLine(to: CGPoint(x: size.width * f, y: size.height)) }, with: .color(line), lineWidth: 1)
                ctx.stroke(Path { p in p.move(to: CGPoint(x: 0, y: size.height * f)); p.addLine(to: CGPoint(x: size.width, y: size.height * f)) }, with: .color(line), lineWidth: 1)
            }
            let center = Color.white.opacity(0.6)
            ctx.stroke(Path { p in p.move(to: CGPoint(x: size.width / 2, y: 0)); p.addLine(to: CGPoint(x: size.width / 2, y: size.height)) }, with: .color(center.opacity(0.5)), lineWidth: 0.5)
            ctx.stroke(Path { p in p.move(to: CGPoint(x: 0, y: size.height / 2)); p.addLine(to: CGPoint(x: size.width, y: size.height / 2)) }, with: .color(center.opacity(0.5)), lineWidth: 0.5)
            ctx.stroke(Path(ellipseIn: CGRect(x: size.width / 2 - 6, y: size.height / 2 - 6, width: 12, height: 12)), with: .color(center), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// A mock of the platform's UI (#67): the right-hand button column, the username and caption lines at the
/// bottom-left, the top tabs and the bottom bar — so you see what your short looks like in the feed.
struct PlatformChrome: View {
    let platform: SafeAreaPlatform
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let w = width, h = height
        let i = platform.insets
        ZStack(alignment: .topLeading) {
            // Top tabs.
            HStack(spacing: w * 0.06) {
                Text(platform == .youtubeShorts ? "Shorts" : "Following").font(.system(size: max(9, w * 0.035), weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                Text(platform == .youtubeShorts ? "" : "For You").font(.system(size: max(9, w * 0.035), weight: .bold)).foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: w)
            .offset(y: h * max(0.03, i.top * 0.45))
            // Right-hand column: avatar, like, comment, share, sound.
            VStack(spacing: h * 0.028) {
                Circle().fill(.white.opacity(0.35)).frame(width: w * 0.11, height: w * 0.11)
                ForEach(["heart.fill", "ellipsis.bubble.fill", "bookmark.fill", "arrowshape.turn.up.right.fill"], id: \.self) { s in
                    VStack(spacing: 2) {
                        Image(systemName: s).font(.system(size: max(10, w * 0.07))).foregroundStyle(.white.opacity(0.85))
                        Text("12K").font(.system(size: max(7, w * 0.025), weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                    }
                }
                RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.35)).frame(width: w * 0.09, height: w * 0.09)
            }
            .frame(width: w * i.right)
            .offset(x: w * (1 - i.right), y: h * (1 - i.bottom) - h * 0.42)
            // Username + caption + sound ticker.
            VStack(alignment: .leading, spacing: 5) {
                Text("@yourhandle").font(.system(size: max(9, w * 0.038), weight: .bold)).foregroundStyle(.white.opacity(0.95))
                RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.55)).frame(width: w * 0.55, height: max(6, w * 0.028))
                RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.4)).frame(width: w * 0.38, height: max(6, w * 0.028))
                HStack(spacing: 4) {
                    Image(systemName: "music.note").font(.system(size: max(8, w * 0.03))).foregroundStyle(.white.opacity(0.8))
                    RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.4)).frame(width: w * 0.3, height: max(5, w * 0.024))
                }
            }
            .offset(x: w * max(0.03, i.left + 0.02), y: h * (1 - i.bottom) - h * 0.17)
            // Bottom bar.
            HStack {
                ForEach(0..<5, id: \.self) { k in
                    if k == 2 {
                        RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.9)).frame(width: w * 0.12, height: max(14, h * 0.028))
                    } else {
                        RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.5)).frame(width: w * 0.07, height: max(8, h * 0.014))
                    }
                    if k < 4 { Spacer() }
                }
            }
            .padding(.horizontal, w * 0.07)
            .frame(width: w)
            .offset(y: h * (1 - i.bottom * 0.45))
        }
        .allowsHitTesting(false)
    }
}


/// Viewer render quality (#187): Full / ½ / ¼, with "auto" when PULSE stepped it down itself.
struct PlaybackQualityMenu: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession

    var body: some View {
        let quality = session.effectivePlaybackQuality
        let dropped = session.playbackQualityOverride != nil
        Menu {
            ForEach(PlaybackQuality.allCases, id: \.self) { q in
                Button {
                    session.setPlaybackQuality(q)
                } label: {
                    if q == quality { Label(q.longName, systemImage: "checkmark") } else { Text(q.longName) }
                }
            }
            Divider()
            Toggle("Drop a step when playback stutters", isOn: $app.settings.autoPlaybackQuality)
            Toggle("Use proxies for playback", isOn: Binding(get: { app.settings.proxy.useProxiesForPlayback }, set: { on in
                app.settings.proxy.useProxiesForPlayback = on
                session.reloadPlayback(debounce: 0)
            }))
            if dropped {
                Button("Back to \(app.settings.playbackQuality.longName.lowercased())") { session.setPlaybackQuality(app.settings.playbackQuality) }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: quality == .full ? "sparkles.tv" : "tv").font(.system(size: 10, weight: .semibold))
                Text((quality == .full ? "Full" : quality.displayName + (dropped ? " auto" : "")) + (app.settings.proxy.useProxiesForPlayback ? " · proxy" : ""))
                    .font(.pulseMicro).monospacedDigit()
            }
            .foregroundStyle(dropped ? Theme.warning : Theme.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(dropped ? "Playback was falling behind, so the viewer renders at \(quality.longName.lowercased()). Exports always render in full."
                      : "Viewer render size — lower is lighter on the GPU; exports always render in full")
    }
}

/// The viewer in its own window (#205): the same player as the editor, so it stays in sync.
struct DetachedViewerWindow: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        Group {
            if let session = app.session {
                DetachedViewerContent(session: session)
            } else {
                Text("Open a project and its viewer shows here")
                    .font(.pulseBody).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.well)
    }
}

struct DetachedViewerContent: View {
    @ObservedObject var session: ProjectSession
    @ObservedObject var playback: PlaybackController

    init(session: ProjectSession) {
        self.session = session
        self.playback = session.playback
    }

    var body: some View {
        let canvas = session.activeTimeline?.canvas ?? .vertical1080
        VStack(spacing: 0) {
            PlayerView(player: playback.player)
                .overlay {
                    if playback.isBuilding, let frame = playback.lastFrame {
                        Image(decorative: frame, scale: 1).resizable().aspectRatio(contentMode: .fit).opacity(0.7).allowsHitTesting(false)
                    }
                }
                .aspectRatio(CGFloat(max(canvas.width, 1)) / CGFloat(max(canvas.height, 1)), contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)
            TransportBar(session: session, playback: playback)
        }
        .background(Theme.well)
    }
}


/// Luma waveform and vectorscope of the current frame (#310), refreshed a few times a second.
struct ScopesPanel: View {
    @ObservedObject var playback: PlaybackController
    @State private var data: ScopeData?

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("WAVEFORM").font(.pulseMicro).foregroundStyle(.white.opacity(0.6))
                Canvas { ctx, size in
                    guard let data else { return }
                    for (c, column) in data.waveform.enumerated() {
                        let x = CGFloat(c) / CGFloat(data.columns) * size.width
                        let w = size.width / CGFloat(data.columns)
                        for (b, v) in column.enumerated() where v > 0.02 {
                            let y = size.height - CGFloat(b + 1) / CGFloat(data.bins) * size.height
                            ctx.fill(Path(CGRect(x: x, y: y, width: w, height: size.height / CGFloat(data.bins))),
                                     with: .color(Color(red: 0.4, green: 0.95, blue: 0.5).opacity(Double(v) * 0.9)))
                        }
                    }
                    // 100 % and 0 % lines.
                    ctx.stroke(Path { p in p.move(to: CGPoint(x: 0, y: 0.5)); p.addLine(to: CGPoint(x: size.width, y: 0.5)) }, with: .color(.white.opacity(0.3)), lineWidth: 1)
                }
                .frame(width: 150, height: 72)
                .background(Color.black.opacity(0.85))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.15)))
                if let data {
                    Text(data.clippedShare > 0.01 ? String(format: "%.0f%% clipping", data.clippedShare * 100) :
                            (data.crushedShare > 0.3 ? String(format: "%.0f%% crushed blacks", data.crushedShare * 100) : "no clipping"))
                        .font(.pulseMicro).foregroundStyle(data.clippedShare > 0.01 ? Theme.warning : .white.opacity(0.6))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("VECTORSCOPE").font(.pulseMicro).foregroundStyle(.white.opacity(0.6))
                Canvas { ctx, size in
                    guard let data else { return }
                    let cell = size.width / CGFloat(data.grid)
                    for gy in 0..<data.grid { for gx in 0..<data.grid {
                        let v = data.vectorscope[gy * data.grid + gx]
                        guard v > 0.03 else { continue }
                        ctx.fill(Path(CGRect(x: CGFloat(gx) * cell, y: CGFloat(gy) * cell, width: cell, height: cell)),
                                 with: .color(Color(red: 0.95, green: 0.8, blue: 0.4).opacity(Double(v))))
                    } }
                    ctx.stroke(Path(ellipseIn: CGRect(x: 1, y: 1, width: size.width - 2, height: size.height - 2)), with: .color(.white.opacity(0.25)), lineWidth: 1)
                    ctx.stroke(Path { p in
                        p.move(to: CGPoint(x: size.width / 2, y: 0)); p.addLine(to: CGPoint(x: size.width / 2, y: size.height))
                        p.move(to: CGPoint(x: 0, y: size.height / 2)); p.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    }, with: .color(.white.opacity(0.15)), lineWidth: 1)
                }
                .frame(width: 72, height: 72)
                .background(Color.black.opacity(0.85))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.15)))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 7).fill(.black.opacity(0.55)))
        .allowsHitTesting(false)
        .task(id: playback.isPlaying) {
            // Playing: a few times a second; paused: once per seek (the clock tick) — cheap either way.
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(nanoseconds: playback.isPlaying ? 250_000_000 : 400_000_000)
            }
        }
    }

    func refresh() {
        guard let frame = playback.currentFrame() else { return }
        let width = 160, height = 90
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return }
        data = ScopeData.compute(pixels: pixels, width: width, height: height, bytesPerRow: width * 4)
    }
}


/// The Speed Edit strip over the viewer (#500): which moment you're on and the keys that move it along.
struct SpeedEditHUD: View {
    @ObservedObject var session: ProjectSession

    var body: some View {
        let moments = session.speedEditMoments
        let current = session.speedEditCurrent
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill").foregroundStyle(Theme.accent)
                Text("SPEED EDIT").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.accent)
                HelpChip(topic: .speedEdit)
                if let current, let index = session.speedEditIndex {
                    Text("\(index + 1) / \(moments.count)").font(.pulseMono).foregroundStyle(.white.opacity(0.8))
                    Text(current.title).font(.pulseCaption).foregroundStyle(.white).lineLimit(1)
                    Text("\(current.potential)").font(.pulseMono).foregroundStyle(Theme.ai)
                    Text("\(Timecode.short(current.range.start)) → \(Timecode.short(current.range.end))").font(.pulseMono).foregroundStyle(.white.opacity(0.7))
                } else {
                    Text(moments.isEmpty ? "No moments yet — analyze the recording" : "Press N for the first moment").font(.pulseCaption).foregroundStyle(.white.opacity(0.8))
                }
            }
            Text("N / P next · previous   I / O mark   X short   D dismiss   ↩ export in → out   J K L shuttle   ⎋ leave")
                .font(.pulseMicro).foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent.opacity(0.5)))
    }
}

/// The caption page under the playhead as text fields (#231): retype a word and press Return.
struct CaptionQuickEdit: View {
    @ObservedObject var session: ProjectSession
    let time: Seconds
    @State private var drafts: [UUID: String] = [:]
    @State private var page: CaptionPage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let page {
                Text("On screen at \(Timecode.short(time))").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                ForEach(Array(page.lines.enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 4) {
                        ForEach(line, id: \.id) { word in
                            TextField("", text: Binding(get: { drafts[word.id] ?? word.text }, set: { drafts[word.id] = $0 }))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, weight: word.isEmphasized ? .bold : .regular))
                                .frame(width: max(44, CGFloat((drafts[word.id] ?? word.text).count) * 8 + 18))
                                .onSubmit { commit(word.id) }
                        }
                    }
                }
                Text("Return saves a word. Timing, emphasis and style stay as they were.").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            } else {
                Text("No caption on screen here — move the playhead onto a line.").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .frame(minWidth: 220)
        .onAppear(perform: load)
    }

    func load() {
        guard let timeline = session.activeTimeline, let captions = timeline.captions else { page = nil; return }
        let words = CaptionLayoutEngine.timelineWords(captions, in: timeline)
        page = CaptionLayoutEngine.page(at: time, in: CaptionLayoutEngine.pages(words, style: captions.style))
    }

    func commit(_ id: UUID) {
        guard let text = drafts[id]?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return }
        session.editTimeline("Edit Caption") { $0.captions?.setWordText(id: id, text: text) }
        load()
    }
}
