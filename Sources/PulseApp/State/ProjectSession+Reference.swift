import Foundation
import PulseCore
import PulseEngine

/// "Edit Like a Reference": edit this project's recording the way a reference video is edited.
extension ProjectSession {
    func editLikeReference(_ style: ReferenceStyle, answers: ReferenceAnswers, extras: EditExtras = EditExtras()) {
        PulseLog.info("Edit like reference “\(style.name)”: length \(answers.length.rawValue), focus \(answers.focus.rawValue), \(answers.closeness.rawValue)")
        if answers.length == .shorts {
            makeShortsLikeReference(style, answers: answers)
        } else {
            var options = style.longFormOptions(answers)
            options.extras = extras
            editMyVOD(options: options)
        }
    }

    /// The best clips, built as shorts in the reference's style.
    func makeShortsLikeReference(_ style: ReferenceStyle, answers: ReferenceAnswers) {
        guard let asset = document.primaryAsset else {
            app.presentMessage(title: "No recording yet", message: "Import a stream or long video first.")
            return
        }
        guard let analysis = analyses[asset.id], analysis.audio != nil || analysis.transcript != nil else {
            app.toast("Analyzing first — your shorts start right after")
            analyze(assetID: asset.id, generateClips: false) { [weak self] in self?.makeShortsLikeReference(style, answers: answers) }
            return
        }
        app.jobs.start("Making shorts like “\(style.name)”", kind: .autoEdit) { [weak self] job in
            guard let self else { return }
            var pool = self.document.visibleCandidates.filter { $0.assetID == asset.id }
            if pool.isEmpty {
                job.detail = "Finding clips"
                let settings = self.app.settings.ai.generationSettings
                let taste = self.app.settings.ai.taste
                let fresh = await Task.detached(priority: .userInitiated) {
                    ClipGenerator(input: ClipGenerationInput(analysis: analysis), settings: settings).generate().applyingTaste(taste)
                }.value
                self.edit("Generate AI Clips") { $0.candidates += fresh }
                pool = fresh
            }
            let focus = answers.focus.tags
            func score(_ c: ClipCandidate) -> Int { c.potential + (c.tags.contains { focus.contains($0) } ? 12 : 0) }
            let picks = pool.sorted { score($0) > score($1) }.prefix(max(1, answers.shortsCount))
            var made: [UUID] = []
            for (i, candidate) in picks.enumerated() {
                if job.state != .running { return }
                job.detail = "Short \(i + 1) of \(picks.count)"
                if let id = self.createShort(from: candidate.id, open: false, style: (style, answers)) { made.append(id) }
                job.progress = Double(i + 1) / Double(picks.count)
            }
            if let first = made.first { self.open(timelineID: first) }
            self.app.logActivity(.autoEdit, title: "\(made.count) shorts styled like “\(style.name)”", detail: style.summary)
            self.app.toast(made.isEmpty ? "No clips stood out — try Find Again on AI Clips" : "\(made.count) shorts ready, styled like “\(style.name)”")
        }
    }
}
