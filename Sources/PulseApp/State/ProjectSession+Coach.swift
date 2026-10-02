import Foundation
import PulseCore
import PulseEngine

/// The edit coach: a live performance prediction for the open edit plus suggestions with one-click fixes.
extension ProjectSession {
    func signals(for assetID: UUID) -> EngagementSignals? {
        guard let analysis = analyses[assetID] else { return nil }
        if let cached = signalCache[assetID], cached.count == max(1, Int((analysis.duration / cached.step).rounded(.up))) { return cached }
        let signals = EngagementModel.compute(analysis: analysis)
        signalCache[assetID] = signals
        return signals
    }

    /// Review of the active edit (recomputed as you edit; cheap compared with rendering).
    var activeReview: EditReview? {
        // Without an analysis there's nothing real to judge — no score rather than a made-up one.
        guard let timeline = activeTimeline, timeline.duration > 0.5, !document.isCompound(timeline.id),
              let analysis = analysis(for: timeline), analysis.audio != nil || analysis.transcript != nil else { return nil }
        return EditCoach.review(timeline, analysis: analysis, signals: signals(for: analysis.assetID), calibration: app.settings.ai.coachCalibration)
    }

    /// Review of any edit in this project (used to remember predictions at export).
    func review(of timeline: Timeline) -> EditReview? {
        guard let analysis = analysis(for: timeline), analysis.audio != nil || analysis.transcript != nil else { return nil }
        return EditCoach.review(timeline, analysis: analysis, signals: signals(for: analysis.assetID), calibration: app.settings.ai.coachCalibration)
    }

    func applyCoachFix(_ suggestion: EditSuggestion) {
        guard let timeline = activeTimeline else { return }
        var only = EntertainmentOptions()
        only.jumpCuts = false
        only.removeFillers = false
        only.punchIns = false
        only.captionEmphasis = false
        only.reactionZooms = false
        switch suggestion.fix {
        case .trimStart(let seconds):
            editTimeline("Trim Slow Start") { $0.rippleDelete(range: TimeRange(start: 0, end: seconds)) }
            playback.seek(to: 0)
        case .trimEnd(let seconds):
            let d = timeline.duration
            editTimeline("Trim Ending") { $0.rippleDelete(range: TimeRange(start: max(0, d - seconds), end: d)) }
        case .removeDeadAir:
            only.jumpCuts = true
            only.silencePreset = .balanced
            applyEntertainment(options: only)
        case .addCaptions:
            CaptionsWorkspace.generateCaptions(session: self)
        case .addMusic:
            only.music = true
            makeMoreEntertainingWithLibrary(options: only)
        case .addZooms:
            only.punchIns = true
            only.reactionZooms = true
            applyEntertainment(options: only)
        case .addSoundEffects:
            only.soundEffects = true
            makeMoreEntertainingWithLibrary(options: only)
        case .coldOpen(let range):
            editTimeline("Add Cold Open") { try $0.insertColdOpen(from: range) }
            playback.seek(to: 0)
        case .none:
            return
        }
        app.logActivity(.autoEdit, title: "Coach: \(suggestion.title)", detail: timeline.name)
    }
}
