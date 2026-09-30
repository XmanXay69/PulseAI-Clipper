import AVFoundation
import Foundation
import ImageIO
import PulseCore

/// Reads technical metadata from media files using AVFoundation (hardware-friendly, no decoding).
public enum MediaProbe {
    public static func probe(_ url: URL) async throws -> MediaMetadata {
        guard FileManager.default.fileExists(atPath: url.path) else { throw EngineError.fileMissing(url) }
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }.map { Int64($0) } ?? 0
        guard let kind = MediaTypes.kind(for: url) else {
            throw EngineError.unsupportedMedia(url, reason: "the file type isn't supported.")
        }
        if kind == .image {
            return try probeImage(url, fileSize: fileSize)
        }
        if MediaTypes.needsConversionExtensions.contains(url.pathExtension.lowercased()) {
            // AVFoundation can sometimes open these (e.g. WebM on recent macOS); try before asking for FFmpeg.
            if let meta = try? await probeAV(url, fileSize: fileSize), meta.duration > 0 { return meta }
            throw EngineError.needsFFmpeg(url)
        }
        return try await probeAV(url, fileSize: fileSize)
    }

    static func probeAV(_ url: URL, fileSize: Int64) async throws -> MediaMetadata {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let (duration, tracks, isPlayable) = try await asset.load(.duration, .tracks, .isPlayable)
        let videoTracks = tracks.filter { $0.mediaType == .video }
        let audioTracks = tracks.filter { $0.mediaType == .audio }
        guard !videoTracks.isEmpty || !audioTracks.isEmpty else {
            throw EngineError.corruptedMedia(url, reason: "no audio or video tracks were found")
        }
        guard duration.secondsValue > 0 else {
            throw EngineError.corruptedMedia(url, reason: "the recording has no duration — it may not have finished writing")
        }
        var meta = MediaMetadata(duration: duration.secondsValue, fileSize: fileSize)
        meta.creationDate = try? await asset.load(.creationDate)?.load(.dateValue)
        if let video = videoTracks.first {
            let (naturalSize, transform, fps, formats) = try await video.load(.naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions)
            let rect = CGRect(origin: .zero, size: naturalSize).applying(transform)
            meta.width = Int(abs(rect.width).rounded())
            meta.height = Int(abs(rect.height).rounded())
            meta.frameRate = Double(fps)
            meta.hasVideo = true
            if let desc = formats.first {
                meta.videoCodec = fourCC(CMFormatDescriptionGetMediaSubType(desc))
            }
            if !isPlayable {
                throw EngineError.unsupportedMedia(url, reason: "macOS doesn't have a decoder for its video codec (\(meta.videoCodec ?? "unknown")). Re-encode it as H.264 or HEVC.")
            }
        }
        if let audio = audioTracks.first {
            meta.hasAudio = true
            meta.audioTrackCount = audioTracks.count
            let formats = try await audio.load(.formatDescriptions)
            if let desc = formats.first {
                meta.audioCodec = fourCC(CMFormatDescriptionGetMediaSubType(desc))
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
                    meta.audioChannels = Int(asbd.mChannelsPerFrame)
                    meta.audioSampleRate = asbd.mSampleRate
                }
            }
        }
        return meta
    }

    static func probeImage(_ url: URL, fileSize: Int64) throws -> MediaMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw EngineError.corruptedMedia(url, reason: "the image couldn't be decoded")
        }
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        return MediaMetadata(duration: 5, width: w, height: h, frameRate: 0, hasVideo: true, fileSize: fileSize)
    }

    static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF), UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
        let raw = String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "\(code)"
        switch raw {
        case "avc1": return "H.264"
        case "hvc1", "hev1": return "HEVC"
        case "apcn", "apcs", "apco", "apch", "ap4h": return "ProRes"
        case "av01": return "AV1"
        case "vp09": return "VP9"
        case "aac ": return "AAC"
        case "lpcm": return "PCM"
        case "opus": return "Opus"
        default: return raw
        }
    }
}

/// Creates `MediaAsset`s from files and converts containers AVFoundation can't read.
public enum MediaImporter {
    public static func makeAsset(for item: ImportPlan.Item, cacheRoot: URL) async throws -> MediaAsset {
        var url = item.url
        var meta: MediaMetadata
        do {
            meta = try await MediaProbe.probe(url)
        } catch EngineError.needsFFmpeg(let original) {
            // Remux / transcode into a cached MP4 so the whole app can use native decoding.
            url = try await FFmpeg.convertToMP4(original, cacheDirectory: PulseDirectories.cache("Converted", root: cacheRoot))
            meta = try await MediaProbe.probe(url)
        }
        var asset = MediaAsset(name: item.url.deletingPathExtension().lastPathComponent, path: url.path, bookmark: MediaAccess.bookmark(for: url),
                               kind: item.kind, role: item.role, metadata: meta)
        if url != item.url { asset.tags.append("converted") }
        return asset
    }
}

/// Minimal FFmpeg integration, used only for formats AVFoundation can't open.
public enum FFmpeg {
    public static var executableURL: URL? {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        return candidates.map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public static var isAvailable: Bool { executableURL != nil }

    /// Remuxes when codecs are MP4-compatible, otherwise transcodes with VideoToolbox (hardware).
    public static func convertToMP4(_ source: URL, cacheDirectory: URL) async throws -> URL {
        guard let ffmpeg = executableURL else { throw EngineError.needsFFmpeg(source) }
        let output = cacheDirectory.appendingPathComponent(source.deletingPathExtension().lastPathComponent + "-\(abs(source.path.hashValue)).mp4")
        if FileManager.default.fileExists(atPath: output.path) { return output }
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 } ?? 0
        try DiskSpace.ensure(Int64(size) * 2, at: cacheDirectory)
        // Attempt a fast stream copy first.
        let copyArgs = ["-y", "-i", source.path, "-map", "0:v:0?", "-map", "0:a?", "-c", "copy", "-movflags", "+faststart", output.path]
        if (try? await run(ffmpeg, copyArgs)) == 0, (try? await MediaProbe.probeAV(output, fileSize: 0)) != nil {
            return output
        }
        try? FileManager.default.removeItem(at: output)
        let transcodeArgs = ["-y", "-i", source.path, "-map", "0:v:0?", "-map", "0:a?", "-c:v", "h264_videotoolbox", "-b:v", "20M",
                             "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart", output.path]
        let status = try await run(ffmpeg, transcodeArgs)
        guard status == 0, FileManager.default.fileExists(atPath: output.path) else {
            try? FileManager.default.removeItem(at: output)
            throw EngineError.conversionFailed(source, reason: "FFmpeg exited with status \(status)")
        }
        return output
    }

    static func run(_ executable: URL, _ arguments: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { p in continuation.resume(returning: p.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
