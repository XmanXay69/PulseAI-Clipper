import Foundation
import PulseCore
import PulseEngine

extension ProjectSession {
    /// A first look at the clips (#35): the pipeline hands over the audio features before it starts transcribing,
    /// and the loud, surprising moments show up now; the full pass replaces them (favorites and opened clips stay).
    func firstLook(_ early: MediaAnalysis) {
        let assetID = early.assetID
        // Head-start clips (#1061) may already be there; anything you have worked with means the full pass is done.
        let existing = document.candidates.filter { $0.assetID == assetID }
        guard existing.allSatisfy({ $0.preliminary == true }), early.audio != nil else { return }
        let input = ClipGenerationInput(analysis: early, game: gameProfile(for: early))
        let settings = app.settings.ai.generationSettings
        let taste = app.settings.ai.taste
        Task { @MainActor [weak self] in
            let found = await Task.detached(priority: .utility) {
                ClipGenerator(input: input, settings: settings).generate().applyingTaste(taste).sorted { $0.potential > $1.potential }
            }.value
            guard let self, !found.isEmpty else { return }
            let now = self.document.candidates.filter { $0.assetID == assetID }
            guard now.allSatisfy({ $0.preliminary == true }) else { return }
            // Not on top of a clip that is already showing.
            let flagged = found.filter { c in !now.contains { $0.range.iou(c.range) > 0.3 } }.prefix(12)
                .map { c -> ClipCandidate in var c = c; c.preliminary = true; return c }
            guard !flagged.isEmpty else { return }
            self.edit("First Look") { $0.candidates += flagged }
            self.app.toast("First look: \(flagged.count) moments from the audio — refining as the transcript comes in")
        }
    }

    /// Three real clips from the first ten minutes while the rest of a long recording is analyzed (#1061). The
    /// start is copied out without re-encoding and analyzed on its own (sound, words and the facecam; no banners,
    /// reactions or speakers); its best moments
    /// appear as clips with titles and captions. Quietly does nothing when the copy or the analysis fails: the
    /// full pass is on its way regardless.
    func headStart(_ asset: MediaAsset) {
        guard HeadStart.isWorthIt(duration: asset.metadata.duration), asset.kind == .video || asset.kind == .audio,
              document.candidates.allSatisfy({ $0.assetID != asset.id }) else { return }
        let source = url(for: asset)
        let folder = PulseDirectories.cache("Analysis", root: app.cacheFolder)
        var quick = app.settings.ai
        quick.hudCues = false
        quick.faceReactions = false
        quick.detectSpeakers = false
        let settings = app.settings.ai.generationSettings
        let taste = app.settings.ai.taste
        let started = Date()
        Task { @MainActor [weak self] in
            var head = asset
            head.id = UUID()
            head.bookmark = nil
            head.metadata.duration = min(asset.metadata.duration, HeadStart.length)
            let file = folder.appendingPathComponent("\(head.id.uuidString)-head.\(source.pathExtension.lowercased() == "mp4" ? "mp4" : "mov")")
            defer {
                try? FileManager.default.removeItem(at: file)
                try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(head.id.uuidString)-16k.wav"))
            }
            do {
                head.path = try await HeadClip.export(url: source, seconds: HeadStart.length, to: file).path
                let output = try await AnalysisPipeline(cacheDirectory: folder)
                    .run(asset: head, options: AnalysisPipeline.Options(transcribe: true, detectFaces: true, ai: quick), progress: { _ in })
                let analysis = output.analysis
                let found = await Task.detached(priority: .userInitiated) {
                    HeadStart.clips(from: analysis, assetID: asset.id, settings: settings, taste: taste)
                }.value
                guard let self, !found.isEmpty else { return }
                // The full pass may have finished first on a fast Mac: then there is nothing to add.
                let existing = self.document.candidates.filter { $0.assetID == asset.id }
                guard existing.allSatisfy({ $0.preliminary == true }) else { return }
                let replaced = HeadStart.superseded(by: found, among: existing)
                // The words and the facecam of the first ten minutes, so a clip opened now gets its captions and its
                // layout before the full analysis exists. Kept beside the real analyses, never in place of one.
                if self.analyses[asset.id] == nil {
                    var known = analysis
                    known.assetID = asset.id
                    self.headAnalyses[asset.id] = known
                }
                self.edit("First Clips") { doc in
                    doc.candidates.removeAll { replaced.contains($0.id) }
                    doc.candidates += found
                }
                let seconds = Int(Date().timeIntervalSince(started).rounded())
                self.app.toast("\(found.count) clip\(found.count == 1 ? "" : "s") from the first ten minutes, \(seconds) s in. The rest is still being analyzed.")
                self.app.logActivity(.clipGeneration, title: "\(found.count) clips from the first ten minutes", detail: "\(asset.name) · ready after \(seconds) s")
                PulseLog.info("Head start: \(found.count) clips from the first \(Int(HeadStart.length / 60)) min of “\(asset.name)” after \(seconds) s")
            } catch {
                PulseLog.info("Head start skipped for “\(asset.name)”: \(error.localizedDescription)")
            }
        }
    }
}
