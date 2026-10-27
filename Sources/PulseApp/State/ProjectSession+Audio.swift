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
