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
}
