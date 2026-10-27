import AVFoundation
import Foundation
import PulseCore

extension RecordingSplitter {
    /// Cuts `url` into the given stretches without re-encoding (#322): each part is a passthrough export of
    /// its range, named "… part N of M". Returns the part files in order; the original is left in place.
    public static func split(url: URL, into ranges: [TimeRange], directory: URL? = nil) async throws -> [URL] {
        guard ranges.count > 1 else { return [url] }
        let asset = AVURLAsset(url: url)
        let base = url.deletingPathExtension().lastPathComponent
        let folder = directory ?? url.deletingLastPathComponent()
        var parts: [URL] = []
        for (i, range) in ranges.enumerated() {
            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
                throw EngineError.exportFailed("couldn't split the recording")
            }
            let output = folder.appendingPathComponent(partName(base: base, index: i, count: ranges.count, extension: url.pathExtension.isEmpty ? "mov" : url.pathExtension))
            try? FileManager.default.removeItem(at: output)
            session.outputURL = output
            session.outputFileType = url.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
            session.timeRange = CMTimeRange(start: .seconds(range.start), duration: .seconds(range.duration))
            session.shouldOptimizeForNetworkUse = true
            await session.export()
            guard session.status == .completed else {
                for made in parts { try? FileManager.default.removeItem(at: made) }
                throw EngineError.exportFailed(session.error?.localizedDescription ?? "splitting part \(i + 1) failed")
            }
            parts.append(output)
        }
        return parts
    }

    /// Splits every video file of a recording that is over the limit (#322); the original files are removed
    /// once their parts exist. Parts carry a shared sequence group and their index.
    public static func splitLargeFiles(_ result: RecordingResult, gigabytes: Double) async throws -> RecordingResult {
        let limit = bytes(gigabytes: gigabytes)
        guard limit > 0 else { return result }
        var files: [RecordingResult.File] = []
        var warnings = result.warnings
        for file in result.files {
            let size = (try? FileManager.default.attributesOfItem(atPath: file.url.path)[.size] as? NSNumber)?.int64Value ?? 0
            let duration = (try? await AVURLAsset(url: file.url).load(.duration).seconds) ?? result.duration
            let ranges = plan(fileSize: size, duration: duration, maxBytes: limit)
            guard ranges.count > 1, file.role != .microphone else { files.append(file); continue }
            do {
                let parts = try await split(url: file.url, into: ranges)
                let group = UUID()
                for (i, part) in parts.enumerated() {
                    var entry = RecordingResult.File(url: part, role: file.role, syncOffset: file.syncOffset + ranges[i].start)
                    entry.sequenceGroup = group
                    entry.sequenceIndex = i
                    files.append(entry)
                }
                try? FileManager.default.removeItem(at: file.url)
            } catch {
                warnings.append("The recording couldn't be split into \(ranges.count) parts (\(error.localizedDescription)); it was kept as one file.")
                files.append(file)
            }
        }
        return RecordingResult(files: files, duration: result.duration, warnings: warnings)
    }
}
