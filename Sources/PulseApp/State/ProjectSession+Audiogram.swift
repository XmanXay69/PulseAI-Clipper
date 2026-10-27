import Foundation
import PulseCore
import PulseEngine

extension ProjectSession {
    /// The waveform video drawn for an audio-only recording (#9): the one already in the project when its file is
    /// still there, otherwise rendered into the cache from the recording's peaks. Nil when the recording has no length.
    func audiogramAsset(for asset: MediaAsset, job: BackgroundJob) async throws -> MediaAsset? {
        let tag = AudiogramPlacer.tag(for: asset.id)
        if let existing = document.media.first(where: { $0.tags.contains(tag) && !$0.isTrashed }),
           FileManager.default.fileExists(atPath: url(for: existing).path) {
            return existing
        }
        let duration = asset.metadata.duration
        guard duration > 0 else { return nil }
        let peaks = await WaveformService.shared.peaks(for: url(for: asset))
        let output = PulseDirectories.cache("Audiograms", root: app.cacheFolder).appendingPathComponent("\(asset.id.uuidString).mov")
        let base = job.progress
        let cancelled = job.isCancelledCheck
        try await AudiogramGenerator.render(peaks: peaks, perSecond: Double(WaveformService.peaksPerSecond), duration: duration, title: asset.name, to: output,
                                            progress: { p in Task { @MainActor in job.progress = base + 0.1 * p } },
                                            isCancelled: cancelled)
        guard !cancelled(), FileManager.default.fileExists(atPath: output.path) else { return nil }
        var visual = try await MediaImporter.makeAsset(for: ImportPlan.Item(url: output, kind: .video, role: .graphic), cacheRoot: app.cacheFolder)
        visual.name = "\(asset.name) — Waveform"
        visual.category = .graphics
        visual.tags.append(tag)
        return visual
    }
}
