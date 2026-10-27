import PulseCore
import PulseEngine
import SwiftUI

/// A small floating viewer (#196) for the pages that don't show the editor — AI Clips and Media — so the
/// edit keeps playing where you can see it. Drag it anywhere; the × hides it (View → Mini Viewer brings it back).
struct MiniViewer: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    @ObservedObject var playback: PlaybackController
    @AppStorage("viewer.pip") private var enabled = true
    @State private var offset: CGSize = .zero
    @State private var dragging: CGSize = .zero
    @State private var hovering = false

    init(session: ProjectSession) {
        self.session = session
        self.playback = session.playback
    }

    var body: some View {
        if enabled, let timeline = session.activeTimeline {
            let aspect = CGFloat(max(timeline.canvas.width, 1)) / CGFloat(max(timeline.canvas.height, 1))
            let width: CGFloat = aspect < 1 ? 150 : 240
            VStack(spacing: 0) {
                PlayerView(player: playback.player)
                    .overlay {
                        if playback.isBuilding, let frame = playback.lastFrame {
                            Image(decorative: frame, scale: 1).resizable().aspectRatio(contentMode: .fit).opacity(0.7).allowsHitTesting(false)
                        }
                    }
                    .frame(width: width, height: width / aspect)
                    .contentShape(Rectangle())
                    .onTapGesture { playback.togglePlayPause() }
                    .overlay(alignment: .topTrailing) {
                        if hovering {
                            Button { enabled = false } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(.white.opacity(0.85)) }
                                .buttonStyle(.plain).padding(4).help("Hide the mini viewer (View → Mini Viewer shows it again)")
                        }
                    }
                HStack(spacing: 6) {
                    Button { playback.togglePlayPause() } label: { Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill") }
                        .buttonStyle(.plain).foregroundStyle(Theme.textPrimary)
                    MiniViewerClock(playback: playback)
                    Spacer(minLength: 2)
                    Text(timeline.name).font(.pulseMicro).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    Button { app.section = .editor } label: { Image(systemName: "arrow.up.forward.square") }
                        .buttonStyle(.plain).foregroundStyle(Theme.textSecondary).help("Open in the editor")
                }
                .font(.system(size: 10))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Theme.panel)
            }
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.borderStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 14, y: 4)
            .offset(x: offset.width + dragging.width, y: offset.height + dragging.height)
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { dragging = $0.translation }
                .onEnded { value in
                    offset = CGSize(width: offset.width + value.translation.width, height: offset.height + value.translation.height)
                    dragging = .zero
                })
            .onHover { hovering = $0 }
            .padding(16)
            .help("The edit's viewer, so it keeps playing while you pick clips or media (#196). Drag to move; click to play or pause.")
        }
    }
}

/// The mini viewer's timecode, refreshed by the playback clock on its own so the rest of the page doesn't redraw.
struct MiniViewerClock: View {
    @ObservedObject var playback: PlaybackController

    var body: some View {
        ClockObserving(clock: playback.slowClock) {
            Text(Timecode.short(playback.currentTime)).font(.pulseMono).foregroundStyle(Theme.textSecondary).monospacedDigit()
        }
    }
}
