import Foundation
import PulseCore
import PulseEngine

extension ProjectSession {
    /// Audio inspector → Learn from In/Out (#263): the stretch between In and Out (set around room tone,
    /// a fan, hiss) becomes the clip's noise profile and the classic noise reduction subtracts exactly that.
    func learnNoiseProfile(clipID: UUID) {
        guard let timeline = activeTimeline, let clip = timeline.clip(id: clipID),
              let assetID = clip.assetID, let asset = document.asset(id: assetID) else { return }
        guard let marked = inOutRange else {
            app.toast("Set In and Out (I / O) around a silent stretch first")
            return
        }
        guard let overlap = marked.intersection(clip.timelineRange), overlap.duration >= 0.3 else {
            app.toast("Put In and Out on a silent part of this clip (at least 0.3 s)")
            return
        }
        let source = TimeRange(start: clip.sourceTime(atTimeline: overlap.start), end: clip.sourceTime(atTimeline: overlap.end))
        let url = self.url(for: asset)
        app.jobs.start("Learning noise · \(clip.name)", kind: .analysis) { [weak self] job in
            guard let self else { return }
            job.detail = "Listening to \(String(format: "%.1f", source.duration)) s of noise"
            guard let profile = try await AudioEnhancer.learnNoiseProfile(sourceURL: url, range: source), !profile.isEmpty else {
                self.app.toast("That stretch is too short to learn from")
                return
            }
            self.editClip(clipID, "Learn Noise Profile") { c in
                c.audio.noiseProfile = profile
                c.audio.noiseMethod = .spectral
                if c.audio.noiseReduction < 0.3 { c.audio.noiseReduction = 0.5 }
            }
            self.app.toast(String(format: "Noise profile learned from %.1f s — classic reduction now subtracts it", profile.seconds))
        }
    }
}
