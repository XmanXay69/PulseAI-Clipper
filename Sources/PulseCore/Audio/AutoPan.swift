import Foundation

/// Subtle pan automation (#271): a voice whose picture sits to one side of the frame leans that way a little,
/// so a left-hand facecam sounds like it comes from the left. Never more than `strength` of full pan.
public enum AutoPan {
    public static let strength = 0.2

    /// Pan (−1 left … 1 right) for a picture centred at `x` (0 left … 1 right): nothing in the middle third,
    /// rising to ±strength at the edges.
    public static func pan(forPictureX x: Double, strength: Double = AutoPan.strength) -> Double {
        let offset = x.clamped(0, 1) - 0.5
        let dead = 1.0 / 6
        guard abs(offset) > dead else { return 0 }
        let amount = min(1, (abs(offset) - dead) / (0.5 - dead))
        return (offset < 0 ? -1 : 1) * amount * strength
    }

    /// Sets the pan of the audio linked to each facecam clip (same link group, else the same asset) to follow
    /// where the facecam sits on the canvas. Returns how many audio clips changed.
    @discardableResult
    public static func apply(to timeline: inout Timeline, strength: Double = AutoPan.strength) -> Int {
        let cams = timeline.allClips.filter { $0.isVisual && ($0.role == .webcam || $0.role == .camera) }
        guard !cams.isEmpty else { return 0 }
        var changed = 0
        for t in timeline.tracks.indices where timeline.tracks[t].kind == .audio {
            for c in timeline.tracks[t].clips.indices {
                let clip = timeline.tracks[t].clips[c]
                let cam = cams.first { $0.linkGroup != nil && $0.linkGroup == clip.linkGroup }
                    ?? cams.first { $0.assetID != nil && $0.assetID == clip.assetID && $0.timelineRange.overlaps(clip.timelineRange) }
                guard let cam else { continue }
                let x = cam.transform.positionX.value(at: max(0, cam.duration / 2))
                let pan = pan(forPictureX: x, strength: strength)
                if abs(timeline.tracks[t].clips[c].audio.pan - pan) > 0.001 {
                    timeline.tracks[t].clips[c].audio.pan = pan
                    changed += 1
                }
            }
        }
        return changed
    }
}
