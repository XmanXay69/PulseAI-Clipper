import AVFoundation
import Foundation
import PulseCore

/// Generates lightweight proxy media (hardware transcode) so 4K / 8-hour sources scrub smoothly.
public enum ProxyGenerator {
    public static func preset(forHeight height: Int) -> String {
        switch height {
        case ...480: return AVAssetExportPreset640x480
        case ...540: return AVAssetExportPreset960x540
        case ...720: return AVAssetExportPreset1280x720
        default: return AVAssetExportPreset1920x1080
        }
    }

    /// Creates (or reuses) a proxy for `asset` and returns its path.
    public static func makeProxy(for asset: MediaAsset, settings: ProxySettings, cacheRoot: URL? = nil,
                                 progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        let source = MediaAccess.resolve(asset)
        guard FileManager.default.fileExists(atPath: source.path) else { throw EngineError.fileMissing(source) }
        let height = settings.proxyHeight(forSourceHeight: asset.metadata.height)
        let directory = PulseDirectories.cache("Proxies", root: cacheRoot)
        let output = directory.appendingPathComponent("\(asset.id.uuidString)-\(height)p.mp4")
        if FileManager.default.fileExists(atPath: output.path) { return output }
        // Proxies are ~10% of the source size.
        try DiskSpace.ensure(asset.metadata.fileSize / 8, at: directory)
        let avAsset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: avAsset, presetName: preset(forHeight: height)) else {
            throw EngineError.exportFailed("proxy preset unavailable")
        }
        session.outputURL = output
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = false
        let timer = Task {
            while !Task.isCancelled {
                progress(Double(session.progress))
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        await session.export()
        timer.cancel()
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            throw EngineError.exportFailed(session.error?.localizedDescription ?? "proxy generation failed")
        }
        progress(1)
        return output
    }
}
