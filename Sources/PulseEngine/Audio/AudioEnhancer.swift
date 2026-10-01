import AVFoundation
import Foundation
import PulseCore

/// Renders a clip's "Enhance" chain (EQ, voice, noise reduction, compressor, loudness, limiter)
/// into a cached PCM file covering exactly the clip's source range. The composition then uses the
/// processed file instead of the original, so playback and export sound identical and the edit
/// stays non-destructive (change a setting → a new cache entry; the source is never touched).
public actor AudioEnhancer {
    public static let shared = AudioEnhancer()
    public static let sampleRate = 48_000.0

    private var inFlight: [String: Task<URL, Error>] = [:]

    public init() {}

    /// Returns the processed file (rendering it on first use).
    public func render(sourceURL: URL, range: TimeRange, settings: AudioSettings, cacheDirectory: URL) async throws -> URL {
        let attributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = StableHash.fnv1a("\(sourceURL.path)|\(size)|\(modified)|\(String(format: "%.4f-%.4f", range.start, range.end))|\(settings.enhanceFingerprint)")
        let directory = PulseDirectories.ensure(cacheDirectory)
        let output = directory.appendingPathComponent("enh-\(key).caf")
        if FileManager.default.fileExists(atPath: output.path) { return output }
        if let running = inFlight[key] { return try await running.value }
        let task = Task.detached(priority: .userInitiated) {
            try await AudioEnhancer.process(sourceURL: sourceURL, range: range, settings: settings, output: output)
            return output
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }

    /// Decodes the range to float PCM, runs the chain, writes a CAF next to other caches.
    static func process(sourceURL: URL, range: TimeRange, settings: AudioSettings, output: URL) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw EngineError.noAudioTrack(sourceURL) }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: .seconds(range.start), duration: .seconds(range.duration))
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        trackOutput.alwaysCopiesSampleData = false
        reader.add(trackOutput)
        guard reader.startReading() else {
            throw EngineError.readerFailed(reader.error?.localizedDescription ?? "couldn't read audio for enhancement")
        }

        var channelCount = 0
        var channels: [[Float]] = []
        while let buffer = trackOutput.copyNextSampleBuffer() {
            if channelCount == 0, let format = CMSampleBufferGetFormatDescription(buffer),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                channelCount = max(1, Int(asbd.mChannelsPerFrame))
                channels = Array(repeating: [], count: channelCount)
                let expected = Int(range.duration * sampleRate) + 4096
                for c in 0..<channelCount { channels[c].reserveCapacity(expected) }
            }
            let interleaved = SampleBufferReader.floats(from: buffer)
            guard channelCount > 0 else { continue }
            let frames = interleaved.count / channelCount
            for c in 0..<channelCount {
                var i = c
                for _ in 0..<frames {
                    channels[c].append(interleaved[i])
                    i += channelCount
                }
            }
        }
        if reader.status == .failed {
            throw EngineError.readerFailed(reader.error?.localizedDescription ?? "audio decode failed")
        }
        guard channelCount > 0, let frames = channels.first?.count, frames > 0 else { throw EngineError.noAudioTrack(sourceURL) }

        AudioEnhanceChain.process(&channels, sampleRate: sampleRate, settings: settings, voiceIsolator: VoiceIsolation.isolator)
        // Panning can turn mono into stereo.
        let outputChannels = channels.count

        let temp = output.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".caf")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: AVAudioChannelCount(outputChannels), interleaved: false)!
        do {
            let file = try AVAudioFile(forWriting: temp, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let chunk = 65_536
            var offset = 0
            while offset < frames {
                let count = min(chunk, frames - offset)
                guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                      let data = pcm.floatChannelData else { break }
                pcm.frameLength = AVAudioFrameCount(count)
                for c in 0..<outputChannels {
                    channels[c].withUnsafeBufferPointer { src in
                        data[c].update(from: src.baseAddress! + offset, count: count)
                    }
                }
                try file.write(from: pcm)
                offset += count
            }
        }
        try? FileManager.default.removeItem(at: output)
        try FileManager.default.moveItem(at: temp, to: output)
    }
}
