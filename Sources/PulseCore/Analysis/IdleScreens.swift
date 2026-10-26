import Foundation

/// Loading screens, menus, "be right back" and "starting soon" cards: nothing moves and nobody talks. Edit My
/// VOD cuts them like dead air (#32, #33).
public enum IdleScreens {
    /// Screen cards that are worth cutting even when they're short (a BRB card is never a moment).
    static let strongCues: Set<String> = ["BE RIGHT BACK", "BRB", "STARTING SOON", "STREAM STARTING SOON", "STARTING SHORTLY",
                                          "INTERMISSION", "STREAM ENDING", "STREAM ENDED", "THANKS FOR WATCHING", "TECHNICAL DIFFICULTIES"]

    /// Stretches of at least `minimum` seconds where the picture barely moves and nobody speaks. An idle-screen
    /// cue read off the screen inside the stretch (BRB, LOADING…) lowers the bar to `cued` seconds. Without
    /// frame analysis, only strong cues count, for `cued` seconds after they appear (while nobody speaks).
    public static func ranges(visual: VisualFeatureSeries?, words: [TranscriptWord], cues: [HUDEvent], duration: Seconds,
                              minimum: Seconds = 20, cued: Seconds = 6) -> [TimeRange] {
        let idleCues = cues.filter { $0.kind == .idleScreen }
        var candidates: [TimeRange] = []
        if let visual, visual.count > 2, visual.hop > 0 {
            // "Barely moves": well under the recording's own typical motion, and under what a static card produces.
            let sorted = visual.motion.values.sorted()
            let median = sorted[sorted.count / 2]
            let quiet = Float(min(0.006, max(0.0015, Double(median) * 0.25)))
            var runStart: Int?
            for i in 0...visual.count {
                let still = i < visual.count && visual.motion.values[i] <= quiet
                if still, runStart == nil { runStart = i }
                if !still, let s = runStart {
                    candidates.append(TimeRange(start: Double(s) * visual.hop, end: Double(i) * visual.hop))
                    runStart = nil
                }
            }
        } else {
            for cue in idleCues where strongCues.contains(cue.text) {
                candidates.append(TimeRange(start: max(0, cue.time - 0.5), end: min(duration, cue.time + cued * 2)))
            }
        }
        var out: [TimeRange] = []
        for range in candidates {
            // Nobody talks: speech covers less than a tenth of the stretch.
            let speech = words.filter { $0.end > range.start && $0.start < range.end }
                .reduce(0.0) { $0 + (min($1.end, range.end) - max($1.start, range.start)) }
            guard speech < range.duration * 0.1 else { continue }
            let hasCue = idleCues.contains { range.expanded(by: 2).contains($0.time) }
            let needed = hasCue ? Swift.min(cued, minimum) : minimum
            if range.duration >= needed { out.append(TimeRange(start: max(0, range.start), end: min(duration, range.end))) }
        }
        return out.merged()
    }
}
