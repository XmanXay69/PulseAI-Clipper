import Foundation
import PulseCore
import PulseEngine

/// Meters (#194, #281) and room tone (#273).
extension ProjectSession {
    /// Makes sure every recording on the active timeline has its peaks in memory for the meters;
    /// loads the missing ones in the background (they're cached on disk after the first time).
    func ensureMeterPeaks() {
        guard let timeline = activeTimeline else { return }
        for id in timeline.assetIDs where meterPeaks[id] == nil && !meterPeaksLoading.contains(id) {
            guard let asset = document.asset(id: id), asset.metadata.hasAudio else { continue }
            meterPeaksLoading.insert(id)
            let url = url(for: asset)
            Task { @MainActor [weak self] in
                let peaks = await WaveformService.shared.peaks(for: url)
                guard let self else { return }
                self.meterPeaks[id] = peaks
                self.meterPeaksLoading.remove(id)
            }
        }
    }

    /// Every track's peak level and the master at timeline time `t` (0 … 1+, over 1 = the bus clips).
    func meterLevels(at t: Seconds) -> (tracks: [UUID: Float], master: Float) {
        guard let timeline = activeTimeline else { return ([:], 0) }
        let cache = meterPeaks
        return MixMeter.levels(timeline, at: t, perSecond: Double(WaveformService.peaksPerSecond)) { cache[$0] }
    }

    /// Timeline → Fill Gaps with Room Tone (#273): short silences between audio clips get the recording's
    /// own quietest stretch, 6 dB down, so cuts stop dropping to nothing.
    func fillRoomTone() {
        guard var timeline = activeTimeline else { return }
        var features: [UUID: AudioFeatureSeries] = [:]
        for id in timeline.assetIDs { if let audio = analyses[id]?.audio { features[id] = audio } }
        guard !features.isEmpty else {
            app.toast("Analyze the recording first — room tone comes from its quietest moment")
            return
        }
        let count = RoomTone.fill(&timeline, features: features)
        guard count > 0 else { app.toast("No short gaps between audio clips to fill"); return }
        editTimeline("Fill Gaps with Room Tone") { $0 = timeline }
        app.toast("\(count) gap\(count == 1 ? "" : "s") filled with room tone")
    }

    /// The role a clip's sound plays — its own, else its recording's.
    func audioRole(of clip: TimelineClip) -> MediaRole? {
        clip.role ?? clip.assetID.flatMap { document.asset(id: $0)?.role }
    }
}

extension ProjectSession {
    /// Render load spans for the ruler (#183), recomputed only when the timeline changes.
    func renderLoad(for timeline: Timeline) -> [RenderLoad.Span] {
        let key = "\(timeline.id)-\(timeline.modifiedAt.timeIntervalSinceReferenceDate)-\(timeline.allClips.count)"
        if let cached = renderLoadCache, cached.key == key { return cached.spans }
        let spans = RenderLoad.merged(RenderLoad.profile(timeline))
        renderLoadCache = (key, spans)
        return spans
    }
}

extension ProjectSession {
    /// The analysed RMS series of a recording, for the loudness readout.
    func audioFeatures(for assetID: UUID) -> AudioFeatureSeries? { analyses[assetID]?.audio }

    /// Momentary and short-term loudness at `t` (#262); nil parts when nothing analysed is under the playhead.
    func loudness(at t: Seconds) -> (momentary: Double?, shortTerm: Double?) {
        guard let timeline = activeTimeline else { return (nil, nil) }
        let features = analyses
        func f(_ id: UUID) -> AudioFeatureSeries? { features[id]?.audio }
        return (PlayheadLoudness.momentary(timeline, at: t, features: f), PlayheadLoudness.shortTerm(timeline, at: t, features: f))
    }

    /// The whole edit's integrated loudness, from a cache that refills in the background after each edit.
    func integratedLoudnessValue() -> Double? {
        guard let timeline = activeTimeline else { return nil }
        let key = "\(timeline.id)-\(timeline.modifiedAt.timeIntervalSinceReferenceDate)-\(timeline.allClips.count)"
        if let cached = integratedLoudness, cached.key == key { return cached.value }
        guard integratedLoudnessPending != key else { return integratedLoudness?.value }
        integratedLoudnessPending = key
        var series: [UUID: AudioFeatureSeries] = [:]
        for id in timeline.assetIDs { if let audio = analyses[id]?.audio { series[id] = audio } }
        let snapshot = timeline
        Task.detached(priority: .utility) { [weak self] in
            let value = PlayheadLoudness.integrated(snapshot) { series[$0] }
            await MainActor.run {
                guard let self else { return }
                self.integratedLoudness = (key, value)
                if self.integratedLoudnessPending == key { self.integratedLoudnessPending = nil }
            }
        }
        return integratedLoudness?.value
    }
}

extension ProjectSession {
    /// Timeline → Pin Emoji to Face… (#81): a text layer that follows the biggest face through the selected clip.
    func pinEmojiToFace(_ text: String) {
        guard let timeline = activeTimeline, let id = selectedClipIDs.first, let clip = timeline.clip(id: id),
              let assetID = clip.assetID else {
            app.toast("Select a video clip first")
            return
        }
        guard let faces = analyses[assetID]?.visual?.faces, !faces.isEmpty else {
            app.toast("Analyze the recording first — the sticker follows the faces it finds")
            return
        }
        guard let sticker = FaceFollower.pinned(text, to: clip, faces: faces) else {
            app.toast("No face in that stretch to pin to")
            return
        }
        editTimeline("Pin \(text) to Face") { t in
            let track = t.freeTrack(kind: .text, for: sticker.timelineRange)
            try t.insert(sticker, onTrack: track, mode: .overwrite)
        }
        app.toast("\(text) follows the face — keyframes are on the sticker's position")
    }

    /// Timeline → Record Voice-Over (#331): the microphone to a new audio clip from the playhead until Stop.
    func toggleVoiceOver() {
        if isRecordingVoiceOver { stopVoiceOver(); return }
        guard activeTimeline != nil else { return }
        let folder = PulseDirectories.cache("VoiceOver", root: app.cacheFolder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Voice-over \(Int(Date().timeIntervalSince1970)).m4a")
        do {
            let recorder = try VoiceOverRecorder(microphoneID: app.recording.microphoneID, url: url)
            voiceOverRecorder = recorder
            voiceOverStart = inPoint ?? playhead
            isRecordingVoiceOver = true
            playback.pause()
            Task { @MainActor [weak self] in
                do {
                    try await recorder.start()
                    self?.app.toast("Recording voice-over — Timeline → Stop Voice-Over when you're done")
                } catch {
                    self?.isRecordingVoiceOver = false
                    self?.voiceOverRecorder = nil
                    self?.app.presentMessage(title: "Couldn't record", message: error.localizedDescription)
                }
            }
        } catch {
            app.presentMessage(title: "Couldn't record", message: error.localizedDescription)
        }
    }

    func stopVoiceOver() {
        guard let recorder = voiceOverRecorder else { return }
        isRecordingVoiceOver = false
        voiceOverRecorder = nil
        let start = voiceOverStart
        let cacheRoot = app.cacheFolder
        app.jobs.start("Placing voice-over", kind: .importMedia) { [weak self] job in
            guard let self else { return }
            let (url, duration) = try await recorder.stop()
            guard duration > 0.2 else { self.app.toast("That voice-over was too short to keep"); return }
            var asset = try await MediaImporter.makeAsset(for: ImportPlan.Item(url: url, kind: .audio, role: .microphone), cacheRoot: cacheRoot)
            asset.name = "Voice-over \(Timecode.short(start))"
            asset.tags.append("voice-over")
            self.registerMediaIdentities([asset])
            let placed = asset
            self.edit("Record Voice-Over") { doc in
                doc.media.append(placed)
                guard let tid = self.selectedTimelineID else { return }
                doc.updateTimeline(id: tid) { t in
                    let range = TimeRange(start: start, duration: duration)
                    let track = t.freeTrack(kind: .audio, for: range)
                    var clip = TimelineClip(name: placed.name, content: .media(assetID: placed.id), start: start, sourceDuration: duration, role: .microphone)
                    clip.audio.normalize = true
                    try? t.insert(clip, onTrack: track, mode: .overwrite)
                    // Music under the voice-over ducks like it does under the main dialogue.
                    for ti in t.tracks.indices {
                        for ci in t.tracks[ti].clips.indices where t.tracks[ti].clips[ci].role == .music && t.tracks[ti].clips[ci].timelineRange.overlaps(range) {
                            t.tracks[ti].clips[ci].audio.duckUnderDialogue = true
                        }
                    }
                }
            }
            self.app.toast("Voice-over placed at \(Timecode.short(start)) (\(Timecode.short(duration)))")
        }
    }
}

extension ProjectSession {
    /// Captions → Translate… (#248): the current captions translated sentence by sentence through the configured
    /// AI provider, kept as a second track you can switch to; the original stays.
    func translateCaptions(to language: String) {
        guard let timeline = activeTimeline, let captions = timeline.captions else { app.toast("Add captions first"); return }
        guard let provider = AIProviders.translationProvider(settings: app.settings.ai) else {
            app.presentMessage(title: "No translator set up", message: "Translation uses the AI provider from Settings → AI: Claude, OpenAI, or a local OpenAI-compatible server (LM Studio, Ollama). PULSE has no built-in translation model.")
            return
        }
        if provider.location == .cloud, app.settings.ai.processingPolicy == .alwaysLocal {
            app.presentMessage(title: "Cloud AI is off", message: "Settings → AI → Processing is set to always local. Allow cloud processing, or point PULSE at a local OpenAI-compatible server.")
            return
        }
        let sentences = CaptionTranslator.sentences(in: captions)
        guard !sentences.isEmpty else { app.toast("Nothing to translate"); return }
        let timelineID = timeline.id
        let source = analyses[captions.sourceAssetID]?.transcript?.language
        let name = CaptionTranslator.name(for: language)
        app.jobs.start("Translating captions · \(name)", kind: .captions, location: provider.location) { [weak self] job in
            guard let self else { return }
            // In batches, so a long edit doesn't ride on one giant request.
            var translations: [String] = []
            let batch = 40
            var index = 0
            while index < sentences.count {
                if job.state != .running { return }
                let slice = Array(sentences[index..<min(index + batch, sentences.count)])
                job.detail = "Sentences \(index + 1)–\(index + slice.count) of \(sentences.count)"
                translations += try await provider.translate(sentences: slice.map(\.text), from: source, to: name)
                index += batch
                job.progress = Double(index) / Double(sentences.count)
            }
            guard let track = CaptionTranslator.track(from: captions, sentences: sentences, translations: translations) else {
                throw AIProviderError.badResponse("the translation came back empty")
            }
            self.edit("Translate Captions") { doc in
                doc.updateTimeline(id: timelineID) { t in
                    t.addCaptionTranslation(track, language: language)
                    t.switchCaptions(to: language)
                }
            }
            self.app.logActivity(.captions, title: "Captions translated to \(name)", detail: "\(sentences.count) sentences", location: provider.location)
            self.app.toast("Captions in \(name) — switch languages in the Captions panel")
        }
    }
}
