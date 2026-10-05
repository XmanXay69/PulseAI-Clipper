import Foundation
import PulseCore
import PulseEngine

/// "Edit My VOD": the whole stream → a 10–20 minute YouTube video, as an ordinary editable timeline.
extension ProjectSession {
    /// Library effects the long-form edit may use (rendered on this Mac the first time).
    static let longFormEffectIDs = ["sfx.whoosh", "sfx.boom", "sfx.impact", "sfx.rimshot", "sfx.sadTrombone", "sfx.scratch", "sfx.ding"]

    /// Rough up-front time for the edit (composing music dominates).
    func longFormEstimate(options: LongFormOptions) -> Seconds {
        guard let asset = document.primaryAsset else { return 30 }
        let target = options.targetLength(forSource: asset.metadata.duration)
        // Composing music dominates: one bed per ~4 minutes, roughly 6 s + 8 % of its length each.
        let chapters = max(1, (target / 240).rounded(.up))
        let music = options.music ? chapters * (6 + min(target / chapters, 300) * 0.08) : 0
        return 6 + music + (options.soundEffects || options.memes ? 6 : 0)
    }

    func editMyVOD(options: LongFormOptions, segments: [LongFormSegment]? = nil, hookPayoff: Seconds? = nil) {
        guard let asset = document.primaryAsset else {
            app.presentMessage(title: "No recording yet", message: "Import a stream or long video first.")
            return
        }
        guard let analysis = analyses[asset.id], analysis.audio != nil || analysis.transcript != nil else {
            app.toast("Analyzing first — your edit starts right after")
            analyze(assetID: asset.id, generateClips: false) { [weak self] in self?.editMyVOD(options: options, segments: segments, hookPayoff: hookPayoff) }
            return
        }
        let job = app.jobs.start("Editing your VOD", kind: .autoEdit) { [weak self] job in
            guard let self else { return }
            // 1. Sound effects from the built-in library.
            var effects: [MediaAsset] = []
            var newAssets: [MediaAsset] = []
            if options.soundEffects || options.memes {
                job.detail = "Preparing sound effects"
                for id in Self.longFormEffectIDs {
                    guard let sound = SoundLibrary.sound(id: id) else { continue }
                    let prepared = try await self.prepareLibrarySound(sound)
                    effects.append(prepared.asset)
                    if prepared.isNew { newAssets.append(prepared.asset) }
                    if job.state != .running { return }
                }
            }
            job.progress = 0.1
            // 2. Pick the moments and build the edit.
            job.detail = "Finding the best moments"
            let sounds = LongFormSounds(effects: effects)
            let taste = self.app.settings.ai.taste
            var result = await Task.detached(priority: .userInitiated) {
                LongFormEditor.build(asset: asset, analysis: analysis, options: options, sounds: sounds, taste: taste,
                                     segments: segments, hookPayoff: hookPayoff)
            }.value
            job.progress = 0.3
            // 3. Music: one composed bed per chapter, changing style as the video goes on.
            if options.music, !result.musicChapters.isEmpty {
                let tags = Array(result.segments.flatMap(\.tags).prefix(6))
                var beds: [MediaAsset] = []
                // Real Creative Commons tracks from YouTube when allowed; the built-in calm beds otherwise.
                if self.app.settings.ai.onlineMusic {
                    let found = await self.onlineMusicBeds(tags: tags, count: min(result.musicChapters.count, 4), job: job)
                    beds = found.assets
                    newAssets += found.assets.filter { a in !self.document.media.contains { $0.id == a.id } }
                    if !found.tracks.isEmpty {
                        result.timeline.notes += "\n\n" + MusicPicker.creditBlock(found.tracks)
                    }
                }
                let builtInChapters = beds.isEmpty ? result.musicChapters : []
                for (i, chapter) in builtInChapters.enumerated() {
                    if job.state != .running { return }
                    let sound = SoundLibrary.backgroundMusic(seed: i)
                    job.detail = "Composing music \(i + 1) of \(result.musicChapters.count) (\(sound.name))"
                    let prepared = try await self.prepareLibrarySound(sound, duration: max(3, chapter.duration))
                    beds.append(prepared.asset)
                    if prepared.isNew { newAssets.append(prepared.asset) }
                    job.progress = 0.3 + 0.65 * Double(i + 1) / Double(result.musicChapters.count)
                }
                LongFormEditor.addMusic(beds, chapters: result.musicChapters, to: &result.timeline, drops: result.musicDrops)
            }
            let timeline = result.timeline
            self.edit("Edit My VOD") { doc in
                doc.media.append(contentsOf: newAssets.filter { a in !doc.media.contains { $0.id == a.id } })
                doc.timelines.append(timeline)
                doc.activeTimelineID = timeline.id
            }
            self.open(timelineID: timeline.id)
            self.autoApplyBrandKit(to: timeline.id)
            self.lastAIReport = result.report
            self.app.logActivity(.autoEdit, title: "Edited “\(asset.name)” into a \(Timecode.short(timeline.duration)) video", detail: result.report)
            self.app.toast("Your edit is ready — \(result.report)")
        }
        job.expect(longFormEstimate(options: options))
    }

    /// Creative Commons tracks for the edit, imported as project media.
    func onlineMusicBeds(tags: [ClipTag], count: Int, job: BackgroundJob) async -> (assets: [MediaAsset], tracks: [OnlineTrack]) {
        job.detail = "Finding Creative Commons music"
        let tracks: [OnlineTrack]
        do {
            tracks = try await OnlineMusicLibrary.shared.tracks(for: tags, count: max(1, count)) { status in
                Task { @MainActor in job.detail = status }
            }
        } catch {
            PulseLog.warning("Online music unavailable, using built-in beds: \(error.localizedDescription)")
            return ([], [])
        }
        var assets: [MediaAsset] = []
        var used: [OnlineTrack] = []
        for track in tracks {
            guard let url = await OnlineMusicLibrary.shared.fileURL(for: track) else { continue }
            if let existing = document.media.first(where: { $0.path == url.path }) {
                assets.append(existing)
                used.append(track)
                continue
            }
            let plan = ImportPlan.make(urls: [url], existingPaths: [])
            guard let item = plan.items.first, var asset = try? await MediaImporter.makeAsset(for: item, cacheRoot: app.cacheFolder) else { continue }
            asset.name = track.title
            asset.role = .music
            asset.tags.append("creative-commons")
            assets.append(asset)
            used.append(track)
        }
        return (assets, used)
    }

    /// Edit → Check Edit: the same checks Edit My VOD runs (slivers, clicks at cuts, gaps, loud music,
    /// overlapping text, busy zooms, pacing, chapter length), fixing what's mechanical.
    func checkEdit() {
        guard let timeline = activeTimeline else { return }
        let words = analysis(for: timeline)?.transcript?.words ?? []
        var checked = timeline
        let report = EditQualityCheck.run(&checked, words: words)
        if !report.fixed.isEmpty {
            edit("Check Edit") { doc in doc.editTimeline(id: timeline.id) { $0 = checked } }
        }
        PulseLog.info("Check Edit on “\(timeline.name)”: \(report.summary)")
        app.presentMessage(title: report.issues.isEmpty ? "Edit check: all clear" : report.summary, message: report.text)
    }
}
