import Foundation
import PulseCore
import PulseEngine

/// Variable-frame-rate recordings (OBS, phones) re-encoded at a constant rate (#24), so captions and cuts
/// stop drifting. The project's asset is pointed at the new file; clips and analysis stay as they are.
extension ProjectSession {
    func conformFrameRate(assetID: UUID) {
        guard let asset = document.asset(id: assetID), asset.kind == .video, asset.metadata.width > 0 else { return }
        let fps = asset.metadata.frameRate >= 20 ? min(60, asset.metadata.frameRate.rounded()) : 30
        let width = asset.metadata.width, height = asset.metadata.height
        var timeline = Timeline(name: "Conform", canvas: CanvasSettings(width: width, height: height, frameRate: fps),
                                tracks: [Track(kind: .video, name: "V1"), Track(kind: .audio, name: "A1")])
        let video = TimelineClip(name: asset.name, content: .media(assetID: asset.id), start: 0, sourceDuration: asset.metadata.duration)
        timeline.tracks[0].clips = [video]
        if asset.metadata.hasAudio {
            timeline.tracks[1].clips = [TimelineClip(name: asset.name, content: .media(assetID: asset.id), start: 0, sourceDuration: asset.metadata.duration)]
        }
        let bitrate = min(80_000_000, max(6_000_000, Int(Double(width * height) * fps * 0.12)))
        let preset = ExportPreset(id: "conform", name: "Conform", width: width, height: height, codec: .h264, videoBitrate: bitrate, audioBitrate: 256_000)
        var settings = ExportSettings(preset: preset)
        settings.frameRate = fps
        settings.burnInCaptions = false
        settings.exportSRT = false
        settings.exportThumbnail = false
        settings.loudnessTarget = nil
        let folder = app.cacheFolder.appendingPathComponent("Conformed")
        let destination = folder.appendingPathComponent("\(asset.id.uuidString.prefix(8))-\(Int(fps))fps.mp4")
        let assets = [asset.id: asset]
        app.jobs.start("Conforming \(asset.name) to \(Int(fps)) fps", kind: .rendering) { [weak self] job in
            guard let self else { return }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            job.detail = "Re-encoding at a constant \(Int(fps)) fps"
            try await ExportEngine().export(timeline: timeline, assets: assets, settings: settings, to: destination,
                                            progress: { p in Task { @MainActor in job.progress = p } })
            var probed = try await MediaProbe.probe(destination)
            probed.variableFrameRate = false
            self.edit("Conform Frame Rate") { doc in
                doc.updateAsset(id: assetID) {
                    $0.path = destination.path
                    $0.bookmark = MediaAccess.bookmark(for: destination)
                    $0.availability = .online
                    $0.metadata = probed
                    $0.contentHash = nil
                }
            }
            self.reloadPlayback(debounce: 0)
            self.app.toast("\(asset.name) now runs at a constant \(Int(fps)) fps — the original file is untouched")
        }
    }
}
