import Foundation

/// A three-second animated name card at the very start of a YouTube edit (#373), for people without an intro
/// video: a dark slate, your name sliding up, your handle under it, a fade to the first shot. Everything on the
/// timeline moves right to make room, so it can be taken out again with a ripple delete (the Brand Kit does).
public enum IntroBumper {
    public static let clipName = "Intro Bumper"

    /// False when the name is empty, the timeline has no video track, or a bumper is already there.
    @discardableResult
    public static func add(_ timeline: inout Timeline, name: String, handle: String? = nil, duration: Seconds = 3,
                           background: RGBAColor = RGBAColor(hex: "#101014")!) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, duration >= 1, let vi = timeline.tracks.firstIndex(where: { $0.kind == .video }),
              let ti = timeline.tracks.firstIndex(where: { $0.kind == .text }) else { return false }
        if timeline.allClips.contains(where: { $0.name == clipName }) { return false }
        for t in timeline.tracks.indices {
            for c in timeline.tracks[t].clips.indices { timeline.tracks[t].clips[c].start += duration }
        }
        for i in timeline.markers.indices { timeline.markers[i].time += duration }
        for i in timeline.layoutChanges.indices { timeline.layoutChanges[i].time += duration }

        var slate = TimelineClip(name: clipName, content: .solid(background), start: 0, sourceDuration: duration, role: .graphic, aiGenerated: true)
        slate.transitionOut = ClipTransition(kind: .fadeToBlack, duration: 0.25, aiGenerated: true)
        timeline.tracks[vi].clips.insert(slate, at: 0)

        let handle = handle?.trimmingCharacters(in: .whitespaces) ?? ""
        let titleStyle = TextStyle(fontName: TextStyle.tiktokSans, fontSize: 96, weight: .black, textCase: .uppercase, color: .white,
                                   strokeColor: .black, strokeWidth: 0, shadowOpacity: 0.6, shadowRadius: 18, shadowOffsetY: 6)
        var title = TimelineClip(name: clipName, content: .text(TextElement(text: name, style: titleStyle, animationIn: .slideUp, animationOut: .fadeIn,
                                                                            animationDuration: 0.45, maxWidth: 0.86)),
                                 start: 0.25, sourceDuration: max(0.5, duration - 0.5), aiGenerated: true)
        title.transform.positionY = AnimatedDouble(handle.isEmpty ? 0.5 : 0.46)
        timeline.tracks[ti].clips.append(title)
        if !handle.isEmpty {
            let handleStyle = TextStyle(fontName: TextStyle.tiktokSans, fontSize: 40, weight: .semibold, textCase: .asTyped, color: RGBAColor(hex: "#D7D7DE")!,
                                        strokeColor: .black, strokeWidth: 0, shadowOpacity: 0.5, shadowRadius: 12, shadowOffsetY: 4)
            var sub = TimelineClip(name: clipName, content: .text(TextElement(text: handle.hasPrefix("@") ? handle : "@" + handle, style: handleStyle,
                                                                              animationIn: .fadeIn, animationOut: .fadeIn, animationDuration: 0.35, maxWidth: 0.8)),
                                   start: 0.6, sourceDuration: max(0.4, duration - 0.85), aiGenerated: true)
            sub.transform.positionY = AnimatedDouble(0.585)
            timeline.tracks[ti].clips.append(sub)
        }
        timeline.tracks[ti].sortClips()
        timeline.markers.insert(Marker(time: 0, name: "Intro", color: .orange, aiGenerated: true), at: 0)
        timeline.touch()
        return true
    }
}
