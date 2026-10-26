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
        var extras: Seconds = 0
        if options.extras.beatSync, options.music { extras += 4 + chapters * 2 }
        if options.extras.brollClips { extras += 25 }   // searching + downloading a few short clips
        return 6 + music + (options.soundEffects || options.memes ? 6 : 0) + extras
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
        lastLongFormOptions = options
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
                    let found = await self.onlineMusicBeds(tags: tags, chapterTags: result.chapterTags, count: min(result.musicChapters.count, 4), job: job)
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
            // 4. The extras you said yes to.
            if options.extras.beatSync {
                if job.state != .running { return }
                job.detail = "Finding the beat"
                let known = Dictionary((self.document.media + newAssets).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                let report = await self.syncToBeats(&result.timeline, assets: known, drops: result.musicDrops)
                if !report.isEmpty { result.report += " · " + report }
            }
            if options.extras.brollClips, !result.brollMoments.isEmpty {
                if job.state != .running { return }
                let found = await self.brollCutaways(result.brollMoments, job: job)
                let placed = BrollPlacer.place(&result.timeline, clips: found.placements)
                if placed > 0 {
                    newAssets += found.placements.map { $0.asset }.filter { a in !self.document.media.contains { $0.id == a.id } }
                    result.timeline.notes += "\n\n" + BrollPlacer.creditBlock(found.clips)
                    result.report += " · \(placed) B-roll cutaway\(placed == 1 ? "" : "s")"
                } else {
                    result.report += " · no B-roll found (offline?)"
                }
            }
            let timeline = result.timeline
            var seen = Set<UUID>()
            let fresh = newAssets.filter { seen.insert($0.id).inserted }
            self.edit("Edit My VOD") { doc in
                doc.media.append(contentsOf: fresh.filter { a in !doc.media.contains { $0.id == a.id } })
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

    /// "Beat-synced music & zooms": music pieces start on a beat, AI zooms land on beats.
    func syncToBeats(_ timeline: inout Timeline, assets: [UUID: MediaAsset], drops: [Seconds] = []) async -> String {
        let musicIDs = Set(timeline.tracks.filter { $0.kind == .audio }.flatMap(\.clips).filter { $0.role == .music }.compactMap(\.content.assetID))
        var beats: [UUID: [Seconds]] = [:]
        var durations: [UUID: Seconds] = [:]
        for id in musicIDs {
            guard let asset = assets[id] else { continue }
            do {
                let grid = try await BeatDetector.shared.beats(url: asset.url)
                if grid.count >= 8 {
                    beats[id] = grid
                    durations[id] = asset.metadata.duration
                }
            } catch {
                PulseLog.warning("Beat detection failed for “\(asset.name)”: \(error.localizedDescription)")
            }
        }
        guard !beats.isEmpty else {
            PulseLog.info("Beat sync: no steady beat found in the music")
            return musicIDs.isEmpty ? "" : "no clear beat in the music"
        }
        let aligned = BeatSync.alignMusic(&timeline, beats: beats, durations: durations)
        // Pieces that now continue from the top of their track need the music drops too.
        if aligned > 0, !drops.isEmpty { EditPolish.musicDrops(&timeline, at: drops) }
        let snapped = BeatSync.snapZooms(&timeline, beats: BeatSync.timelineBeats(timeline, beats: beats))
        PulseLog.info("Beat sync: \(aligned) music pieces on the beat, \(snapped) zooms moved onto beats")
        return "\(snapped) zooms on the beat"
    }

    /// "B-roll cutaways": one Creative Commons clip per moment, downloaded and imported as project media.
    func brollCutaways(_ moments: [BrollPlacer.Moment], job: BackgroundJob) async -> (placements: [(asset: MediaAsset, at: Seconds)], clips: [OnlineTrack]) {
        var placements: [(asset: MediaAsset, at: Seconds)] = []
        var clips: [OnlineTrack] = []
        var used = Set<String>()
        for (i, moment) in moments.enumerated() {
            if job.state != .running { break }
            job.detail = "Finding B-roll \(i + 1) of \(moments.count)"
            guard let found = await OnlineMusicLibrary.shared.brollClip(query: moment.query, avoiding: used, progress: { status in
                Task { @MainActor in job.detail = status }
            }) else { continue }
            used.insert(found.clip.videoID)
            if let existing = (document.media + placements.map { $0.asset }).first(where: { $0.path == found.url.path }) {
                placements.append((existing, moment.time))
                clips.append(found.clip)
                continue
            }
            let plan = ImportPlan.make(urls: [found.url], existingPaths: [])
            guard let item = plan.items.first, var asset = try? await MediaImporter.makeAsset(for: item, cacheRoot: app.cacheFolder) else { continue }
            asset.name = found.clip.title
            asset.role = .graphic
            asset.tags.append("b-roll")
            asset.tags.append("creative-commons")
            placements.append((asset, moment.time))
            clips.append(found.clip)
        }
        PulseLog.info("B-roll: \(placements.count) of \(moments.count) cutaways found")
        return (placements, clips)
    }

    /// Creative Commons tracks for the edit, imported as project media.
    func onlineMusicBeds(tags: [ClipTag], chapterTags: [[ClipTag]] = [], count: Int, job: BackgroundJob) async -> (assets: [MediaAsset], tracks: [OnlineTrack]) {
        job.detail = "Finding Creative Commons music"
        var tracks: [OnlineTrack] = []
        // One bed per chapter, chosen for that chapter's mood (a fight gets driving music, a story gets ambient),
        // never the same track twice; the whole-stream mood fills in for chapters with no clear one.
        let perChapter = chapterTags.prefix(count).map { $0.isEmpty ? tags : $0 }
        if perChapter.count >= 2 {
            var used = Set<String>()
            for (i, chapterTag) in perChapter.enumerated() {
                job.detail = "Finding music for chapter \(i + 1) of \(perChapter.count)"
                if let track = try? await OnlineMusicLibrary.shared.tracks(for: chapterTag, count: 1, avoiding: used, progress: { status in
                    Task { @MainActor in job.detail = status }
                }).first {
                    tracks.append(track)
                    used.insert(track.videoID)
                }
            }
        }
        if tracks.isEmpty {
            do {
                tracks = try await OnlineMusicLibrary.shared.tracks(for: tags, count: max(1, count)) { status in
                    Task { @MainActor in job.detail = status }
                }
            } catch {
                PulseLog.warning("Online music unavailable, using built-in beds: \(error.localizedDescription)")
                return ([], [])
            }
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

    /// Edit → Edit My VOD Again: the same answers (optionally a little shorter or longer) as a new timeline;
    /// the previous edit stays.
    func editAgain(lengthScale: Double = 1) {
        guard var options = lastLongFormOptions else {
            app.toast("Run Edit My VOD first — Edit Again repeats its settings")
            return
        }
        options.minimumLength *= lengthScale
        options.maximumLength *= lengthScale
        options.extras.approveCut = false
        editMyVOD(options: options)
    }

    /// Timeline → Make a Short from Selection: the selected piece of the main recording (or the in → out
    /// range) becomes an AI clip and opens as a short.
    func makeShortFromSelection() {
        guard let timeline = activeTimeline, let asset = document.primaryAsset, let analysis = analyses[asset.id] else {
            app.toast("Analyze the recording first")
            return
        }
        var range: TimeRange?
        if let clip = selectedClips.first(where: { $0.content.assetID == asset.id && $0.role != .graphic }) {
            range = clip.sourceRange
        } else if let a = inPoint, let b = outPoint, b > a,
                  let clip = timeline.tracks.first(where: { $0.kind == .video })?.clips.first(where: { $0.content.assetID == asset.id && $0.timelineRange.contains(a) }) {
            let start = clip.sourceIn + (a - clip.start) * clip.speed
            range = TimeRange(start: start, end: min(clip.sourceOut, start + (b - a) * clip.speed))
        }
        guard let range, range.duration >= 3 else {
            app.toast("Select a piece of the recording (or set in and out points) first")
            return
        }
        let settings = app.settings.ai.generationSettings
        let candidate = ClipGenerator.candidate(for: range, analysis: analysis, settings: settings)
        edit("Short from Selection") { $0.candidates.insert(candidate, at: 0) }
        _ = createShort(from: candidate.id)
    }

    /// Timeline → Nudge (, and .): move the selected clips by whole frames (⇧ for ten).
    func nudgeSelection(frames: Int) {
        guard let timeline = activeTimeline, !selectedClipIDs.isEmpty else { return }
        let delta = Double(frames) / max(timeline.canvas.frameRate, 1)
        let ids = selectedClipIDs
        editTimeline("Nudge", coalesce: "nudge") { t in
            for id in ids {
                guard let clip = t.clip(id: id) else { continue }
                try? t.move(clipID: id, toStart: max(0, clip.start + delta))
            }
        }
    }

    /// Timeline → Freeze Frame (⇧F): hold the frame under the playhead for two seconds; the sound pauses with it.
    func freezeFrame(hold: Seconds = 2) {
        guard activeTimeline != nil else { return }
        let at = playback.currentTime
        var failed = false
        editTimeline("Freeze Frame") { t in
            do { try t.freezeFrame(at: at, hold: hold) } catch { failed = true }
        }
        if failed { app.toast("Put the playhead over a video clip to freeze a frame") }
    }

    /// Timeline → Close All Gaps: ripple every black gap on the main track closed.
    func closeAllGaps() {
        guard let timeline = activeTimeline else { return }
        var closed = timeline
        let n = EditQualityCheck.closeGaps(&closed)
        guard n > 0 else { app.toast("No gaps on the main track"); return }
        edit("Close Gaps") { doc in doc.editTimeline(id: timeline.id) { $0 = closed } }
        app.toast("Closed \(n) gap\(n == 1 ? "" : "s")")
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
