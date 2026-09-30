import Accelerate
import XCTest
@testable import PulseCore

final class AudioDSPTests: XCTestCase {
    let rate = 48_000.0

    func sine(_ frequency: Double, amplitude: Float, seconds: Double) -> [Float] {
        let n = Int(seconds * rate)
        return (0..<n).map { amplitude * Float(sin(2 * Double.pi * frequency * Double($0) / rate)) }
    }

    func rmsDB(_ x: ArraySlice<Float>) -> Double {
        let ms = x.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(x.count, 1))
        return 10 * log10(max(ms, 1e-20))
    }

    func rmsDB(_ x: [Float]) -> Double { rmsDB(x[...]) }

    func testHighPassRemovesRumbleAndKeepsVoiceBand() {
        var low = sine(30, amplitude: 0.5, seconds: 1)
        var mid = sine(2000, amplitude: 0.5, seconds: 1)
        let lowBefore = rmsDB(low), midBefore = rmsDB(mid)
        var f1 = Biquad.highPass(frequency: 200, sampleRate: rate)
        var f2 = Biquad.highPass(frequency: 200, sampleRate: rate)
        f1.process(&low)
        f2.process(&mid)
        XCTAssertLessThan(rmsDB(low[4800...]) - lowBefore, -20)
        XCTAssertEqual(rmsDB(mid[4800...]), midBefore, accuracy: 0.5)
    }

    func testPeakingEQBoostsCentreFrequency() {
        var x = sine(1200, amplitude: 0.1, seconds: 0.5)
        let before = rmsDB(x)
        var eq = Biquad.peaking(frequency: 1200, gainDB: 6, q: 0.8, sampleRate: rate)
        eq.process(&x)
        XCTAssertEqual(rmsDB(x[4800...]) - before, 6, accuracy: 0.5)
    }

    func testLoudnessOfFullScaleSineIsAboutMinus3LUFS() {
        // BS.1770: a 0 dBFS ~1 kHz sine in one channel measures ≈ −3.0 LUFS.
        let lufs = LoudnessMeter.integratedLUFS([sine(997, amplitude: 1, seconds: 3)], sampleRate: rate)
        XCTAssertEqual(lufs, -3.01, accuracy: 0.3)
    }

    func testSilenceHasNoLoudness() {
        let lufs = LoudnessMeter.integratedLUFS([[Float](repeating: 0, count: 48_000)], sampleRate: rate)
        XCTAssertFalse(lufs.isFinite)
    }

    func testNormalizeReachesPlatformTarget() {
        var channels = [sine(440, amplitude: 0.03, seconds: 4), sine(440, amplitude: 0.03, seconds: 4)]
        var settings = AudioSettings()
        settings.normalize = true
        AudioEnhanceChain.process(&channels, sampleRate: rate, settings: settings)
        let lufs = LoudnessMeter.integratedLUFS(channels, sampleRate: rate)
        XCTAssertEqual(lufs, AudioEnhanceChain.targetLUFS, accuracy: 1)
        XCTAssertLessThanOrEqual(LoudnessMeter.samplePeak(channels), Float(pow(10, AudioEnhanceChain.ceilingDB / 20)) + 1e-4)
    }

    func testLimiterNeverExceedsCeiling() {
        var channels = [sine(220, amplitude: 2, seconds: 1)]
        AudioEnhanceChain.limit(&channels, sampleRate: rate, ceilingDB: -1)
        XCTAssertLessThanOrEqual(LoudnessMeter.samplePeak(channels), Float(pow(10, -1.0 / 20)) + 1e-5)
        // Quiet material is untouched.
        var quiet = [sine(220, amplitude: 0.2, seconds: 0.5)]
        let copy = quiet
        AudioEnhanceChain.limit(&quiet, sampleRate: rate, ceilingDB: -1)
        XCTAssertEqual(quiet[0], copy[0])
    }

    func testCompressorReducesLoudPartsMoreThanQuietParts() {
        let loud = sine(500, amplitude: 0.9, seconds: 1)
        let quiet = sine(500, amplitude: 0.02, seconds: 1)
        var channels = [loud + quiet]
        AudioEnhanceChain.compress(&channels, sampleRate: rate, thresholdDB: -20, ratio: 4, makeupDB: 0)
        let n = loud.count
        let loudChange = rmsDB(channels[0][(n / 2)..<n]) - rmsDB(loud[(n / 2)..<n])
        let quietChange = rmsDB(channels[0][(n + n / 2)...]) - rmsDB(quiet[(n / 2)...])
        XCTAssertLessThan(loudChange, -8)
        XCTAssertEqual(quietChange, 0, accuracy: 0.5)
    }

    func testNoiseReductionLowersTheFloorButKeepsSpeech() {
        var generator = SeededGenerator(seed: 7)
        let n = Int(2 * rate)
        var signal = (0..<n).map { _ in Float.random(in: -0.004...0.004, using: &generator) }
        let burst = sine(300, amplitude: 0.3, seconds: 0.6)
        let burstStart = Int(0.7 * rate)
        for i in burst.indices { signal[burstStart + i] += burst[i] }
        let noiseBefore = rmsDB(signal[0..<Int(0.5 * rate)])
        let speechBefore = rmsDB(signal[(burstStart + 4800)..<(burstStart + burst.count - 4800)])
        var channels = [signal]
        AudioEnhanceChain.expand(&channels, sampleRate: rate, amount: 1)
        let noiseAfter = rmsDB(channels[0][0..<Int(0.5 * rate)])
        let speechAfter = rmsDB(channels[0][(burstStart + 4800)..<(burstStart + burst.count - 4800)])
        XCTAssertLessThan(noiseAfter - noiseBefore, -10)
        XCTAssertEqual(speechAfter, speechBefore, accuracy: 1)
    }

    func testSpectralDenoiserReconstructsExactlyWithUnityGain() {
        var generator = SeededGenerator(seed: 11)
        let input = (0..<20_000).map { _ in Float.random(in: -0.5...0.5, using: &generator) }
        let log2n = vDSP_Length(log2(Double(SpectralDenoiser.frameSize)))
        let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        defer { vDSP_destroy_fftsetup(setup) }
        var window = [Float](repeating: 0, count: SpectralDenoiser.frameSize)
        vDSP_hann_window(&window, vDSP_Length(SpectralDenoiser.frameSize), Int32(vDSP_HANN_DENORM))
        let output = SpectralDenoiser.denoise(input, setup: setup, log2n: log2n, window: window, oversubtraction: 0, floorGain: 1)
        XCTAssertEqual(output.count, input.count)
        let maxError = zip(input, output).map { abs($0 - $1) }.max() ?? 1
        XCTAssertLessThan(maxError, 1e-4)
    }

    func testSpectralDenoiserRemovesSteadyNoiseUnderAndAroundSpeech() {
        var generator = SeededGenerator(seed: 5)
        let n = Int(3 * rate)
        var signal = (0..<n).map { _ in Float.random(in: -0.02...0.02, using: &generator) }
        let tone = sine(1000, amplitude: 0.3, seconds: 1)
        let toneStart = Int(1 * rate)
        for i in tone.indices { signal[toneStart + i] += tone[i] }
        let noiseBefore = rmsDB(signal[0..<Int(0.8 * rate)])
        let toneBefore = rmsDB(signal[(toneStart + 4800)..<(toneStart + tone.count - 4800)])
        var channels = [signal]
        SpectralDenoiser.process(&channels, amount: 1)
        let noiseAfter = rmsDB(channels[0][Int(0.1 * rate)..<Int(0.8 * rate)])
        let toneAfter = rmsDB(channels[0][(toneStart + 4800)..<(toneStart + tone.count - 4800)])
        XCTAssertLessThan(noiseAfter - noiseBefore, -12)
        XCTAssertEqual(toneAfter, toneBefore, accuracy: 1.5)
    }

    func testEnhanceFlagsAndFingerprint() {
        var settings = AudioSettings()
        XCTAssertFalse(settings.needsEnhanceRender)
        let plain = settings.enhanceFingerprint
        settings.applyVoicePreset()
        XCTAssertTrue(settings.needsEnhanceRender)
        XCTAssertNotEqual(settings.enhanceFingerprint, plain)
        settings.isMuted = true
        XCTAssertFalse(settings.needsEnhanceRender)
        XCTAssertEqual(StableHash.fnv1a("pulse"), StableHash.fnv1a("pulse"))
        XCTAssertNotEqual(StableHash.fnv1a("pulse"), StableHash.fnv1a("pulsE"))
    }

    func testPanMovesMonoAndBalancesStereo() {
        var mono = [sine(440, amplitude: 0.5, seconds: 0.2)]
        AudioEnhanceChain.applyPan(&mono, pan: -1)
        XCTAssertEqual(mono.count, 2)
        XCTAssertGreaterThan(rmsDB(mono[0]), -10)
        XCTAssertLessThan(rmsDB(mono[1]), -60)
        var stereo = [sine(440, amplitude: 0.5, seconds: 0.2), sine(440, amplitude: 0.5, seconds: 0.2)]
        let before = rmsDB(stereo[0])
        AudioEnhanceChain.applyPan(&stereo, pan: 0.5)
        XCTAssertEqual(rmsDB(stereo[1]), before, accuracy: 0.01)
        XCTAssertEqual(rmsDB(stereo[0]) - before, 20 * log10(0.5), accuracy: 0.01)
    }

    func testVoicePresetChainStaysFiniteAndUnderCeiling() {
        var channels = [sine(180, amplitude: 0.4, seconds: 1) , sine(180, amplitude: 0.4, seconds: 1)]
        var settings = AudioSettings()
        settings.applyVoicePreset()
        settings.eq.isEnabled = true
        settings.eq.highGain = 3
        AudioEnhanceChain.process(&channels, sampleRate: rate, settings: settings)
        XCTAssertTrue(channels.allSatisfy { $0.allSatisfy(\.isFinite) })
        XCTAssertLessThanOrEqual(LoudnessMeter.samplePeak(channels), Float(pow(10, AudioEnhanceChain.ceilingDB / 20)) + 1e-4)
    }

    func testVoiceIsolatorIsMixedByAmountAndFallsBackToClassic() {
        var generator = SeededGenerator(seed: 11)
        let voice = sine(220, amplitude: 0.2, seconds: 1)
        let noise = (0..<voice.count).map { _ in Float.random(in: -0.05...0.05, using: &generator) }
        let noisy = zip(voice, noise).map(+)
        var settings = AudioSettings()
        XCTAssertEqual(settings.noiseMethod, .voiceIsolation, "new clips use the neural isolator")
        settings.noiseReduction = 0.7
        // A perfect isolator: returns the voice alone.
        let perfect: AudioEnhanceChain.VoiceIsolator = { channels, _ in channels = [voice]; return true }
        var channels = [noisy]
        XCTAssertEqual(AudioEnhanceChain.process(&channels, sampleRate: rate, settings: settings, voiceIsolator: perfect), .voiceIsolation)
        let residual = zip(channels[0], voice).map { $0 - $1 }
        let keep = AudioEnhanceChain.backgroundGain(amount: 0.7)
        XCTAssertEqual(keep, 0.09, accuracy: 0.001)
        XCTAssertEqual(rmsDB(residual) - rmsDB(noise), 20 * log10(Double(keep)), accuracy: 0.1, "background kept at the amount's level")
        // Amount 1 = voice only.
        settings.noiseReduction = 1
        channels = [noisy]
        AudioEnhanceChain.process(&channels, sampleRate: rate, settings: settings, voiceIsolator: perfect)
        XCTAssertEqual(channels[0], voice)
        // Isolator unavailable → classic noise reduction, input untouched by the failed attempt.
        let failing: AudioEnhanceChain.VoiceIsolator = { channels, _ in channels = [[]]; return false }
        channels = [noisy]
        XCTAssertEqual(AudioEnhanceChain.process(&channels, sampleRate: rate, settings: settings, voiceIsolator: failing), .spectral)
        XCTAssertEqual(channels[0].count, noisy.count)
        // Classic mode never calls the isolator.
        settings.noiseMethod = .spectral
        channels = [noisy]
        XCTAssertEqual(AudioEnhanceChain.process(&channels, sampleRate: rate, settings: settings, voiceIsolator: perfect), .spectral)
        XCTAssertNotEqual(channels[0], voice)
        // No noise reduction → no method.
        settings.noiseReduction = 0
        XCTAssertNil(AudioEnhanceChain.process(&channels, sampleRate: rate, settings: settings, voiceIsolator: perfect))
    }

    func testNoiseMethodFingerprintAndOldProjects() throws {
        var a = AudioSettings()
        a.noiseReduction = 0.5
        var b = a
        b.noiseMethod = .spectral
        XCTAssertNotEqual(a.enhanceFingerprint, b.enhanceFingerprint)
        // Saved before the neural option existed: keeps classic noise reduction (and its cache key).
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as! [String: Any]
        json.removeValue(forKey: "noiseMethod")
        let old = try JSONDecoder().decode(AudioSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.noiseMethod, .spectral)
        XCTAssertEqual(old.enhanceFingerprint, b.enhanceFingerprint)
    }

    func testSignalAlignmentFindsProcessingDelay() {
        var generator = SeededGenerator(seed: 5)
        let reference = (0..<Int(rate * 2)).map { i in
            Float(sin(Double(i) * 0.013)) * 0.3 + Float.random(in: -0.1...0.1, using: &generator)
        }
        for delay in [0, 7, 480, 2917] {
            let delayed = [Float](repeating: 0, count: delay) + reference.map { $0 * 0.5 } + [Float](repeating: 0, count: 6000)
            let found = SignalAlignment.delay(of: delayed, relativeTo: reference, maxLag: 6000)
            XCTAssertEqual(found.lag, delay)
            XCTAssertGreaterThan(found.correlation, 0.99)
        }
    }
}
