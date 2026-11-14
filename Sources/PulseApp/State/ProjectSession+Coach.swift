import AppKit
import Foundation
import UniformTypeIdentifiers
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
        return EditCoach.review(timeline, analysis: analysis, signals: signals(for: analysis.assetID), calibration: app.settings.ai.coachCalibration,
                                rules: app.settings.ai.retentionProfile.adjusted(EditorPlaybook.rules(for: timeline)))
    }

    /// Review of any edit in this project (used to remember predictions at export).
    func review(of timeline: Timeline) -> EditReview? {
        guard let analysis = analysis(for: timeline), analysis.audio != nil || analysis.transcript != nil else { return nil }
        return EditCoach.review(timeline, analysis: analysis, signals: signals(for: analysis.assetID), calibration: app.settings.ai.coachCalibration,
                                rules: app.settings.ai.retentionProfile.adjusted(EditorPlaybook.rules(for: timeline)))
    }

    /// Plants a tease for the strongest moment that lands in the second half of `timeline` (#582). The moments
    /// are found again off the main thread (the same ones Edit My VOD chose from); only one that is really in
    /// the edit can be promised.
    func plantTease(in timeline: Timeline) {
        guard let analysis = analysis(for: timeline) else { return }
        let options = lastLongFormOptions ?? LongFormOptions()
        let taste = app.settings.ai.taste
        let timelineID = timeline.id
        Task { [weak self] in
            let moments = await Task.detached(priority: .userInitiated) {
                LongFormEditor.planMoments(analysis: analysis, options: options, taste: taste).moments
            }.value
            guard let self, let current = self.document.timeline(id: timelineID), self.activeTimeline?.id == timelineID else { return }
            guard let plan = OpenLoopBuilder.plan(timeline: current, moments: moments, assetID: analysis.assetID) else {
                self.app.toast("Nothing strong enough lands in the second half to promise")
                return
            }
            self.editTimeline("Plant Tease") { edit in _ = OpenLoopBuilder.plant(plan, in: &edit, assetID: analysis.assetID) }
            self.playback.seek(to: plan.at)
            self.app.toast("“\(plan.text)” at \(Timecode.short(plan.at)) points at \(Timecode.short(plan.payoffAt))", undo: true)
            self.app.logActivity(.autoEdit, title: "Coach: planted a tease", detail: current.name)
        }
    }

    /// Where the audience left fastest in `timeline`, from its imported retention (for the marks on the ruler).
    func retentionLeaks(for timeline: Timeline) -> [RetentionLearning.Leak] {
        guard let graph = timeline.retention else { return [] }
        let analysis = analysis(for: timeline)
        return RetentionLearning.leaks(timeline: timeline, graph: graph, signals: analysis.flatMap { signals(for: $0.assetID) }, assetID: analysis?.assetID)
    }

    /// Imports the open edit's real audience retention from a YouTube Studio export (#936): the graph is kept
    /// on the edit and drawn along the ruler, the coach says where viewers left and what was on screen, and the
    /// video is added to what PULSE knows about this channel's audience (#937).
    func importRetentionGraph() {
        guard let timeline = activeTimeline else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.message = "Choose the audience-retention CSV exported from YouTube Studio for “\(timeline.name)”"
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .utf16)),
              let graph = RetentionImporter.parse(text, duration: timeline.duration, source: url.lastPathComponent) else {
            app.presentMessage(title: "That isn't a retention export",
                               message: "PULSE looked for a position column and a retention column and found neither. In YouTube Studio: Analytics → the video → Engagement → Audience retention → See more → the download arrow → CSV.")
            return
        }
        editTimeline("Import Retention Graph") { $0.retention = graph }
        UserDefaults.standard.set(true, forKey: "timeline.retentionStrip")
        let analysis = analysis(for: timeline)
        let signals = analysis.flatMap { self.signals(for: $0.assetID) }
        if let seen = RetentionLearning.observe(timeline: timeline, graph: graph, signals: signals, assetID: analysis?.assetID) {
            app.settings.ai.retentionProfile = app.settings.ai.retentionProfile.adding(seen, video: timeline.id.uuidString)
        }
        let leaks = RetentionLearning.leaks(timeline: timeline, graph: graph, signals: signals, assetID: analysis?.assetID)
        let average = Int((graph.averageViewed * 100).rounded())
        app.toast(leaks.isEmpty ? "Retention imported: \(average) % watched on average, no sudden drops"
                                : "Retention imported: \(average) % watched on average. The coach shows where viewers left.")
        app.logActivity(.analysis, title: "Imported the real retention of “\(timeline.name)”", detail: "\(average) % average viewed · \(leaks.count) sudden drop\(leaks.count == 1 ? "" : "s")")
    }

    /// Silences the recording's own sound where it sounds like a music track (#521), in the open edit. The
    /// picture, captions and everything PULSE added stay; one undo step brings the sound back.
    func silenceMusicInRecording() {
        guard let timeline = activeTimeline, let analysis = analysis(for: timeline) else { return }
        let flags = MusicRisk.flags(in: timeline, analysis: analysis)
        guard !flags.isEmpty else { return }
        editTimeline("Silence Music in the Recording") { edit in _ = MusicRisk.mute(flags, in: &edit, assetID: analysis.assetID) }
        app.toast("Silenced the recording at \(MusicRisk.describe(flags))", undo: true)
        app.logActivity(.autoEdit, title: "Silenced music in the recording", detail: "\(timeline.name) · \(MusicRisk.describe(flags))")
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
        case .plantTease:
            plantTease(in: timeline)
            return
        case .removeTease:
            editTimeline("Remove Tease") { OpenLoopBuilder.remove(from: &$0) }
        case .muteMusic:
            silenceMusicInRecording()
            return
        case .none:
            return
        }
        app.logActivity(.autoEdit, title: "Coach: \(suggestion.title)", detail: timeline.name)
    }
}
