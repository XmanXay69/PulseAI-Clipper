import Foundation
import PulseCore
import PulseEngine

extension ProjectSession {
    /// Captions → Language → Dub into … (#486): the translated captions spoken by the system voice for that
    /// language, on a copy of the timeline with the original voice lowered under it — a second-language
    /// channel version of the edit, exported like any other timeline.
    func dubCaptions(language: String) {
        guard let timeline = activeTimeline else { return }
        let name = CaptionTranslator.name(for: language)
        guard let track = timeline.captionTranslations[language] else {
            app.toast("Translate the captions into \(name) first")
            return
        }
        guard DubSynthesizer.voice(for: language) != nil else {
            app.presentMessage(title: "No \(name) voice installed",
                               message: "Add one in System Settings → Accessibility → Spoken Content → System Voice → Manage Voices, then try again. Enhanced and Premium voices sound best.")
            return
        }
        let lines = DubPlanner.lines(from: track, in: timeline)
        guard !lines.isEmpty else { app.toast("No \(name) captions land on this timeline"); return }
        let duration = timeline.duration
        let output = PulseDirectories.cache("Dubs", root: app.cacheFolder).appendingPathComponent("\(timeline.id.uuidString)-\(language).caf")
        app.jobs.start("Dubbing · \(name)", kind: .captions) { [weak self] job in
            guard let self else { return }
            job.detail = "\(lines.count) lines"
            try await DubSynthesizer.synthesize(lines: lines, language: language, duration: duration, to: output,
                                                progress: { p in Task { @MainActor in job.progress = p * 0.9 } }, isCancelled: job.isCancelledCheck)
            var asset = try await MediaImporter.makeAsset(for: ImportPlan.Item(url: output, kind: .audio, role: .microphone), cacheRoot: self.app.cacheFolder)
            asset.name = "Dub · \(name) · \(timeline.name)"
            asset.category = .audio
            asset.tags.append("dub:\(language)")
            var dubbed = timeline
            dubbed.id = UUID()
            dubbed.name = "\(timeline.name) — \(name) dub"
            dubbed.switchCaptions(to: language)
            let lowered = DubPlanner.place(&dubbed, dubAssetID: asset.id, duration: duration, language: language)
            let copy = dubbed
            self.edit("Dub Captions") { doc in
                if !doc.media.contains(where: { $0.id == asset.id }) { doc.media.append(asset) }
                doc.timelines.append(copy)
                doc.activeTimelineID = copy.id
            }
            self.open(timelineID: copy.id)
            self.app.logActivity(.captions, title: "Dubbed “\(timeline.name)” into \(name)", detail: "\(lines.count) lines · original voice −18 dB on \(lowered) clip\(lowered == 1 ? "" : "s")")
            self.app.toast("\(name) dub ready on “\(copy.name)” — export it for the second-language channel")
        }
    }
}
