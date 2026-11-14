import AVFoundation
import Foundation
import PulseCore

/// Cuts the start of a recording into its own file without re-encoding (#1061), so the first ten minutes can
/// be analyzed on their own while the whole recording is still being read.
public enum HeadClip {
    /// The first `seconds` of `url` as a passthrough copy at `destination` (replaced if it exists). Takes a few
    /// seconds whatever the recording's length: nothing is decoded.
    public static func export(url: URL, seconds: Seconds, to destination: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw EngineError.exportFailed("couldn't read the start of the recording")
        }
        try? FileManager.default.removeItem(at: destination)
        session.outputURL = destination
        session.outputFileType = destination.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
        session.timeRange = CMTimeRange(start: .zero, duration: .seconds(seconds))
        await withTaskCancellationHandler { await session.export() } onCancel: { session.cancelExport() }
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: destination)
            throw EngineError.exportFailed(session.error?.localizedDescription ?? "couldn't copy the start of the recording")
        }
        return destination
    }
}
