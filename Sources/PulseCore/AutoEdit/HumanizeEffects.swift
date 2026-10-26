import Foundation

extension EditPolish {
    /// Repeated sound effects don’t sound copy-pasted (#284): each gets its own level within ±`amount`
    /// (5 % by default), chosen from the clip’s id and `seed` so the same edit always comes out the same.
    /// Only clips with the sound-effect role and a flat volume are touched. Returns how many changed.
    @discardableResult
    public static func humanizeEffects(_ timeline: inout Timeline, seed: Int = 0, amount: Double = 0.05) -> Int {
        guard amount > 0 else { return 0 }
        var count = 0
        for t in timeline.tracks.indices where timeline.tracks[t].kind == .audio {
            for c in timeline.tracks[t].clips.indices where timeline.tracks[t].clips[c].role == .soundEffect {
                let clip = timeline.tracks[t].clips[c]
                guard clip.audio.volume.keyframes.isEmpty else { continue }
                let unit = jitter(id: clip.id, seed: seed)
                let factor = 1 + (unit * 2 - 1) * amount
                timeline.tracks[t].clips[c].audio.volume = AnimatedDouble((clip.audio.volume.value * factor).clamped(0, 1))
                count += 1
            }
        }
        if count > 0 { timeline.touch() }
        return count
    }

    /// 0…1 from the id and seed (FNV-1a), stable across runs and machines.
    static func jitter(id: UUID, seed: Int) -> Double {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in id.uuidString.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x100000001b3
        }
        h ^= UInt64(bitPattern: Int64(seed))
        h = h &* 0x100000001b3
        return Double(h >> 11) / Double(1 << 53)
    }
}
