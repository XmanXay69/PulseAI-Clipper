import AVFoundation
import Foundation
import PulseCore

extension CMTime {
    /// High-precision CMTime from seconds (timescale 600 is exact for 24/25/30/60 fps and 44.1/48 kHz boundaries).
    public static func seconds(_ s: Seconds, timescale: CMTimeScale = 600) -> CMTime {
        CMTime(seconds: s, preferredTimescale: timescale)
    }

    public var secondsValue: Seconds {
        let s = CMTimeGetSeconds(self)
        return s.isFinite ? s : 0
    }
}

extension TimeRange {
    public var cmTimeRange: CMTimeRange {
        CMTimeRange(start: .seconds(start), duration: .seconds(duration))
    }
}

extension CMTimeRange {
    public var timeRange: TimeRange {
        TimeRange(start: start.secondsValue, duration: duration.secondsValue)
    }
}

/// Errors with user-facing explanations (never "Something went wrong").
public enum EngineError: Error, LocalizedError {
    case fileMissing(URL)
    case unsupportedMedia(URL, reason: String)
    case corruptedMedia(URL, reason: String)
    case noAudioTrack(URL)
    case noVideoTrack(URL)
    case needsFFmpeg(URL)
    case conversionFailed(URL, reason: String)
    case insufficientDiskSpace(needed: Int64, available: Int64)
    case transcriptionUnavailable(String)
    case transcriptionFailed(String)
    case exportFailed(String)
    case cancelled
    case readerFailed(String)
    case downloadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .fileMissing(let url):
            return "“\(url.lastPathComponent)” can't be found. It may have been moved, renamed or be on a disconnected drive. Use Relink Media to point PULSE to it."
        case .unsupportedMedia(let url, let reason):
            return "“\(url.lastPathComponent)” can't be opened: \(reason)"
        case .corruptedMedia(let url, let reason):
            return "“\(url.lastPathComponent)” looks damaged (\(reason)). Try re-exporting it from your recording software."
        case .noAudioTrack(let url):
            return "“\(url.lastPathComponent)” has no audio, so PULSE can't transcribe it or detect loud moments. Clips will be found from video only."
        case .noVideoTrack(let url):
            return "“\(url.lastPathComponent)” has no video track."
        case .needsFFmpeg(let url):
            return "“\(url.lastPathComponent)” uses a container macOS can't read directly (MKV/WebM). Install FFmpeg (`brew install ffmpeg`) and PULSE will convert it automatically, or re-record as MP4/MOV."
        case .conversionFailed(let url, let reason):
            return "PULSE couldn't convert “\(url.lastPathComponent)”: \(reason)"
        case .insufficientDiskSpace(let needed, let available):
            let f = ByteCountFormatter()
            return "Not enough disk space. This needs about \(f.string(fromByteCount: needed)) but only \(f.string(fromByteCount: available)) is free. Free up space or change the cache/export folder in Settings → Files."
        case .transcriptionUnavailable(let detail):
            return detail
        case .transcriptionFailed(let detail):
            return "Transcription failed: \(detail). Clips can still be found from audio energy; you can also import an SRT/VTT transcript."
        case .exportFailed(let detail):
            return "Export failed: \(detail)"
        case .downloadFailed(let detail):
            return "Download failed — \(detail). Check your internet connection and try again."
        case .cancelled:
            return "Cancelled."
        case .readerFailed(let detail):
            return "PULSE couldn't read the media: \(detail)"
        }
    }
}

/// Filesystem helpers.
public enum DiskSpace {
    /// Free bytes available to the user on the volume containing `url`.
    public static func available(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let important = values?.volumeAvailableCapacityForImportantUsage { return important }
        return Int64(values?.volumeAvailableCapacity ?? 0)
    }

    public static func total(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey])
        return Int64(values?.volumeTotalCapacity ?? 0)
    }

    public static func ensure(_ bytes: Int64, at url: URL) throws {
        let free = available(at: url)
        if free > 0 && free < bytes + 200_000_000 {
            throw EngineError.insufficientDiskSpace(needed: bytes, available: free)
        }
    }

    public static func size(of url: URL) -> Int64 {
        ProjectStore().diskUsage(of: url)
    }
}

/// Standard app folders (overridable in Settings → Files).
public enum PulseDirectories {
    public static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return ensure(base.appendingPathComponent("PULSE", isDirectory: true))
    }

    public static var caches: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return ensure(base.appendingPathComponent("PULSE", isDirectory: true))
    }

    public static var defaultProjects: URL {
        let base = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
        return ensure(base.appendingPathComponent("PULSE Projects", isDirectory: true))
    }

    public static var defaultExports: URL {
        let base = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
        return ensure(base.appendingPathComponent("PULSE Exports", isDirectory: true))
    }

    public static var recovery: URL { ensure(applicationSupport.appendingPathComponent("Recovery", isDirectory: true)) }

    public static func cache(_ name: String, root: URL? = nil) -> URL {
        ensure((root ?? caches).appendingPathComponent(name, isDirectory: true))
    }

    @discardableResult
    public static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Progress reporting for long background work.
public struct EngineProgress: Sendable {
    public var stage: String
    public var fraction: Double
    public var detail: String?

    public init(stage: String, fraction: Double, detail: String? = nil) {
        self.stage = stage
        self.fraction = fraction
        self.detail = detail
    }
}

public typealias ProgressHandler = @Sendable (EngineProgress) -> Void

/// Opens a file that may need a security-scoped bookmark (sandboxed builds) and keeps access open.
public enum MediaAccess {
    public static func resolve(_ asset: MediaAsset) -> URL {
        if let bookmark = asset.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
                _ = url.startAccessingSecurityScopedResource()
                return url
            }
        }
        return asset.url
    }

    public static func bookmark(for url: URL) -> Data? {
        (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
    }
}

/// Copies decoded LPCM samples out of a sample buffer (safe for non-contiguous block buffers).
public enum SampleBufferReader {
    public static func floats(from sampleBuffer: CMSampleBuffer) -> [Float] {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return [] }
        let length = CMBlockBufferGetDataLength(block)
        let count = length / MemoryLayout<Float>.size
        guard count > 0 else { return [] }
        var data = [Float](repeating: 0, count: count)
        data.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress {
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size, destination: base)
            }
        }
        return data
    }
}
