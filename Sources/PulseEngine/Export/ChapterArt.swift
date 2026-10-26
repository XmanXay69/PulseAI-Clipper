import AppKit
import AVFoundation
import Foundation
import PulseCore

/// A picture per chapter for the description and the end screen (#493): the frame at the chapter marker
/// with the chapter's name set over it, as 1280×720 PNGs in a folder you choose.
public enum ChapterArt {
    public struct Result: Sendable {
        public var files: [URL]
        public var skipped: Int
    }

    /// Renders one PNG per blue (chapter) marker. The frame comes from the recording behind the main video
    /// track at that moment; markers over a cutaway or a gap are skipped.
    public static func render(timeline: Timeline, assets: [UUID: MediaAsset], into folder: URL,
                              progress: (@Sendable (Double) -> Void)? = nil) async throws -> Result {
        let chapters = timeline.markers.filter { $0.color == .blue }.sorted { $0.time < $1.time }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var files: [URL] = []
        var skipped = 0
        var generators: [UUID: AVAssetImageGenerator] = [:]
        for (index, marker) in chapters.enumerated() {
            let at = marker.time + 0.5
            guard let hit = timeline.clips(at: at).first(where: { $0.track.kind == .video && $0.clip.role != .graphic && $0.clip.content.assetID != nil }),
                  let assetID = hit.clip.content.assetID, let asset = assets[assetID] else { skipped += 1; continue }
            let sourceTime = hit.clip.sourceTime(atTimeline: at)
            let generator = generators[assetID] ?? {
                let g = AVAssetImageGenerator(asset: AVURLAsset(url: MediaAccess.resolve(asset)))
                g.appliesPreferredTrackTransform = true
                g.maximumSize = CGSize(width: 1280, height: 1280)
                g.requestedTimeToleranceBefore = .zero
                g.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
                generators[assetID] = g
                return g
            }()
            guard let frame = try? await generator.image(at: CMTime(seconds: sourceTime, preferredTimescale: 600)).image else { skipped += 1; continue }
            let title = marker.name.isEmpty ? "Chapter \(index + 1)" : marker.name
            let image = compose(frame: frame, title: title, index: index + 1, total: chapters.count)
            let name = String(format: "%02d %@.png", index + 1, ExportSettings.cleanComponent(title))
            let url = folder.appendingPathComponent(name)
            if let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                try data.write(to: url)
                files.append(url)
            }
            progress?(Double(index + 1) / Double(max(chapters.count, 1)))
        }
        return Result(files: files, skipped: skipped)
    }

    /// 1280×720: the frame filled, a dark band at the bottom, the chapter name large and "Chapter n of N" small.
    static func compose(frame: CGImage, title: String, index: Int, total: Int) -> CGImage {
        let width = 1280, height = 720
        let canvas = NSImage(size: NSSize(width: width, height: height))
        canvas.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        NSColor.black.setFill()
        rect.fill()
        let scale = max(CGFloat(width) / CGFloat(frame.width), CGFloat(height) / CGFloat(frame.height))
        let drawn = NSRect(x: (CGFloat(width) - CGFloat(frame.width) * scale) / 2, y: (CGFloat(height) - CGFloat(frame.height) * scale) / 2,
                           width: CGFloat(frame.width) * scale, height: CGFloat(frame.height) * scale)
        NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height)).draw(in: drawn, from: .zero, operation: .copy, fraction: 1)
        let band = NSRect(x: 0, y: 0, width: width, height: 220)
        NSGradient(colors: [NSColor.black.withAlphaComponent(0.85), NSColor.black.withAlphaComponent(0)])?.draw(in: band, angle: 90)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 28, weight: .semibold), .foregroundColor: NSColor.white.withAlphaComponent(0.85),
                                                     .paragraphStyle: paragraph, .shadow: shadow]
        let big: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 64, weight: .black), .foregroundColor: NSColor.white,
                                                   .paragraphStyle: paragraph, .shadow: shadow]
        NSAttributedString(string: "Chapter \(index) of \(total)", attributes: small).draw(in: NSRect(x: 60, y: 128, width: width - 120, height: 40))
        NSAttributedString(string: title.uppercased(), attributes: big).draw(in: NSRect(x: 60, y: 44, width: width - 120, height: 84))
        canvas.unlockFocus()
        var proposed = NSRect(origin: .zero, size: canvas.size)
        return canvas.cgImage(forProposedRect: &proposed, context: nil, hints: nil) ?? frame
    }
}
