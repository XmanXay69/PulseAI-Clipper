import Foundation
import PulseCore
import PulseEngine

/// Speaker diarization on demand (Transcript panel → Speakers).
extension ProjectSession {
    /// Re-detects who's talking. With one microphone per person (a multicam/multi-mic session) the
    /// loudest mic decides and speakers take the camera names; otherwise voices are clustered.
    /// `count` 0 = estimate.
    func detectSpeakers(assetID: UUID, count: Int = 0) {
        guard let asset = document.asset(id: assetID), let transcript = analyses[assetID]?.transcript, !transcript.isEmpty else {
            app.presentMessage(title: "No transcript yet", message: "Transcribe the recording first — speakers are detected from the transcript's speech.")
            return
        }
        let voice = voiceCompanion(for: asset)
        let micGroup = MulticamGroup.group(containing: assetID, in: document.media)
        let mics = micGroup?.videoAngles.filter(\.hasAudio) ?? []
        app.jobs.start("Detecting speakers · \(asset.name)", kind: .transcription) { [weak self] job in
            guard let self else { return }
            var result = transcript
            if mics.count >= 2, let main = micGroup?.angle(assetID) {
                // One mic per person: loudness per mic, mapped into this asset's time.
                job.detail = "Comparing microphones"
                var levels: [[Float]] = []
                var hop = AudioAnalyzer.hop
                for (i, mic) in mics.enumerated() {
                    guard let micAsset = self.document.asset(id: mic.assetID) else { continue }
                    let features: AudioFeatureSeries
                    if let cached = self.analyses[mic.assetID]?.audio {
                        features = cached
                    } else {
                        features = try await AudioAnalyzer().analyze(url: self.url(for: micAsset), isCancelled: job.isCancelledCheck).features
                    }
                    hop = features.hop
                    // Series index k (mic time) ↔ this asset's time k·hop + main.offset − mic.offset.
                    let shift = Int(((main.offset - mic.offset) / hop).rounded())
                    let values = features.rmsDB.values
                    let count = Int((asset.metadata.duration / hop).rounded()) + 1
                    levels.append((0..<count).map { k in
                        let j = k + shift
                        return j >= 0 && j < values.count ? values[j] : -120
                    })
                    job.progress = Double(i + 1) / Double(mics.count) * 0.9
                }
                let segments = SpeechSegmenter.segments(from: transcript)
                let labels = Diarizer.labelsFromMicrophones(segments, levels: levels, hop: hop)
                var names: [Int: String] = [:]
                for (i, mic) in mics.enumerated() { names[i] = mic.name }
                Diarizer.apply(labels: labels, segments: segments, to: &result, names: names)
            } else {
                job.detail = "Listening for different voices"
                let source = voice ?? asset
                let delta = voice.map { asset.syncOffset - $0.syncOffset } ?? 0
                result = try await SpeakerDiarization.diarize(transcript, audioURL: self.url(for: source), delta: delta,
                                                               speakerCount: count > 0 ? count : nil, isCancelled: job.isCancelledCheck)
            }
            guard var analysis = self.analyses[assetID] else { return }
            analysis.transcript = result
            analysis.processing["speakers"] = .local
            self.setAnalysis(analysis)
            self.syncCaptionSpeakers(assetID: assetID, transcript: result)
            let found = result.speakerIDs.count
            self.app.logActivity(.transcription, title: found > 1 ? "\(found) speakers found" : "One speaker", detail: asset.name)
            self.app.toast(found > 1 ? "\(found) speakers found — rename them in the transcript" : "Only one voice detected")
        }
    }

    func renameSpeaker(_ id: Int, to name: String, assetID: UUID) {
        guard var analysis = analyses[assetID], var t = analysis.transcript else { return }
        t.renameSpeaker(id: id, to: name)
        analysis.transcript = t
        setAnalysis(analysis)
        syncCaptionSpeakers(assetID: assetID, transcript: t)
    }

    func mergeSpeaker(_ from: Int, into: Int, assetID: UUID) {
        guard var analysis = analyses[assetID], var t = analysis.transcript else { return }
        t.mergeSpeaker(from, into: into)
        analysis.transcript = t
        setAnalysis(analysis)
        syncCaptionSpeakers(assetID: assetID, transcript: t)
    }

    /// Carries new speaker labels and names into every caption track made from this asset's transcript
    /// (re-coloring tracks that were colored by speaker).
    func syncCaptionSpeakers(assetID: UUID, transcript: Transcript) {
        let ids = (document.timelines + document.compounds).filter { $0.captions?.sourceAssetID == assetID }.map(\.id)
        guard !ids.isEmpty else { return }
        edit("Update Caption Speakers") { doc in
            for id in ids {
                doc.updateTimeline(id: id) { t in
                    guard var captions = t.captions else { return }
                    let colored = captions.isColoredBySpeaker
                    captions.syncSpeakers(from: transcript)
                    if colored { captions.colorBySpeaker() }
                    t.captions = captions
                }
            }
        }
    }
}
