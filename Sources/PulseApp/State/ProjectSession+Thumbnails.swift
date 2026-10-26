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
    /// `abPair` names the designs "… A" and "… B" (#375): the two picks as a pair to test against each other.
    func writeThumbnailDesigns(asset: MediaAsset, picks: [ThumbnailPick], layouts: [ThumbnailLayout], abPair: Bool = false) async throws -> [URL] {
        let source = url(for: asset)
        let kit = app.settings.brandKit
        let brandHex = kit.enabled ? kit.highlightColor.map(ThumbnailDesigner.hex) : nil
        let logo = kit.enabled && !kit.logoPath.isEmpty && FileManager.default.fileExists(atPath: kit.logoPath) ? kit.logoPath : nil
        let project = document.name.isEmpty ? asset.name : document.name
        var written: [URL] = []
        for (pickIndex, pick) in picks.enumerated() {
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
                var name = ThumbnailDesigner.designName(project: project, headline: pick.headline, layout: layout)
                if abPair { name += " " + (pickIndex == 0 ? "A" : "B") }
                written.append(try ThumbnailStudioLink.writeDesign(design, named: name))
            }
        }
        PulseLog.info("Thumbnail Studio: wrote \(written.count) designs for \(asset.name)")
        return written
    }

    /// After an export (#357): one design for the edit, sent to Thumbnail Studio when it's installed.
    func thumbnailAfterExport(timelineID: UUID) async {
        guard ThumbnailStudioLink.isInstalled, let setup = thumbnailSetup(for: ThumbnailRequest(timelineID: timelineID)),
              let pick = setup.picks.first else { return }
        let layouts: [ThumbnailLayout] = pick.face == nil ? [.fullFrame] : [.faceZoom]
        guard let designs = try? await writeThumbnailDesigns(asset: setup.asset, picks: [pick], layouts: layouts), let first = designs.first else { return }
        if await ThumbnailStudioLink.open(design: first) {
            app.toast("Thumbnail design for “\(setup.subject)” sent to Thumbnail Studio")
        }
    }
}


// MARK: - Grade matching (#311)

extension ProjectSession {
    /// The visual clip that ends where this one starts (or the nearest earlier one on the same track).
    func previousVisualClip(before clipID: UUID) -> TimelineClip? {
        guard let timeline = activeTimeline, let track = timeline.tracks.first(where: { $0.clips.contains { $0.id == clipID } }),
              let clip = track.clips.first(where: { $0.id == clipID }) else { return nil }
        return track.clips.filter { $0.id != clipID && $0.end <= clip.start + 0.01 && $0.assetID != nil }.max { $0.end < $1.end }
    }

    /// Average colour of a source frame from the middle of a clip (ungraded), via a 64×36 downsample.
    func frameStats(for clip: TimelineClip) async -> FrameStats? {
        guard let id = clip.assetID, let asset = document.asset(id: id) else { return nil }
        let t = clip.sourceIn + clip.sourceDuration / 2
        guard let image = await ThumbnailService.shared.image(for: url(for: asset), at: t, maxWidth: 160, precise: true) else { return nil }
        return Self.stats(of: image)
    }

    nonisolated static func stats(of image: CGImage) -> FrameStats? {
        let width = 64, height = 36
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return FrameStats.compute(pixels: pixels, width: width, height: height, bytesPerRow: width * 4, step: 1)
    }

    /// Inspector → Colour → Match grade: this clip takes on the look of the clip before it.
    func matchGrade(of clipID: UUID, toClipBefore: Bool) {
        guard let timeline = activeTimeline, let clip = timeline.clip(id: clipID), let reference = previousVisualClip(before: clipID) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let refStats = await self.frameStats(for: reference), let targetStats = await self.frameStats(for: clip) else {
                self.app.toast("Couldn't read frames from both clips to match them")
                return
            }
            let grade = GradeMatch.match(reference: refStats, referenceGrade: reference.color, target: targetStats, targetGrade: clip.color)
            self.editClip(clipID, "Match Grade", coalesce: nil) { $0.color = grade }
            self.app.toast(String(format: "Matched to “%@”: %+.2f EV, saturation %+.2f, temperature %+.2f", reference.name,
                                  grade.exposure - clip.color.exposure, grade.saturation - clip.color.saturation, grade.temperature - clip.color.temperature))
        }
    }
}
