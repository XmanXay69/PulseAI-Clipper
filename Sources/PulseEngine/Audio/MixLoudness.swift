import AVFoundation
import Foundation
import PulseCore

/// Measures the finished mix exactly as an export would hear it (same composition, same audio mix, every
/// Enhance render applied): BS.1770 integrated loudness and sample peak. Used by the export loudness check.
public enum MixLoudness {
    public struct Measurement: Sendable {
        public var lufs: Double
        public var peakDB: Double
        /// Inter-sample ("true") peak in dBTP (#280), from 4× cubic oversampling; platforms want ≤ −1 dBTP.
        public var truePeakDB: Double = -.infinity
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
        var truePeak: Float = 0
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
            truePeak = max(truePeak, Self.interSamplePeak(left), Self.interSamplePeak(right))
            frames += count
            let fraction = min(1, Double(frames) / total)
            if fraction - lastReported >= 0.01 {
                lastReported = fraction
                progress?(fraction)
            }
        }
        if reader.status == .failed { throw EngineError.readerFailed(reader.error?.localizedDescription ?? "Couldn't read the mix") }
        var result = Measurement(lufs: meter.integratedLUFS, peakDB: meter.peakDB)
        result.truePeakDB = truePeak > 0 ? 20 * log10(Double(truePeak)) : -.infinity
        PulseLog.info(String(format: "Loudness check: %.1f LUFS, peak %.1f dBFS, true peak %.1f dBTP", result.lufs, result.peakDB, result.truePeakDB))
        return result
    }

    /// The largest absolute value the waveform reaches between samples, from Catmull-Rom interpolation at
    /// quarter-sample points: close enough to the broadcast 4× oversampled true-peak meter for a readout.
    static func interSamplePeak(_ x: [Float]) -> Float {
        guard x.count >= 4 else { return x.map { abs($0) }.max() ?? 0 }
        var peak: Float = 0
        for i in 1..<(x.count - 2) {
            let p0 = x[i - 1], p1 = x[i], p2 = x[i + 1], p3 = x[i + 2]
            peak = max(peak, abs(p1))
            for t in [Float(0.25), 0.5, 0.75] {
                let t2 = t * t, t3 = t2 * t
                let v = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
                peak = max(peak, abs(v))
            }
        }
        return peak
    }
}
