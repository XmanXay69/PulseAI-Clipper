import AppKit
import Foundation
import PulseCore
import PulseEngine

extension ProjectSession {
    /// A still for a moment with no footage (#485): a photo from the project whose name fits the moment, else a
    /// frame of the recording a moment earlier, saved as an image asset. Nil when nothing can be made.
    func stillForBroll(moment: BrollPlacer.Moment, primary: MediaAsset, sourceTime: Seconds?, used: inout Set<UUID>) async -> MediaAsset? {
        if let image = StillMotion.pick(images: document.media, for: moment.query, used: used) {
            used.insert(image.id)
            return image
        }
        guard let sourceTime, primary.metadata.hasVideo else { return nil }
        let at = StillMotion.grabTime(for: sourceTime, duration: primary.metadata.duration)
        guard let cg = await ThumbnailService.shared.image(for: url(for: primary), at: at, maxWidth: 1920, precise: true),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return nil }
        let folder = PulseDirectories.cache("Stills", root: app.cacheFolder)
        let file = folder.appendingPathComponent("\(primary.id.uuidString)-\(Int(at * 10)).png")
        do {
            try png.write(to: file)
            var asset = try await MediaImporter.makeAsset(for: ImportPlan.Item(url: file, kind: .image, role: .graphic), cacheRoot: app.cacheFolder)
            asset.name = "Still · \(Timecode.short(at))"
            asset.category = .graphics
            asset.tags += ["still", "b-roll"]
            used.insert(asset.id)
            return asset
        } catch {
            PulseLog.warning("Still grab failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Gives every still on the B-roll track a slow move (#485), a different one per still.
    static func animateStills(in timeline: inout Timeline, images: Set<UUID>) -> Int {
        var count = 0
        for t in timeline.tracks.indices where timeline.tracks[t].kind == .video {
            for c in timeline.tracks[t].clips.indices {
                guard let id = timeline.tracks[t].clips[c].assetID, images.contains(id) else { continue }
                StillMotion.apply(to: &timeline.tracks[t].clips[c], seed: count)
                count += 1
            }
        }
        return count
    }
}
