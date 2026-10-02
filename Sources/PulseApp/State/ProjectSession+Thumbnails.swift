import CoreGraphics
import Foundation
import PulseCore
import PulseEngine

/// What a "Make Thumbnail" sheet is for: one AI clip, one edit, or the whole recording.
struct ThumbnailRequest: Identifiable {
    let id = UUID()
    var timelineID: UUID?
    var candidateID: UUID?
}

/// Thumbnail Studio tie-in: PULSE picks the frames and the words, the studio does the design.
extension ProjectSession {
    struct ThumbnailSetup {
        var asset: MediaAsset
        var picks: [ThumbnailPick]
        var subject: String
    }

    /// The frames worth designing around for a clip, an edit, or the whole recording.
    func thumbnailSetup(for request: ThumbnailRequest) -> ThumbnailSetup? {
        let timeline = request.timelineID.flatMap { document.timeline(id: $0) }
        let candidateID = request.candidateID ?? timeline?.origin?.candidateID
        if let candidate = candidateID.flatMap({ id in document.candidates.first { $0.id == id } }),
           let asset = document.asset(id: candidate.assetID) {
            let picks = ThumbnailPicker.pick(clip: candidate, analysis: analyses[asset.id])
            return ThumbnailSetup(asset: asset, picks: picks, subject: timeline?.name ?? candidate.title)
        }
        let assetID = timeline?.origin?.assetID ?? timeline?.assetIDs.first ?? document.primaryAsset?.id
        guard let assetID, let asset = document.asset(id: assetID) else { return nil }
        // An edit: only moments it actually uses.
        let ranges = timeline.map { t in
            t.tracks.filter { $0.kind == .video }.flatMap(\.clips).compactMap { clip -> TimeRange? in
                if case .media(let id) = clip.content, id == assetID { return clip.sourceRange }
                return nil
            }
        }
        let analysis = analyses[asset.id]
        var picks = ThumbnailPicker.pick(candidates: document.candidates.filter { $0.assetID == assetID }, analysis: analysis, within: ranges, count: 4)
        if picks.isEmpty {
            // Not analyzed yet: the biggest faces, else the middle of the video.
            let headline = ThumbnailHeadline.make(from: timeline?.name ?? asset.name)
            let whole = TimeRange(start: 0, end: asset.metadata.duration)
            picks = ThumbnailPicker.alternates(in: whole, visual: analysis?.visual, count: 3, spacing: 30).map {
                ThumbnailPick(time: $0.time, face: $0.face, headline: headline, reason: "😮 Big reaction")
            }
            if picks.isEmpty {
                picks = [ThumbnailPick(time: max(0, asset.metadata.duration * 0.5), headline: headline, reason: "Middle of the video")]
            }
        }
        if let title = timeline?.copy?.titles.first, !title.isEmpty, picks.count > 0 {
            picks[0].headline = ThumbnailHeadline.make(from: title)
        }
        return ThumbnailSetup(asset: asset, picks: picks, subject: timeline?.name ?? asset.name)
    }

    /// Saves each frame at full resolution and writes one studio design per frame × layout.
    /// Returns the design files, first one first.
    func writeThumbnailDesigns(asset: MediaAsset, picks: [ThumbnailPick], layouts: [ThumbnailLayout]) async throws -> [URL] {
        let source = url(for: asset)
        let kit = app.settings.brandKit
        let brandHex = kit.enabled ? kit.highlightColor.map(ThumbnailDesigner.hex) : nil
        let logo = kit.enabled && !kit.logoPath.isEmpty && FileManager.default.fileExists(atPath: kit.logoPath) ? kit.logoPath : nil
        let project = document.name.isEmpty ? asset.name : document.name
        var written: [URL] = []
        for pick in picks {
            guard let image = await ThumbnailService.shared.image(for: source, at: pick.time, maxWidth: 1920, precise: true) else {
                PulseLog.warning("Thumbnail: no frame at \(pick.time)s of \(asset.name)")
                continue
            }
            let frame = try ThumbnailStudioLink.storeFrame(image)
            let aspect = image.height > 0 ? Double(image.width) / Double(image.height) : 16.0 / 9.0
            for layout in layouts {
                // A face zoom needs a face.
                if layout == .faceZoom, pick.face == nil, layouts.count > 1 { continue }
                let design = ThumbnailDesigner.design(layout, framePath: frame.path, sourceAspect: aspect, face: pick.face,
                                                      headline: pick.headline, accentHex: brandHex ?? "FFD60A",
                                                      panelHex: brandHex ?? "FF2D55", logoPath: logo)
                let name = ThumbnailDesigner.designName(project: project, headline: pick.headline, layout: layout)
                written.append(try ThumbnailStudioLink.writeDesign(design, named: name))
            }
        }
        PulseLog.info("Thumbnail Studio: wrote \(written.count) designs for \(asset.name)")
        return written
    }
}
