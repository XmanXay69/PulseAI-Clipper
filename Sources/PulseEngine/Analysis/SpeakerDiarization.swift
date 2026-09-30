import Accelerate
import AVFoundation
import Foundation
import PulseCore

/// Local speaker diarization: a voiceprint per speech segment (MFCC statistics + pitch), clustered
/// into speakers. Streams the audio once, so multi-hour recordings don't need to fit in memory.
public enum SpeakerDiarization {
    public static let sampleRate = 16_000.0
    static let frameLength = 400        // 25 ms
    static let hop = 160                // 10 ms
    static let fftSize = 512
    static let melBands = 26
    static let cepstra = 13

    /// Labels `transcript` with speakers. `delta` maps times: fileTime = transcriptTime + delta.
    /// `speakerCount` nil estimates the number of speakers.
    public static func diarize(_ transcript: Transcript, audioURL: URL, delta: Seconds = 0, speakerCount: Int? = nil,
                               isCancelled: @escaping @Sendable () -> Bool = { false }) async throws -> Transcript {
        let segments = SpeechSegmenter.segments(from: transcript)
        guard segments.count >= 2 else { return transcript }
        let ranges = segments.map { TimeRange(start: $0.range.start + delta, end: $0.range.end + delta) }
        let prints = try await voiceprints(url: audioURL, ranges: ranges, isCancelled: isCancelled)
        let usable = prints.indices.filter { prints[$0] != nil }
        guard usable.count >= 2 else { return transcript }
        let clustered = SpeakerClustering.cluster(usable.map { prints[$0]! }, speakerCount: speakerCount)
        // Segments without enough voiced audio take the previous segment's speaker.
        var labels = [Int](repeating: -1, count: segments.count)
        for (k, index) in usable.enumerated() { labels[index] = clustered[k] }
        var previous = clustered.first ?? 0
        for i in labels.indices {
            if labels[i] < 0 { labels[i] = previous } else { previous = labels[i] }
        }
        var result = transcript
        Diarizer.apply(labels: labels, segments: segments, to: &result)
        return result
    }

    /// One voiceprint per range (sorted, non-overlapping file-time ranges); nil when a range has
    /// too little voiced audio.
    public static func voiceprints(url: URL, ranges: [TimeRange], isCancelled: @escaping @Sendable () -> Bool = { false }) async throws -> [[Float]?] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw EngineError.noAudioTrack(url) }
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
        guard reader.startReading() else { throw EngineError.readerFailed(reader.error?.localizedDescription ?? "couldn't read audio for speakers") }

        let extractor = FrameFeatures()
        var stats = [SegmentStats](repeating: SegmentStats(), count: ranges.count)
        var pending: [Float] = []
        var consumed = 0          // samples dropped from the front of `pending`
        var frameIndex = 0
        var segment = 0
        while let buffer = output.copyNextSampleBuffer() {
            if isCancelled() { reader.cancelReading(); throw EngineError.cancelled }
            pending.append(contentsOf: SampleBufferReader.floats(from: buffer))
            while true {
                let start = frameIndex * hop
                guard start + frameLength <= consumed + pending.count else { break }
                let center = (Double(start) + Double(frameLength) / 2) / sampleRate
                while segment < ranges.count && ranges[segment].end < center { segment += 1 }
                if segment >= ranges.count { break }
                if ranges[segment].contains(center) {
                    let offset = start - consumed
                    pending.withUnsafeBufferPointer { p in
                        if let f = extractor.features(p.baseAddress! + offset, pitch: frameIndex % 2 == 0) { stats[segment].add(f) }
                    }
                }
                frameIndex += 1
            }
            if segment >= ranges.count { reader.cancelReading(); break }
            // Keep only what the next frame still needs.
            let keepFrom = frameIndex * hop - consumed
            if keepFrom > 0 && keepFrom <= pending.count {
                pending.removeFirst(keepFrom)
                consumed += keepFrom
            }
        }
        return stats.map { $0.voiceprint() }
    }

    struct Frame {
        var cepstra: [Float]    // c1…c12
        var logPitch: Float?
    }

    /// Running mean/variance of a segment's frames.
    struct SegmentStats {
        var count = 0
        var sum = [Float](repeating: 0, count: SpeakerDiarization.cepstra - 1)
        var sumSq = [Float](repeating: 0, count: SpeakerDiarization.cepstra - 1)
        var pitchCount = 0
        var pitchSum: Float = 0
        var pitchSumSq: Float = 0

        mutating func add(_ f: Frame) {
            count += 1
            for i in f.cepstra.indices {
                sum[i] += f.cepstra[i]
                sumSq[i] += f.cepstra[i] * f.cepstra[i]
            }
            if let p = f.logPitch {
                pitchCount += 1
                pitchSum += p
                pitchSumSq += p * p
            }
        }

        func voiceprint() -> [Float]? {
            guard count >= 15 else { return nil }
            let n = Float(count)
            let mean = sum.map { $0 / n }
            let sd = zip(sumSq, mean).map { max($0 / n - $1 * $1, 0).squareRoot() }
            let voiced = Float(pitchCount) / max(1, n / 2)
            let pitch = pitchCount > 3 ? pitchSum / Float(pitchCount) : log(150)
            let pitchSD = pitchCount > 3 ? max(pitchSumSq / Float(pitchCount) - pitch * pitch, 0).squareRoot() : 0
            // Pitch is the strongest single cue (it separates most voices), so it counts several times.
            return mean + sd + [pitch, pitch, pitch, pitch, pitchSD, voiced]
        }
    }

    /// MFCCs (Hamming window, 26 mel bands 60 Hz–7.6 kHz, DCT-II) and autocorrelation pitch per frame.
    final class FrameFeatures {
        let setup: FFTSetup
        let log2n = vDSP_Length(9)
        var window = [Float](repeating: 0, count: SpeakerDiarization.frameLength)
        var filters: [[(bin: Int, weight: Float)]] = []
        var dct: [[Float]] = []
        var windowed = [Float](repeating: 0, count: SpeakerDiarization.fftSize)
        var real = [Float](repeating: 0, count: SpeakerDiarization.fftSize / 2)
        var imag = [Float](repeating: 0, count: SpeakerDiarization.fftSize / 2)
        var padded = [Float](repeating: 0, count: SpeakerDiarization.frameLength + 240)
        var correlation = [Float](repeating: 0, count: 240)

        init() {
            setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
            vDSP_hamm_window(&window, vDSP_Length(SpeakerDiarization.frameLength), 0)
            // Mel filterbank.
            func mel(_ f: Double) -> Double { 2595 * log10(1 + f / 700) }
            func hz(_ m: Double) -> Double { 700 * (pow(10, m / 2595) - 1) }
            let bands = SpeakerDiarization.melBands, bins = SpeakerDiarization.fftSize / 2
            let lo = mel(60), hi = mel(7600)
            let points = (0...(bands + 1)).map { hz(lo + (hi - lo) * Double($0) / Double(bands + 1)) }
            let binOf = points.map { Int(($0 / SpeakerDiarization.sampleRate) * Double(SpeakerDiarization.fftSize)) }
            for b in 1...bands {
                var f: [(Int, Float)] = []
                let (l, c, r) = (binOf[b - 1], binOf[b], binOf[b + 1])
                for k in max(l, 0)...min(r, bins - 1) {
                    let w: Double = k < c ? Double(k - l) / Double(max(c - l, 1)) : Double(r - k) / Double(max(r - c, 1))
                    if w > 0 { f.append((k, Float(w))) }
                }
                filters.append(f)
            }
            // DCT-II rows 1…12 (c0 is loudness, left out so level doesn't matter).
            dct = (1..<SpeakerDiarization.cepstra).map { i in
                (0..<bands).map { j in Float(cos(Double.pi * Double(i) * (Double(j) + 0.5) / Double(bands))) }
            }
        }

        deinit { vDSP_destroy_fftsetup(setup) }

        func features(_ samples: UnsafePointer<Float>, pitch: Bool) -> Frame? {
            let n = SpeakerDiarization.frameLength
            // Level gate: skip near-silent frames (below about −50 dBFS).
            var ms: Float = 0
            vDSP_measqv(samples, 1, &ms, vDSP_Length(n))
            guard ms > 1e-5 else { return nil }
            // Pre-emphasis + window, zero-padded to the FFT size.
            for i in 0..<n {
                let x = samples[i] - (i > 0 ? 0.97 * samples[i - 1] : 0)
                windowed[i] = x * window[i]
            }
            for i in n..<SpeakerDiarization.fftSize { windowed[i] = 0 }
            let half = SpeakerDiarization.fftSize / 2
            var power = [Float](repeating: 0, count: half)
            real.withUnsafeMutableBufferPointer { rp in
                imag.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    windowed.withUnsafeBytes { raw in
                        vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half))
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(half))
                }
            }
            let logMel: [Float] = filters.map { f in
                var e: Float = 0
                for (bin, w) in f { e += power[bin] * w }
                return log(max(e, 1e-10))
            }
            let cepstra = dct.map { row in zip(row, logMel).reduce(Float(0)) { $0 + $1.0 * $1.1 } }

            var logPitch: Float?
            if pitch {
                // Normalized autocorrelation over 70–400 Hz lags.
                let minLag = Int(SpeakerDiarization.sampleRate / 400), maxLag = Int(SpeakerDiarization.sampleRate / 70)
                for i in 0..<n { padded[i] = samples[i] }
                for i in n..<padded.count { padded[i] = 0 }
                vDSP_conv(padded, 1, samples, 1, &correlation, 1, vDSP_Length(maxLag + 1), vDSP_Length(n))
                let energy = max(correlation[0], 1e-9)
                var bestLag = 0
                var best: Float = 0
                for lag in minLag...maxLag {
                    // Compensate for the shrinking overlap at longer lags.
                    let r = correlation[lag] / energy * Float(n) / Float(n - lag)
                    if r > best { best = r; bestLag = lag }
                }
                if best > 0.5, bestLag > 0 { logPitch = log(Float(SpeakerDiarization.sampleRate) / Float(bestLag)) }
            }
            return Frame(cepstra: cepstra, logPitch: logPitch)
        }
    }
}
