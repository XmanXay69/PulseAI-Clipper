import Foundation
import PulseCore
import PulseEngine

/// Finishing work on an edit that is already cut: the dialogue-first mix (#761), one pass made again
/// (#1101) and a cut trimmed while it loops (#661).
extension ProjectSession {
    // MARK: Dialogue-first mix (#761)

    /// Places game sound, music and effects under the voice in the open edit and says what changed. Levels
    /// come from each recording's analysis, or from its waveform when it was never analyzed (library music,
    /// sound effects); a sound whose level can't be read is left alone.
    func mixDialogueFirst() {
        guard let timeline = activeTimeline else { return }
        let timelineID = timeline.id
        Task { [weak self] in
            guard let self else { return }
            var levels: [UUID: Double] = [:]
            let assetIDs = Set(timeline.tracks.filter { $0.kind == .audio }.flatMap(\.clips).compactMap(\.assetID))
            for id in assetIDs {
                if let audio = self.analyses[id]?.audio, let level = MixAssistant.level(of: audio) {
                    levels[id] = level
                } else if let asset = self.document.asset(id: id) {
                    let peaks = await WaveformService.shared.peaks(for: self.url(for: asset))
                    if let level = MixAssistant.level(ofPeaks: peaks) { levels[id] = level }
                }
            }
            guard let current = self.activeTimeline, current.id == timelineID else { return }
            let plan = MixAssistant.plan(timeline: current, levels: levels)
            guard plan.voiceLevel != nil else {
                self.app.toast("There is no voice in this edit to mix around")
                return
            }
            guard !plan.isEmpty else {
                self.app.toast("The mix is already dialogue-first: nothing fights the voice")
                return
            }
            self.editTimeline("Dialogue-First Mix") { edit in _ = MixAssistant.apply(plan, to: &edit) }
            self.app.presentMessage(title: plan.changes.count == 1 ? "Mix: one change" : "Mix: \(plan.changes.count) changes",
                                    message: plan.changes.map(\.text).joined(separator: "\n") + "\n\nUndo (⌘Z) puts every level back.")
            self.app.logActivity(.autoEdit, title: "Dialogue-first mix", detail: "\(current.name) · \(plan.summary)")
        }
    }

    // MARK: Rebuild one pass (#1101)

    /// Edit My VOD's settings as they stand now (the sheet keeps them in the app's defaults), for redoing one
    /// pass without opening the sheet.
    func currentLongFormOptions() -> LongFormOptions {
        let defaults = UserDefaults.standard
        func flag(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        func number(_ key: String, _ fallback: Double) -> Double { defaults.object(forKey: key) as? Double ?? fallback }
        let minimum = number("longForm.minMinutes", 10), maximum = number("longForm.maxMinutes", 20)
        var options = LongFormOptions(minimumLength: minimum * 60, maximumLength: max(maximum, minimum) * 60,
                                      coldOpen: flag("longForm.coldOpen", true), cutDeadAir: true, zooms: flag("longForm.zooms", true),
                                      captions: flag("longForm.captions", true), memes: flag("longForm.memes", true),
                                      soundEffects: flag("longForm.sfx", true), music: flag("longForm.music", true),
                                      restraint: LongFormOptions.Restraint(rawValue: defaults.string(forKey: "longForm.restraint") ?? "") ?? .balanced)
        options.tighten = flag("longForm.tighten", false)
        options.shortenPauses = flag("longForm.shortenPauses", false)
        options.musicLevel = number("longForm.musicLevel", 1)
        options.chapterTitles = flag("longForm.chapterTitles", false)
        options.progressBar = flag("longForm.progressBar", false)
        options.cutGameOnly = flag("longForm.cutGameOnly", false)
        options.openLoop = flag("longForm.tease", false)
        options.deadAir = SilencePreset(rawValue: defaults.string(forKey: "longForm.deadAir") ?? "") ?? .balanced
        options.socialHandle = app.settings.ai.socialHandle
        options.memeTexts = app.settings.ai.memeTextsByTag
        if let playbook = EditorPlaybook.playbook(id: defaults.string(forKey: "longForm.editStyle") ?? "") {
            options.style = playbook.style.longFormOptions(.recommended(for: playbook.style)).style
        }
        return options
    }

    /// Makes one pass of the open YouTube edit again with Edit My VOD's current settings: change the style or
    /// a switch there, then redo only the zooms (or the pop-ups, the sound effects, the caption look, the
    /// tease). The cut and everything else stay. One undo step.
    func rebuild(_ pass: EditPass) {
        guard let timeline = activeTimeline, let analysis = analysis(for: timeline), let asset = document.asset(id: analysis.assetID) else {
            app.toast("Open an edit of an analyzed recording first")
            return
        }
        guard EditFormat.of(timeline) == .longForm else {
            app.toast("Rebuilding a pass is for YouTube edits; use Make More Entertaining on a short")
            return
        }
        let options = currentLongFormOptions()
        let taste = app.settings.ai.taste
        let preferred = app.settings.ai.preferredEffects
        let timelineID = timeline.id
        _ = app.jobs.start("Rebuilding \(pass.displayName.lowercased())", kind: .autoEdit) { [weak self] job in
            guard let self else { return }
            // The sound-effect pass needs the library's effects in the project, as Edit My VOD does.
            var effects = self.document.media.filter { $0.role == .soundEffect }
            var newAssets: [MediaAsset] = []
            if pass == .soundEffects {
                job.detail = "Preparing sound effects"
                for id in Self.longFormEffectIDs {
                    guard let sound = SoundLibrary.sound(id: id) else { continue }
                    let prepared = try await self.prepareLibrarySound(sound)
                    if !effects.contains(where: { $0.id == prepared.asset.id }) { effects.append(prepared.asset) }
                    if prepared.isNew { newAssets.append(prepared.asset) }
                    if job.state != .running { return }
                }
            }
            job.detail = "Finding where each one belongs"
            let sounds = LongFormSounds(effects: effects, preferred: preferred)
            let result = await Task.detached(priority: .userInitiated) { () -> (Timeline, EditRebuilder.Report) in
                var edit = timeline
                let report = EditRebuilder.rebuild(pass, in: &edit, asset: asset, analysis: analysis, options: options, sounds: sounds, taste: taste)
                return (edit, report)
            }.value
            guard self.document.timeline(id: timelineID) != nil else { return }
            self.edit("Rebuild \(pass.displayName)") { doc in
                doc.media.append(contentsOf: newAssets.filter { a in !doc.media.contains { $0.id == a.id } })
                if let index = doc.timelines.firstIndex(where: { $0.id == timelineID }) { doc.timelines[index] = result.0 }
            }
            self.app.toast(result.1.summary, undo: true)
            self.app.logActivity(.autoEdit, title: "Rebuilt the \(pass.displayName.lowercased())", detail: "\(timeline.name) · \(result.1.summary)")
        }
    }

    // MARK: Trim while it loops (#661)

    /// Starts or stops trimming the cut nearest the playhead: the edit plays two seconds either side of it in
    /// a loop while J and L move the cut a frame at a time.
    func toggleTrimLoop() {
        if trimLoop != nil {
            stopTrimLoop()
            return
        }
        guard let timeline = activeTimeline, let cut = TrimLoop.nearestCut(in: timeline, to: playback.currentTime) else {
            app.toast("No cut near the playhead. Park it by a cut on the main picture track and try again.")
            return
        }
        trimLoopRestore = (playback.loopEnabled, playback.loopRange)
        trimLoop = cut
        trimLoopStart = cut.time
        let range = TrimLoop.range(around: cut.time, in: timeline)
        playback.loopRange = range
        playback.loopEnabled = true
        playback.seek(to: range.start)
        playback.play()
        app.toast("Trimming the cut at \(Timecode.short(cut.time)). J and L move it a frame (⇧ for five); K or Esc stops.")
    }

    /// Moves the cut being trimmed by `frames` and keeps the loop around it.
    func nudgeTrimLoop(frames: Int) {
        guard let cut = trimLoop, let timeline = activeTimeline else { return }
        let clip = timeline.allClips.first { $0.id == cut.clipID }
        let mediaDuration = clip?.assetID.flatMap { document.asset(id: $0)?.metadata.duration }
        var moved: Seconds?
        editTimeline("Trim Cut", coalesce: "trim-loop") { edit in
            moved = TrimLoop.roll(&edit, after: cut.clipID, frames: frames, mediaDuration: mediaDuration)
        }
        guard let moved, let current = activeTimeline else { return }
        if abs(moved - cut.time) < 1e-6 {
            app.toast("The cut can't go further that way: a clip or the recording ends there")
            return
        }
        trimLoop = TrimLoop.Cut(clipID: cut.clipID, time: moved)
        let range = TrimLoop.range(around: moved, in: current)
        playback.loopRange = range
        // The picture is rebuilt after an edit: pick the loop up again once it is.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.trimLoop != nil, !self.playback.isPlaying else { return }
            self.playback.seek(to: range.start)
            self.playback.play()
        }
    }

    /// Ends the trim: playback stops on the cut and looping goes back to how it was.
    func stopTrimLoop() {
        guard let cut = trimLoop else { return }
        playback.pause()
        if let restore = trimLoopRestore {
            playback.loopEnabled = restore.0
            playback.loopRange = restore.1
        }
        trimLoopRestore = nil
        trimLoop = nil
        playback.seek(to: cut.time)
        let frames = Int(((cut.time - trimLoopStart) * (activeTimeline?.canvas.frameRate ?? 30)).rounded())
        app.toast(frames == 0 ? "Cut left where it was" : "Cut moved \(abs(frames)) frame\(abs(frames) == 1 ? "" : "s") \(frames > 0 ? "later" : "earlier")")
    }
}
