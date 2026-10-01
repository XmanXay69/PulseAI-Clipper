import AVFoundation
import Foundation
import PulseCore

/// Renders built-in library sounds to AAC files on first use and keeps them in
/// Application Support/PULSE/Sound Library, so they import like any other media file.
public actor SoundLibraryStore {
    public static let shared = SoundLibraryStore()

    public static var defaultDirectory: URL {
        PulseDirectories.ensure(PulseDirectories.applicationSupport.appendingPathComponent("Sound Library", isDirectory: true))
    }

    private var inFlight: [String: Task<URL, Error>] = [:]

    public init() {}

    /// File name for a sound (music includes its length: every length is its own composition).
    public static func fileName(for sound: LibrarySound, duration: Seconds?) -> String {
        var name = "\(sound.id)-v\(SoundLibrary.version)"
        if sound.kind == .music { name += String(format: "-%.1fs", max(2, duration ?? SoundLibrary.defaultMusicLength)) }
        return name + ".m4a"
    }

    /// The rendered file, rendering it if needed. Music is exactly `duration` long.
    public func file(for sound: LibrarySound, duration: Seconds? = nil, directory: URL? = nil) async throws -> URL {
        let folder = PulseDirectories.ensure(directory ?? Self.defaultDirectory)
        let rounded = duration.map { ($0 * 10).rounded() / 10 }
        let url = folder.appendingPathComponent(Self.fileName(for: sound, duration: rounded))
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let key = url.path
        if let running = inFlight[key] { return try await running.value }
        let task = Task.detached(priority: .userInitiated) {
            let audio = SoundLibrary.render(sound, duration: rounded)
            let temp = folder.appendingPathComponent(UUID().uuidString + ".m4a")
            try SoundLibraryStore.write(audio, to: temp)
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: temp, to: url)
            return url
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }

    /// Writes stereo float audio as 256 kbps AAC.
    static func write(_ channels: [[Float]], to url: URL) throws {
        let rate = Synth.sampleRate
        let count = channels.first?.count ?? 0
        guard count > 0, let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: AVAudioChannelCount(channels.count)) else {
            throw EngineError.exportFailed("nothing to write")
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: channels.count,
            AVEncoderBitRateKey: 256_000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let chunk = 32_768
        var offset = 0
        while offset < count {
            let frames = min(chunk, count - offset)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { break }
            buffer.frameLength = AVAudioFrameCount(frames)
            for c in channels.indices {
                channels[c].withUnsafeBufferPointer { buffer.floatChannelData![c].update(from: $0.baseAddress! + offset, count: frames) }
            }
            try file.write(from: buffer)
            offset += frames
        }
    }

    /// A media asset for a rendered library file.
    public static func asset(for sound: LibrarySound, url: URL, duration: Seconds?, cacheRoot: URL) async throws -> MediaAsset {
        var asset = try await MediaImporter.makeAsset(for: ImportPlan.Item(url: url, kind: .audio, role: sound.kind == .music ? .music : .soundEffect),
                                                      cacheRoot: cacheRoot)
        asset.name = sound.name
        asset.category = sound.kind == .music ? .music : .sfx
        asset.tags = sound.assetTags(duration: sound.kind == .music ? duration : nil)
        return asset
    }
}
