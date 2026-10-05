import AVFoundation
import Foundation
import PulseCore

/// Measures the finished mix exactly as an export would hear it (same composition, same audio mix, every
/// Enhance render applied): BS.1770 integrated loudness and sample peak. Used by the export loudness check.
public enum MixLoudness {
    public struct Measurement: Sendable {
        public var lufs: Double
        public var peakDB: Double
    }

    public static func measure(timeline: Timeline, assets: [UUID: MediaAsset], compounds: [UUID: Timeline] = [:],
                               progress: (@Sendable (Double) -> Void)? = nil) async throws -> Measurement {
        var options = CompositionBuilder.Options(includeCaptions: false)
        options.compounds = compounds
        let built = try await CompositionBuilder.build(timeline: timeline, assets: assets, options: options)
        let audioTracks = try await built.composition.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { return Measurement(lufs: -.infinity, peakDB: -.infinity) }
        let reader = try AVAssetReader(asset: built.composition)
        reader.timeRange = CMTimeRange(start: .zero, duration: .seconds(built.duration))
        let rate = 48_000.0
        let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        output.audioMix = built.audioMix
        output.audioTimePitchAlgorithm = .spectral
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw EngineError.readerFailed("Couldn't read the mix") }
        reader.add(output)
        guard reader.startReading() else { throw EngineError.readerFailed(reader.error?.localizedDescription ?? "Couldn't read the mix") }

        var meter = StreamingLoudness(sampleRate: rate)
        var frames = 0
        var lastReported = -1.0
        let total = max(built.duration * rate, 1)
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let interleaved = SampleBufferReader.floats(from: buffer)
            let count = interleaved.count / 2
            guard count > 0 else { continue }
            var left = [Float](repeating: 0, count: count), right = [Float](repeating: 0, count: count)
            for i in 0..<count {
                left[i] = interleaved[2 * i]
                right[i] = interleaved[2 * i + 1]
            }
            meter.add([left, right])
            frames += count
            let fraction = min(1, Double(frames) / total)
            if fraction - lastReported >= 0.01 {
                lastReported = fraction
                progress?(fraction)
            }
        }
        if reader.status == .failed { throw EngineError.readerFailed(reader.error?.localizedDescription ?? "Couldn't read the mix") }
        let result = Measurement(lufs: meter.integratedLUFS, peakDB: meter.peakDB)
        PulseLog.info(String(format: "Loudness check: %.1f LUFS, peak %.1f dBFS", result.lufs, result.peakDB))
        return result
    }
}
