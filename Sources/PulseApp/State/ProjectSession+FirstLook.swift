import Foundation
import PulseCore

extension ProjectSession {
    /// A first look at the clips (#35): the pipeline hands over the audio features before it starts transcribing,
    /// and the loud, surprising moments show up now; the full pass replaces them (favorites and opened clips stay).
    func firstLook(_ early: MediaAnalysis) {
        let assetID = early.assetID
        guard document.candidates.allSatisfy({ $0.assetID != assetID }), early.audio != nil else { return }
        let input = ClipGenerationInput(analysis: early, game: gameProfile(for: early))
        let settings = app.settings.ai.generationSettings
        let taste = app.settings.ai.taste
        Task { @MainActor [weak self] in
            let found = await Task.detached(priority: .utility) {
                ClipGenerator(input: input, settings: settings).generate().applyingTaste(taste).sorted { $0.potential > $1.potential }
            }.value
            guard let self, !found.isEmpty, self.document.candidates.allSatisfy({ $0.assetID != assetID }) else { return }
            let flagged = found.prefix(12).map { c -> ClipCandidate in var c = c; c.preliminary = true; return c }
            self.edit("First Look") { $0.candidates += flagged }
            self.app.toast("First look: \(flagged.count) moments from the audio — refining as the transcript comes in")
        }
    }
}
