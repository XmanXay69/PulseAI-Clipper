import Accelerate
import Foundation

/// Spectral-subtraction noise reduction (STFT, 75 % overlap, Hann windows).
///
/// 1. The noise spectrum is learned from the quietest ~10 % of frames (room tone, fan, hiss).
/// 2. Each frame's bins are attenuated by `1 − k·noise/|X|`, never below a floor, with temporal
///    smoothing to avoid "musical noise".
/// 3. Frames are resynthesized with overlap-add, so untouched bins are reconstructed exactly.
public enum SpectralDenoiser {
    public static let frameSize = 1024
    public static let hop = 256

    public static func process(_ channels: inout [[Float]], amount: Double) {
        guard amount > 0.001, let length = channels.first?.count, length > frameSize * 2 else { return }
        let log2n = vDSP_Length(log2(Double(frameSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return }
        defer { vDSP_destroy_fftsetup(setup) }
        var window = [Float](repeating: 0, count: frameSize)
        vDSP_hann_window(&window, vDSP_Length(frameSize), Int32(vDSP_HANN_DENORM))
        let amount = Float(min(max(amount, 0), 1))
        let oversubtraction: Float = 1 + 1.5 * amount
        let floorGain: Float = pow(10, -(6 + 18 * amount) / 20)
        for c in channels.indices {
            channels[c] = denoise(channels[c], setup: setup, log2n: log2n, window: window, oversubtraction: oversubtraction, floorGain: floorGain)
        }
    }

    static func denoise(_ input: [Float], setup: FFTSetup, log2n: vDSP_Length, window: [Float], oversubtraction: Float, floorGain: Float) -> [Float] {
        let n = frameSize, half = n / 2
        // Pad so every sample is covered by the same number of frames.
        let padded = [Float](repeating: 0, count: n) + input + [Float](repeating: 0, count: n)
        let frameCount = (padded.count - n) / hop + 1

        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var frame = [Float](repeating: 0, count: n)
        var energies = [Float](repeating: 0, count: frameCount)

        func windowed(_ start: Int) {
            padded.withUnsafeBufferPointer { src in
                vDSP_vmul(src.baseAddress! + start, 1, window, 1, &frame, 1, vDSP_Length(n))
            }
        }

        func forward(_ start: Int) {
            windowed(start)
            real.withUnsafeMutableBufferPointer { rp in
                imag.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    frame.withUnsafeBytes { raw in
                        vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half))
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }
        }

        // Pass 1: frame energies (time domain — proportional to spectral energy by Parseval).
        for f in 0..<frameCount {
            windowed(f * hop)
            var e: Float = 0
            vDSP_svesq(frame, 1, &e, vDSP_Length(n))
            energies[f] = e
        }
        let voiced = energies.enumerated().filter { $0.element > 1e-12 }.sorted { $0.element < $1.element }
        guard !voiced.isEmpty else { return input }
        // Learn the noise spectrum from the quietest 10 % of frames.
        let quietCount = max(1, voiced.count / 10)
        var noise = [Float](repeating: 0, count: half)
        for (index, _) in voiced.prefix(quietCount) {
            forward(index * hop)
            for k in 0..<half { noise[k] += (real[k] * real[k] + imag[k] * imag[k]).squareRoot() }
        }
        var scale = 1 / Float(quietCount)
        vDSP_vsmul(noise, 1, &scale, &noise, 1, vDSP_Length(half))

        // Pass 2: gains, inverse FFT, overlap-add.
        var output = [Float](repeating: 0, count: padded.count)
        var previousGain = [Float](repeating: 1, count: half)
        // Hann analysis × Hann synthesis at 75 % overlap sums to 1.5; FFT round trip scales by 2n.
        let synthesisScale = 1 / (Float(2 * n) * 1.5)
        for f in 0..<frameCount {
            forward(f * hop)
            for k in 0..<half {
                let magnitude = (real[k] * real[k] + imag[k] * imag[k]).squareRoot()
                let raw = magnitude > 1e-9 ? max(floorGain, 1 - oversubtraction * noise[k] / magnitude) : floorGain
                // Fast attack when speech appears, slower release to suppress musical noise.
                let g = raw > previousGain[k] ? raw : 0.6 * previousGain[k] + 0.4 * raw
                previousGain[k] = g
                real[k] *= g
                imag[k] *= g
            }
            real.withUnsafeMutableBufferPointer { rp in
                imag.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_INVERSE))
                    frame.withUnsafeMutableBytes { raw in
                        vDSP_ztoc(&split, 1, raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, vDSP_Length(half))
                    }
                }
            }
            let start = f * hop
            for i in 0..<n { output[start + i] += frame[i] * window[i] * synthesisScale }
        }
        return Array(output[n..<(n + input.count)])
    }
}
