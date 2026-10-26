import Foundation

/// How big a recording gets (#319): a plain bits-per-pixel model for the hardware encoders, plus audio.
public enum RecordingEstimate {
    /// Bytes an hour at this size, frame rate and codec; `audioTracks` are 48 kHz AAC streams.
    public static func bytesPerHour(width: Int, height: Int, fps: Int, codec: VideoCodec, audioTracks: Int = 2) -> Int64 {
        let bitsPerPixel: Double
        switch codec {
        case .hevc: bitsPerPixel = 0.045
        case .h264: bitsPerPixel = 0.085
        case .proRes422: bitsPerPixel = 1.9
        }
        let pixels = Double(max(width, 16)) * Double(max(height, 16))
        let videoBitsPerSecond = pixels * Double(max(fps, 1)) * bitsPerPixel
        let audioBitsPerSecond = Double(audioTracks) * 192_000
        return Int64((videoBitsPerSecond + audioBitsPerSecond) * 3600 / 8)
    }

    /// "2.8 GB an hour".
    public static func perHourText(width: Int, height: Int, fps: Int, codec: VideoCodec, audioTracks: Int = 2) -> String {
        let bytes = bytesPerHour(width: width, height: height, fps: fps, codec: codec, audioTracks: audioTracks)
        let gb = Double(bytes) / 1_000_000_000
        return gb >= 1 ? String(format: "%.1f GB an hour", gb) : String(format: "%.0f MB an hour", gb * 1000)
    }
}

/// One-click recording setups (#319).
public enum RecordingPreset: String, CaseIterable, Sendable {
    case gameAndCam, podcast, screencast

    public var displayName: String {
        switch self {
        case .gameAndCam: return "Game + cam"
        case .podcast: return "Podcast"
        case .screencast: return "Screencast"
        }
    }

    public var detail: String {
        switch self {
        case .gameAndCam: return "60 fps, system audio, webcam and mic, HEVC."
        case .podcast: return "30 fps, mic only, no cursor — the picture barely matters."
        case .screencast: return "30 fps, cursor shown, system audio, H.264 for easy sharing."
        }
    }

    public var frameRate: Int { self == .gameAndCam ? 60 : 30 }
    public var captureSystemAudio: Bool { self != .podcast }
    public var showsCursor: Bool { self == .screencast }
    public var codec: VideoCodec { self == .screencast ? .h264 : .hevc }
}
