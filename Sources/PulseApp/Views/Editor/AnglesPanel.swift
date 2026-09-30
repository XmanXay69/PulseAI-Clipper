import PulseCore
import PulseEngine
import SwiftUI

/// Multicam angle viewer: every synced angle at the playhead. Click (or press 1–9) to cut to it.
struct AnglesPanel: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    @ObservedObject var playback: PlaybackController

    init(session: ProjectSession) {
        self.session = session
        self.playback = session.playback
    }

    /// The multicam clip under the playhead.
    var currentClip: TimelineClip? {
        guard let group = session.activeMulticamGroup, let timeline = session.activeTimeline else { return nil }
        return timeline.allClips.first { c in
            c.isVisual && c.timelineRange.contains(playback.currentTime) && (c.assetID.map { group.angle($0) != nil } ?? false)
        }
    }

    var body: some View {
        if let group = session.activeMulticamGroup {
            let clip = currentClip
            let sessionTime = clip.flatMap { MulticamEditor.sessionTime(of: $0, atTimeline: playback.currentTime, group: group) }
            // Refresh thumbnails every half second while playing, exactly when paused.
            let shown = sessionTime.map { playback.isPlaying ? ($0 * 2).rounded() / 2 : $0 }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(group.videoAngles.count) angles").font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Button { session.autoSwitchActiveTimeline() } label: { Label("AI Switch", systemImage: "sparkles") }
                            .buttonStyle(.pulse(.ai, compact: true))
                            .help("Re-cut this edit to whoever is talking")
                    }
                    Text("Click an angle or press its number while playing to cut there. ⌥-click switches the whole clip.")
                        .font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(group.videoAngles.enumerated()), id: \.element.id) { index, angle in
                        angleTile(index: index, angle: angle, group: group, clip: clip, sessionTime: shown)
                    }
                }
                .padding(10)
            }
        } else {
            VStack(spacing: 12) {
                EmptyStateView(symbol: "video.badge.checkmark", title: "No multicam edit open",
                               message: "Import two or more synced cameras (or record screen + webcam), then create a multicam edit.")
                ForEach(session.multicamGroups, id: \.id) { group in
                    MulticamSessionCard(session: session, group: group).padding(.horizontal, 10)
                }
            }
        }
    }

    func angleTile(index: Int, angle: MulticamAngle, group: MulticamGroup, clip: TimelineClip?, sessionTime: Seconds?) -> some View {
        let active = clip?.assetID == angle.assetID
        let available = sessionTime.map { angle.sessionRange.contains($0) } ?? false
        let asset = session.document.asset(id: angle.assetID)
        return Button {
            if NSEvent.modifierFlags.contains(.option), let clip {
                session.switchAngle(clipID: clip.id, to: angle.assetID)
            } else {
                session.cutToAngle(index)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .topLeading) {
                    ThumbnailView(url: asset.map { session.url(for: $0) }, time: max(0, angle.sourceTime(atSession: sessionTime ?? angle.offset)), maxWidth: 480, contentMode: .fit)
                        .frame(height: 110)
                        .frame(maxWidth: .infinity)
                        .background(Color.black)
                        .opacity(available ? 1 : 0.3)
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 5).fill(active ? Theme.accent : Color.black.opacity(0.6)))
                        .padding(6)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(active ? Theme.accent : Theme.border, lineWidth: active ? 2 : 1))
                HStack {
                    Text(angle.name).font(.pulseCaption).foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary).lineLimit(1)
                    Spacer()
                    if !available { Text("not recording").font(.pulseMicro).foregroundStyle(Theme.textTertiary) }
                    if angle.hasAudio { Image(systemName: "mic.fill").font(.system(size: 9)).foregroundStyle(Theme.textTertiary) }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .help("Cut to \(angle.name) at the playhead (\(index + 1))")
    }
}

/// Inspector section for a clip that belongs to a multicam session.
struct MulticamAngleInspector: View {
    @ObservedObject var session: ProjectSession
    let clip: TimelineClip
    let group: MulticamGroup

    var body: some View {
        InspectorSection("Multicam Angle") {
            Picker("Angle", selection: Binding(get: { clip.assetID ?? UUID() }, set: { session.switchAngle(clipID: clip.id, to: $0) })) {
                ForEach(Array(group.videoAngles.enumerated()), id: \.element.id) { index, angle in
                    Text("\(index + 1). \(angle.name)").tag(angle.assetID)
                }
            }
            .font(.pulseCaption)
            Text("Switching keeps the clip in sync and the same length.").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
        }
    }
}
