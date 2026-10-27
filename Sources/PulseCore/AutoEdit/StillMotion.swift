import Foundation

/// B-roll from a still (#485): a photo from the project, or a frame of the recording itself, with a slow push,
/// pull or drift so it reads as footage. For the parts of a story that have no footage.
public enum StillMotion {
    public enum Move: String, CaseIterable, Codable, Sendable {
        case pushIn, pullOut, panLeft, panRight, driftUp
    }

    /// A move for the Nth still, so neighbours don't all push in.
    public static func move(seed: Int) -> Move {
        let all = Move.allCases
        return all[((seed % all.count) + all.count) % all.count]
    }

    /// Zoom and pan keyframes across the clip's length. `strength` is how far the picture travels (0.12 ≈ a
    /// 12 % push). Returns the move used.
    @discardableResult
    public static func apply(to clip: inout TimelineClip, move: Move? = nil, seed: Int = 0, strength: Double = 0.12) -> Move {
        let chosen = move ?? Self.move(seed: seed)
        let length = max(0.1, clip.duration)
        clip.transform.zoom.removeAIKeyframes()
        clip.transform.panX.removeAIKeyframes()
        clip.transform.panY.removeAIKeyframes()
        let s = max(0, strength)
        func zoom(_ a: Double, _ b: Double) {
            clip.transform.zoom.setKeyframe(at: 0, value: a, interpolation: .easeInOut, aiGenerated: true)
            clip.transform.zoom.setKeyframe(at: length, value: b, interpolation: .easeInOut, aiGenerated: true)
        }
        switch chosen {
        case .pushIn:
            zoom(1, 1 + s)
        case .pullOut:
            zoom(1 + s, 1)
        case .panLeft:
            zoom(1 + s, 1 + s)
            clip.transform.panX.setKeyframe(at: 0, value: s / 2, interpolation: .easeInOut, aiGenerated: true)
            clip.transform.panX.setKeyframe(at: length, value: -s / 2, interpolation: .easeInOut, aiGenerated: true)
        case .panRight:
            zoom(1 + s, 1 + s)
            clip.transform.panX.setKeyframe(at: 0, value: -s / 2, interpolation: .easeInOut, aiGenerated: true)
            clip.transform.panX.setKeyframe(at: length, value: s / 2, interpolation: .easeInOut, aiGenerated: true)
        case .driftUp:
            zoom(1 + s * 0.6, 1 + s)
            clip.transform.panY.setKeyframe(at: 0, value: s / 3, interpolation: .easeInOut, aiGenerated: true)
            clip.transform.panY.setKeyframe(at: length, value: -s / 3, interpolation: .easeInOut, aiGenerated: true)
        }
        return chosen
    }

    /// A project image for a moment: one whose name or tags share a word with the moment's query, else any
    /// image not used yet. Nil when the project has no spare stills.
    public static func pick(images: [MediaAsset], for query: String, used: Set<UUID>) -> MediaAsset? {
        let spare = images.filter { $0.kind == .image && !$0.isTrashed && !used.contains($0.id) }
        let words = Set(query.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 3 })
        if let match = spare.first(where: { asset in
            let hay = (asset.name + " " + asset.tags.joined(separator: " ")).lowercased()
            return words.contains { hay.contains($0) }
        }) { return match }
        return spare.first
    }

    /// Where a frame grab of the recording should come from for a moment: a little before it, so the still
    /// shows the build-up rather than the reaction.
    public static func grabTime(for moment: Seconds, duration: Seconds) -> Seconds {
        max(0, min(duration - 0.1, moment - 1.5))
    }
}
