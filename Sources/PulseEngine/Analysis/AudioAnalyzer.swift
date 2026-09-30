import Accelerate
import AVFoundation
import Foundation
import PulseCore

/// Streams an asset's audio once (never loading it into RAM) and produces:
///  * `AudioFeatureSeries` (RMS / peak / zero-crossing / spectral flux at 10 Hz)
///  * optionally a 16 kHz mono WAV used by speech-to-text engines.
public final class AudioAnalyzer: @unchecked Sendable {
    public static let analysisSampleRate: Double = 16_000
    public static let hop: Seconds = 0.1

    public struct Result: Sendable {
        public var features: AudioFeatureSeries
        public var wavURL: URL?
    }

    private let fftSize = 1024
    private let log2n: vDSP_Length = 10
    private let fftSetup: FFTSetup
    private var window: [Float]
    private var previousMagnitudes: [Float]

    public init() {
        fftSetup = vDSP_create_fftsetup(10, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: 1024)
        vDSP_hann_window(&window, vDSP_Length(1024), Int32(vDSP_HANN_NORM))
        previousMagnitudes = [Float](repeating: 0, count: 512)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// - Parameters:
    ///   - writeWAVTo: when set, also writes 16 kHz mono PCM for transcription.
    public func analyze(url: URL, writeWAVTo wavURL: URL? = nil, progress: ProgressHandler? = nil, isCancelled: @escaping @Sendable () -> Bool = { false }) async throws -> Result {
        let asset = AVURLAsset(url: url)
        let (duration, tracks) = try await asset.load(.duration, .tracks)
        let audioTracks = tracks.filter { $0.mediaType == .audio }
        guard let track = audioTracks.first else { throw EngineError.noAudioTrack(url) }
        let total = max(duration.secondsValue, 0.001)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: AudioAnalyzer.analysisSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else {
            throw EngineError.readerFailed(reader.error?.localizedDescription ?? "couldn't start reading audio")
        }

        var wavFile: AVAudioFile?
        let wavFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioAnalyzer.analysisSampleRate, channels: 1, interleaved: false)!
        if let wavURL {
            try? FileManager.default.removeItem(at: wavURL)
            wavFile = try AVAudioFile(forWriting: wavURL, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: AudioAnalyzer.analysisSampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
            ], commonFormat: .pcmFormatFloat32, interleaved: false)
        }

        let hopSamples = Int(AudioAnalyzer.analysisSampleRate * AudioAnalyzer.hop)
        var pending: [Float] = []
        pending.reserveCapacity(hopSamples * 4)
        var rms: [Float] = []
        var peak: [Float] = []
        var zcr: [Float] = []
        var flux: [Float] = []
        let expectedHops = Int(total / AudioAnalyzer.hop) + 2
        rms.reserveCapacity(expectedHops)
        peak.reserveCapacity(expectedHops)
        zcr.reserveCapacity(expectedHops)
        flux.reserveCapacity(expectedHops)
        var processedSamples = 0
        var lastReported = -1.0

        while let buffer = output.copyNextSampleBuffer() {
            if isCancelled() {
                reader.cancelReading()
                throw EngineError.cancelled
            }
            let samples = SampleBufferReader.floats(from: buffer)
            if samples.isEmpty { continue }
            if let wavFile, let pcm = AVAudioPCMBuffer(pcmFormat: wavFormat, frameCapacity: AVAudioFrameCount(samples.count)) {
                pcm.frameLength = AVAudioFrameCount(samples.count)
                samples.withUnsafeBufferPointer { src in
                    pcm.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
                }
                try wavFile.write(from: pcm)
            }
            pending.append(contentsOf: samples)
            var offset = 0
            while pending.count - offset >= hopSamples {
                let features = computeHop(pending, offset: offset, count: hopSamples)
                rms.append(features.rms)
                peak.append(features.peak)
                zcr.append(features.zcr)
                flux.append(features.flux)
                offset += hopSamples
            }
            if offset > 0 { pending.removeFirst(offset) }
            processedSamples += samples.count
            let fraction = Double(processedSamples) / (total * AudioAnalyzer.analysisSampleRate)
            if fraction - lastReported > 0.01 {
                lastReported = fraction
                progress?(EngineProgress(stage: "Analyzing audio", fraction: min(fraction, 1)))
            }
        }
        if reader.status == .failed {
            throw EngineError.readerFailed(reader.error?.localizedDescription ?? "audio decoding failed")
        }
        if !pending.isEmpty {
            let padded = pending + [Float](repeating: 0, count: max(0, hopSamples - pending.count))
            let features = computeHop(padded, offset: 0, count: hopSamples)
            rms.append(features.rms)
            peak.append(features.peak)
            zcr.append(features.zcr)
            flux.append(features.flux)
        }
        let series = AudioFeatureSeries(hop: AudioAnalyzer.hop, rmsDB: rms, peakDB: peak, zeroCrossingRate: zcr, spectralFlux: flux)
        return Result(features: series, wavURL: wavFile != nil ? wavURL : nil)
    }

    private func computeHop(_ samples: [Float], offset: Int, count: Int) -> (rms: Float, peak: Float, zcr: Float, flux: Float) {
        var meanSquare: Float = 0
        var maxMagnitude: Float = 0
        var crossings = 0
        samples.withUnsafeBufferPointer { buf in
            let base = buf.baseAddress! + offset
            vDSP_measqv(base, 1, &meanSquare, vDSP_Length(count))
            vDSP_maxmgv(base, 1, &maxMagnitude, vDSP_Length(count))
            var previous = base[0]
            for i in 1..<count {
                let v = base[i]
                if (v >= 0) != (previous >= 0) { crossings += 1 }
                previous = v
            }
        }
        let rmsDB = 10 * log10(max(meanSquare, 1e-10))
        let peakDB = 20 * log10(max(maxMagnitude, 1e-5))
        let flux = spectralFlux(samples, offset: offset + max(0, (count - fftSize) / 2))
        return (max(rmsDB, -100), max(peakDB, -100), Float(crossings) / Float(count), flux)
    }

    /// Positive spectral change vs the previous hop (onset strength).
    private func spectralFlux(_ samples: [Float], offset: Int) -> Float {
        let n = fftSize
        guard offset + n <= samples.count else { return 0 }
        var windowed = [Float](repeating: 0, count: n)
        samples.withUnsafeBufferPointer { buf in
            vDSP_vmul(buf.baseAddress! + offset, 1, window, 1, &windowed, 1, vDSP_Length(n))
        }
        var real = [Float](repeating: 0, count: n / 2)
        var imag = [Float](repeating: 0, count: n / 2)
        var magnitudes = [Float](repeating: 0, count: n / 2)
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { w in
                    w.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(n / 2))
            }
        }
        var total: Float = 0
        for i in 0..<(n / 2) {
            let diff = magnitudes[i] - previousMagnitudes[i]
            if diff > 0 { total += diff }
        }
        previousMagnitudes = magnitudes
        return log1p(total / Float(n))
    }
}
