import Foundation
import PulseCore
import PulseEngine

/// Finishing touches for a short: its opening line (#542) and its loop (#541).
extension ProjectSession {
    /// Five opening lines for the open short, written from the clip it was made from. Empty for an edit that
    /// didn't come from a clip or whose recording isn't analyzed.
    func hookLines(for timeline: Timeline) -> [HookWriter.Line] {
        guard EditFormat.of(timeline) == .short, let origin = timeline.origin, let analysis = analyses[origin.assetID] else { return [] }
        let candidate = origin.candidateID.flatMap { id in document.candidates.first { $0.id == id } }
        let range = candidate?.range ?? origin.sourceRange
        let payoff = candidate?.payoffTime ?? (range.start + range.duration * 0.6)
        let banner = analysis.hudEvents?.filter { range.contains($0.time) }.max { $0.kind.weight < $1.kind.weight }?.text
        // The same short always offers the same five lines.
        let bytes = timeline.id.uuid
        let seed = Int(bytes.0) << 16 | Int(bytes.1) << 8 | Int(bytes.2)
        return HookWriter.lines(words: analysis.transcript?.words ?? [], range: range, payoff: payoff, tags: candidate?.tags ?? [],
                                banner: banner, seed: seed)
    }

    /// Puts `line` over the opening two seconds (nil takes the line off). One undo step.
    func setHookLine(_ line: HookWriter.Line?) {
        editTimeline(line == nil ? "Remove Opening Line" : "Opening Line") { timeline in
            if let line { HookWriter.apply(line, to: &timeline) } else { HookWriter.remove(from: &timeline) }
        }
        if let line { app.toast("Opening line: “\(line.text)”", undo: true) }
    }

    /// Plays the seam of the open edit `rounds` times: the last couple of seconds, then straight into the
    /// opening, so a loop can be judged by ear and eye before it is posted (#541).
    func previewLoop(rounds: Int = 3) {
        guard let timeline = activeTimeline, timeline.duration > 3 else { return }
        loopPreview?.cancel()
        let end = timeline.duration
        let lead = min(2.5, end / 3)
        let wasLooping = playback.loopEnabled
        let range = playback.loopRange
        playback.loopRange = nil
        playback.loopEnabled = true
        loopPreview = Task { @MainActor [weak self] in
            for _ in 0..<max(1, rounds) {
                guard let self, !Task.isCancelled else { break }
                self.playback.seek(to: end - lead)
                self.playback.play()
                var wrapped = false
                var waited: Seconds = 0
                var stopped = false
                // Through the end and `lead` seconds into the opening.
                while waited < lead * 2 + 4 {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    waited += 0.05
                    if Task.isCancelled { stopped = true; break }
                    let time = self.playback.currentTime
                    if !wrapped, time < end - lead - 0.3 { wrapped = true }
                    if wrapped, time >= lead { break }
                    // Paused by hand: the preview is over.
                    if waited > 0.6, !self.playback.isPlaying { stopped = true; break }
                }
                if stopped { break }
            }
            guard let self else { return }
            self.playback.pause()
            self.playback.loopEnabled = wasLooping
            self.playback.loopRange = range
            self.loopPreview = nil
        }
    }
}
