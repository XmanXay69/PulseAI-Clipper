import Foundation

/// A thin bar along the bottom edge that fills left to right over the whole video (#92) — the "how much is
/// left" cue long videos use. One solid clip on its own track: the bar is the full canvas width, cropped to a
/// strip, and slides in from the left, so what's visible grows with the playhead.
public enum ProgressBar {
    public static let clipName = "Progress Bar"
    public static let trackName = "V Progress"

    @discardableResult
    public static func add(_ timeline: inout Timeline, color: RGBAColor = RGBAColor(hex: "#FF3D6E")!, thickness: Double = 0.006, opacity: Double = 0.85) -> Bool {
        guard timeline.duration >= 10, !timeline.tracks.contains(where: { $0.name == trackName }) else { return false }
        let total = timeline.duration
        var bar = TimelineClip(name: clipName, content: .solid(color), start: 0, sourceDuration: total, role: .graphic, aiGenerated: true)
        bar.transform.crop = NormRect(x: 0, y: 0, width: 1, height: thickness.clamped(0.002, 0.03))
        bar.transform.fit = .fit
        bar.transform.positionY = AnimatedDouble(1 - bar.transform.crop.height / 2)
        bar.transform.opacity = AnimatedDouble(opacity.clamped(0.1, 1))
        var x = AnimatedDouble(-0.5)
        x.setKeyframe(at: 0, value: -0.5, interpolation: .linear, aiGenerated: true)
        x.setKeyframe(at: total, value: 0.5, interpolation: .linear, aiGenerated: true)
        bar.transform.positionX = x
        var track = Track(kind: .video, name: trackName)
        track.clips = [bar]
        let lastVideo = timeline.tracks.lastIndex { $0.kind == .video } ?? -1
        timeline.tracks.insert(track, at: lastVideo + 1)
        timeline.touch()
        return true
    }

    @discardableResult
    public static func remove(_ timeline: inout Timeline) -> Bool {
        let before = timeline.tracks.count
        timeline.tracks.removeAll { $0.name == trackName }
        if timeline.tracks.count != before { timeline.touch() }
        return timeline.tracks.count != before
    }

    public static func isPresent(_ timeline: Timeline) -> Bool { timeline.tracks.contains { $0.name == trackName } }
}
