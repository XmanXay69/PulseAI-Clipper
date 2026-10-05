import AVFoundation
import Foundation
import PulseCore

/// Finds where the beats are in a music track (for the "Beat-synced music & zooms" extra): an onset envelope
/// from rising energy in the kick and hi-hat bands, then `BeatSync.beats`. Results are cached per file.
public actor BeatDetector {
    public static let shared = BeatDetector()
    static let sampleRate = 11_025.0
    static let hopSamples = 128

    private var cache: [URL: [Seconds]] = [:]

    public init() {}

    /// Beat times in the file's own time (seconds from its start). Empty when no steady beat was found.
    public func beats(url: URL) async throws -> [Seconds] {
        if let cached = cache[url] { return cached }
        let (onsets, duration) = try await Self.onsetEnvelope(url: url)
        let grid = BeatSync.beats(onsets: onsets, hop: Double(Self.hopSamples) / Self.sampleRate, duration: duration)
        cache[url] = grid
        PulseLog.info("Beats: \(grid.count) in “\(url.lastPathComponent)”\(grid.count > 1 ? String(format: " (~%.0f BPM)", 60 / ((grid.last! - grid.first!) / Double(grid.count - 1))) : "")")
        return grid
    }

    static func onsetEnvelope(url: URL) async throws -> (onsets: [Float], duration: Seconds) {
        let asset = AVURLAsset(url: url)
        let (length, tracks) = try await asset.load(.duration, .tracks)
        guard let track = tracks.first(where: { $0.mediaType == .audio }) else { throw EngineError.noAudioTrack(url) }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw EngineError.readerFailed(reader.error?.localizedDescription ?? "couldn't read the music") }

        var low = Biquad.lowPass(frequency: 160, sampleRate: sampleRate)
        var high = Biquad.highPass(frequency: 2_500, sampleRate: sampleRate)
        var pending: [Float] = []
        var lowEnergy: [Float] = [], highEnergy: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            pending += SampleBufferReader.floats(from: buffer)
            var offset = 0
            while pending.count - offset >= hopSamples {
                var l: Float = 0, h: Float = 0
                for i in offset..<(offset + hopSamples) {
                    let x = Double(pending[i])
                    let lo = Float(low.process(x)), hi = Float(high.process(x))
                    l += lo * lo
                    h += hi * hi
                }
                lowEnergy.append(l)
                highEnergy.append(h)
                offset += hopSamples
            }
            if offset > 0 { pending.removeFirst(offset) }
        }
        if reader.status == .failed { throw EngineError.readerFailed(reader.error?.localizedDescription ?? "couldn't decode the music") }
        // Rising log-energy in each band (onsets), summed.
        func flux(_ e: [Float]) -> [Float] {
            let compressed = e.map { log1p(1_000 * $0) }
            return compressed.indices.map { $0 == 0 ? 0 : max(0, compressed[$0] - compressed[$0 - 1]) }
        }
        let a = flux(lowEnergy), b = flux(highEnergy)
        return (zip(a, b).map { $0 + 0.6 * $1 }, length.secondsValue)
    }
}
