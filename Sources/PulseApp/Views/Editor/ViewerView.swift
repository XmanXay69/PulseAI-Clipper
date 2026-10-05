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
    @State private var fullscreen = false

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
                        if app.settings.showSafeAreas, canvas.aspect < 1 {
                            SafeAreaOverlay(platform: app.settings.safeAreaPlatform)
                        }
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
                if let review = session.activeReview {
                    Button { session.selectedClipIDs = [] } label: { PerformanceBadge(prediction: review.prediction) }
                        .buttonStyle(.plain).fixedSize()
                }
            }
            Spacer(minLength: 4)
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

    var body: some View {
        GeometryReader { geo in
            let i = platform.insets
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
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
                }
                .frame(width: frameSize.width, height: frameSize.height, alignment: .topLeading)
            }
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
    @ObservedObject var session: ProjectSession
    @ObservedObject var playback: PlaybackController

    var body: some View {
        HStack(spacing: 8) {
            ClockObserving(clock: playback.clock) {
                Text(Timecode.string(playback.currentTime, fps: playback.frameRate))
                    .font(.pulseTimecode)
                    .foregroundStyle(Theme.accent)
                    .fixedSize()
                    .frame(minWidth: 120, maxWidth: 130, alignment: .leading)
            }
            Spacer(minLength: 4)
            IconButton(symbol: "backward.end.fill", help: "Go to start (Home)") { playback.goToStart() }
            IconButton(symbol: "backward.frame.fill", help: "Previous frame (←)") { playback.step(frames: -1) }
            Button { playback.togglePlayPause() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 30)
                    .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.control))
                    .foregroundStyle(Theme.textPrimary)
            }
            .buttonStyle(.plain)
            .help("Play / Pause (Space)")
            IconButton(symbol: "forward.frame.fill", help: "Next frame (→)") { playback.step(frames: 1) }
            IconButton(symbol: "forward.end.fill", help: "Go to end (End)") { playback.goToEnd() }
            IconButton(symbol: "repeat", help: "Loop", isActive: playback.loopEnabled) { playback.loopEnabled.toggle() }
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

    var duration: some View {
        Text(Timecode.string(playback.duration, fps: playback.frameRate))
            .font(.pulseMono)
            .foregroundStyle(Theme.textTertiary)
            .fixedSize()
    }
}
