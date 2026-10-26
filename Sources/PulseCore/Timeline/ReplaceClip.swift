import Foundation

extension Timeline {
    /// Swaps the media behind a clip for another file, keeping its place and length (#164). Linked sound
    /// pieces follow (replaced when the new file has audio, removed when it hasn't). When the new file is
    /// shorter than the clip, the clip is cut down to it. Returns false when the clip isn't a media clip.
    @discardableResult
    public mutating func replaceContent(clipID: UUID, assetID: UUID, assetDuration: Seconds, name: String, hasAudio: Bool) -> Bool {
        guard let (ti, ci) = location(of: clipID), case .media = tracks[ti].clips[ci].content else { return false }
        let group = tracks[ti].clips[ci].linkGroup
        func swap(_ clip: inout TimelineClip) {
            clip.content = .media(assetID: assetID)
            clip.name = name
            clip.sourceIn = 0
            clip.sourceDuration = min(clip.sourceDuration, max(0.1, assetDuration * clip.speed))
            clip.aiGenerated = false
        }
        swap(&tracks[ti].clips[ci])
        if let group {
            for t in tracks.indices where t != ti {
                for c in tracks[t].clips.indices.reversed() where tracks[t].clips[c].linkGroup == group && tracks[t].clips[c].id != clipID {
                    if hasAudio && tracks[t].kind == .audio { swap(&tracks[t].clips[c]) }
                    else if tracks[t].kind == .audio { tracks[t].clips.remove(at: c) }
                }
            }
        }
        touch()
        return true
    }

    func location(of clipID: UUID) -> (Int, Int)? {
        for t in tracks.indices {
            if let c = tracks[t].clips.firstIndex(where: { $0.id == clipID }) { return (t, c) }
        }
        return nil
    }
}
