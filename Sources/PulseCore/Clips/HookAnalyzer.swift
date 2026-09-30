import Foundation

/// Judges whether a clip's first seconds grab attention and suggests fixes.
/// Recommendations are advisory; applying one is always an explicit, undoable user action.
public enum HookAnalyzer {
    public static func analyze(range: TimeRange, payoff: Seconds, signals: EngagementSignals, transcript: Transcript?, hookScore: Double) -> HookAdvice {
        let d = range.duration
        let payoffOffset = payoff - range.start

        // Payoff lands almost immediately → the viewer lacks setup.
        if payoffOffset < d * 0.15, range.start > 4 {
            let back = min(d * 0.3, range.start)
            return HookAdvice(strength: hookScore, recommendation: .startEarlier(back),
                              message: "The payoff happens in the first \(Int(payoffOffset.rounded()))s. Starting \(Int(back.rounded()))s earlier adds context.")
        }
        guard hookScore < 0.45 else {
            return HookAdvice(strength: hookScore, recommendation: .keep, message: "Strong opening — the first 3 seconds already carry energy.")
        }
        // Look for a strong beat early in the clip we could start from instead.
        let searchEnd = range.start + min(d * 0.4, max(payoffOffset - 4, 0))
        if searchEnd > range.start + 1.5, signals.count > 0 {
            var bestIndex = signals.index(at: range.start + 1.5)
            for i in signals.indices(in: TimeRange(start: range.start + 1.5, end: searchEnd)) where signals.excitement[i] > signals.excitement[bestIndex] {
                bestIndex = i
            }
            let bestTime = Double(bestIndex) * signals.step
            let openingLevel = signals.mean(signals.excitement, in: TimeRange(start: range.start, end: range.start + 3))
            if signals.excitement[bestIndex] > openingLevel * 1.6 {
                var newStart = bestTime - 1
                if let transcript, let i = transcript.wordIndex(at: newStart) { newStart = transcript.words[i].start }
                let delta = max(newStart - range.start, 0)
                if delta >= 1.5 {
                    return HookAdvice(strength: hookScore, recommendation: .startLater(delta),
                                      message: "The opening is slow. Starting \(Int(delta.rounded()))s later opens on a stronger moment.")
                }
            }
        }
        // Otherwise suggest a cold open: flash the payoff first, then play the setup.
        return HookAdvice(strength: hookScore, recommendation: .coldOpen(payoffAt: payoff),
                          message: "Weak opening. Try a cold open — show 1–2 s of the payoff first, then the build-up.")
    }
}
