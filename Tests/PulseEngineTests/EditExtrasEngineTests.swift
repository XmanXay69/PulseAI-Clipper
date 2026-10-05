import AVFoundation
import XCTest
@testable import PulseCore
@testable import PulseEngine

/// The engine halves of the Edit My VOD extras, on real decoded audio.
final class EditExtrasEngineTests: XCTestCase {
    static let dir: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PulseExtrasTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func writeWAV(_ name: String, seconds: Double, rate: Double = 44_100, _ sample: (Double) -> Float) throws -> URL {
        let url = Self.dir.appendingPathComponent(name)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let frames = Int(rate * seconds)
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for i in 0..<frames { buffer.floatChannelData![0][i] = sample(Double(i) / rate) }
        try file.write(from: buffer)
        return url
    }

    func testBeatDetectorLocksOntoADrumLoop() async throws {
        // 124 BPM: a decaying 55 Hz kick on every beat, a noisy hi-hat on the off-beats, a quiet pad underneath.
        let period = 60.0 / 124, first = 0.31
        var noise = SeededGenerator(seed: 7)
        let hats = (0..<4_000).map { _ in Float.random(in: -1...1, using: &noise) }
        let url = try writeWAV("loop.wav", seconds: 40) { t in
            let pad = 0.03 * sin(2 * .pi * 220 * t)
            guard t >= first else { return Float(pad) }
            let sinceBeat = (t - first).truncatingRemainder(dividingBy: period)
            let kick = sinceBeat < 0.25 ? 0.6 * exp(-sinceBeat * 18) * sin(2 * .pi * 55 * sinceBeat) : 0
            let sinceHat = (t - first - period / 2).truncatingRemainder(dividingBy: period)
            var hat = 0.0
            if t - first >= period / 2 && sinceHat < 0.05 {
                hat = Double(hats[Int(sinceHat * 44_100) % hats.count]) * 0.15 * exp(-sinceHat * 60)
            }
            return Float(pad + kick + hat)
        }
        let beats = try await BeatDetector().beats(url: url)
        XCTAssertGreaterThan(beats.count, 70, "\(beats.count) beats")
        let gaps = zip(beats.dropFirst(), beats).map { $0 - $1 }.sorted()
        XCTAssertEqual(gaps[gaps.count / 2], period, accuracy: 0.015, "tempo")
        // On the kicks, start to finish (not the hi-hats, no drift).
        let onKick = beats.filter { b in
            let k = ((b - first) / period).rounded()
            return abs(b - (first + k * period)) < 0.04
        }
        XCTAssertGreaterThan(Double(onKick.count), Double(beats.count) * 0.9, "\(onKick.count) of \(beats.count) on the kick")
    }

    func testMixLoudnessHearsWhatTheExportHears() async throws {
        let url = try writeWAV("tone.wav", seconds: 8, rate: 48_000) { t in Float(0.2 * sin(2 * .pi * 1000 * t)) }
        let metadata = try await MediaProbe.probe(url)
        let asset = MediaAsset(name: "tone", path: url.path, kind: .audio, metadata: metadata)
        var timeline = Timeline(name: "t", canvas: .landscape1080, tracks: [Track(kind: .audio, name: "A1")])
        timeline.tracks[0].clips = [TimelineClip(name: "tone", content: .media(assetID: asset.id), start: 0, sourceDuration: 8)]

        let full = try await MixLoudness.measure(timeline: timeline, assets: [asset.id: asset])
        // A 0.2-amplitude 1 kHz sine is about −17.7 LUFS mono; on both channels of the mix ≈ −14.7 (−17.7 if the
        // upmix uses a −3 dB pan law).
        XCTAssertTrue((-18.5)...(-13.5) ~= full.lufs, "measured \(full.lufs) LUFS")
        XCTAssertTrue((-17.5)...(-13.5) ~= full.peakDB, "peak \(full.peakDB) dB")

        // The loudness fix's "lower by N dB" really lowers the exported mix by N dB.
        var fixed = timeline
        let verdict = LoudnessVerdict(lufs: LoudnessVerdict.target + 6, peakDB: -1, unleveledDialogue: false)
        XCTAssertEqual(verdict.action, .lower(6))
        verdict.apply(to: &fixed)
        let lowered = try await MixLoudness.measure(timeline: fixed, assets: [asset.id: asset])
        XCTAssertEqual(full.lufs - lowered.lufs, 6, accuracy: 0.3, "\(full.lufs) → \(lowered.lufs)")
        XCTAssertEqual(full.peakDB - lowered.peakDB, 6, accuracy: 0.3)
    }
}
