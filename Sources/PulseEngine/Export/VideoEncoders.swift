import CoreMedia
import Foundation
import PulseCore
import VideoToolbox

/// Which encoders this Mac has in hardware, from VideoToolbox's encoder list (cached: the list doesn't change
/// while the app runs).
public enum VideoEncoders {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [VideoCodec: Bool] = [:]

    public static func hardwareAvailable(for codec: VideoCodec) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let known = cache[codec] { return known }
        let result = query(codec)
        cache[codec] = result
        return result
    }

    private static func query(_ codec: VideoCodec) -> Bool {
        let type: CMVideoCodecType
        switch codec {
        case .h264: type = kCMVideoCodecType_H264
        case .hevc: type = kCMVideoCodecType_HEVC
        case .proRes422: type = kCMVideoCodecType_AppleProRes422
        case .proRes4444: type = kCMVideoCodecType_AppleProRes4444
        }
        var list: CFArray?
        guard VTCopyVideoEncoderList(nil, &list) == noErr, let encoders = list as? [[String: Any]] else { return false }
        return encoders.contains { entry in
            guard let codecType = entry[kVTVideoEncoderList_CodecType as String] as? NSNumber, codecType.uint32Value == type else { return false }
            return (entry[kVTVideoEncoderList_IsHardwareAccelerated as String] as? Bool) ?? false
        }
    }

    /// A line for the export panel when the chosen codec will fall back to the software encoder.
    public static func warning(for settings: ExportSettings) -> String? {
        guard settings.useHardwareEncoding, !hardwareAvailable(for: settings.codec) else { return nil }
        return "No hardware \(settings.codec.displayName) encoder on this Mac: the export falls back to the software encoder and takes several times longer. H.264 is hardware-encoded on every Mac PULSE runs on."
    }
}
