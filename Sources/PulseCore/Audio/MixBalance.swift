import Foundation

/// One slider between the voice and the game when a recording has them on separate tracks (#267).
/// −1 = voice up front (game 12 dB down), 0 = as recorded, +1 = game up front (voice 12 dB down).
public enum MixBalance {
    public static let rangeDB: Double = 12

    public static func isVoice(_ role: MediaRole?) -> Bool { role == .microphone || role == .webcam }
    public static func isGame(_ role: MediaRole?) -> Bool { role == .gameplay }

    /// Indices of the audio tracks whose clips are mostly `test`-roled.
    static func tracks(in timeline: Timeline, role: (TimelineClip) -> MediaRole?, where test: (MediaRole?) -> Bool) -> [Int] {
        timeline.tracks.indices.filter { i in
            let track = timeline.tracks[i]
            guard track.kind == .audio, !track.clips.isEmpty else { return false }
            let matching = track.clips.filter { test(role($0)) }.count
            return matching * 2 > track.clips.count
        }
    }

    /// True when the timeline has both a voice track and a game track to balance.
    public static func isAvailable(in timeline: Timeline, role: (TimelineClip) -> MediaRole?) -> Bool {
        !tracks(in: timeline, role: role, where: isVoice).isEmpty && !tracks(in: timeline, role: role, where: isGame).isEmpty
    }

    public static func apply(_ balance: Double, to timeline: inout Timeline, role: (TimelineClip) -> MediaRole?) {
        let b = balance.clamped(-1, 1)
        let gameVolume = b < 0 ? pow(10, rangeDB * b / 20) : 1
        let voiceVolume = b > 0 ? pow(10, -rangeDB * b / 20) : 1
        for i in tracks(in: timeline, role: role, where: isGame) { timeline.tracks[i].volume = gameVolume }
        for i in tracks(in: timeline, role: role, where: isVoice) { timeline.tracks[i].volume = voiceVolume }
    }

    /// The balance the track volumes currently express; nil when the timeline has no voice/game pair.
    public static func current(in timeline: Timeline, role: (TimelineClip) -> MediaRole?) -> Double? {
        let game = tracks(in: timeline, role: role, where: isGame)
        let voice = tracks(in: timeline, role: role, where: isVoice)
        guard let g = game.first, let v = voice.first else { return nil }
        let gameVolume = timeline.tracks[g].volume, voiceVolume = timeline.tracks[v].volume
        if gameVolume < 0.999, gameVolume > 0 { return (20 * log10(gameVolume) / rangeDB).clamped(-1, 0) }
        if voiceVolume < 0.999, voiceVolume > 0 { return (-20 * log10(voiceVolume) / rangeDB).clamped(0, 1) }
        return 0
    }
}
