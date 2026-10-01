import XCTest
@testable import PulseCore

final class SoundLibraryTests: XCTestCase {
    let rate = Synth.sampleRate

    func rms(_ x: ArraySlice<Float>) -> Float {
        (x.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(x.count, 1))).squareRoot()
    }

    /// Tempo from the onset envelope's autocorrelation (beats per minute).
    func estimatedTempo(_ channels: [[Float]]) -> Double {
        let hop = Int(rate / 100)
        let mono = zip(channels[0], channels[1]).map { ($0 + $1) / 2 }
        var energy: [Float] = []
        var i = 0
        while i + hop <= mono.count {
            energy.append(mono[i..<(i + hop)].reduce(0) { $0 + $1 * $1 })
            i += hop
        }
        let onset = zip(energy.dropFirst(), energy).map { max(0, $0 - $1) }
        var best = 0, bestScore: Float = -1
        for lag in 30...150 where lag < onset.count {   // 0.3–1.5 s per beat
            var s: Float = 0
            for k in 0..<(onset.count - lag) { s += onset[k] * onset[k + lag] }
            s /= Float(onset.count - lag)
            if s > bestScore { bestScore = s; best = lag }
        }
        return 60 / (Double(best) / 100)
    }

    func testEveryEffectRendersCleanly() {
        for sound in SoundLibrary.effects {
            let audio = SoundLibrary.render(sound)
            XCTAssertEqual(audio.count, 2, sound.name)
            let n = audio[0].count
            XCTAssertGreaterThan(Double(n) / rate, 0.01, sound.name)
            XCTAssertLessThan(Double(n) / rate, 6, sound.name)
            XCTAssertTrue(audio.allSatisfy { $0.allSatisfy(\.isFinite) }, sound.name)
            let peak = LoudnessMeter.samplePeak(audio)
            XCTAssertLessThanOrEqual(peak, Float(pow(10, -3.0 / 20)) + 1e-3, sound.name)
            XCTAssertGreaterThan(peak, 0.3, "\(sound.name) is too quiet")
            print(String(format: "sfx %-16@ %.2fs", sound.name as NSString, Double(n) / rate))
        }
    }

    func testEveryTrackIsExactLengthLevelledAndEndsCleanly() {
        for sound in SoundLibrary.music {
            let duration = 8.5
            let audio = SoundLibrary.render(sound, duration: duration)
            XCTAssertEqual(audio[0].count, Int(duration * rate), sound.name)
            XCTAssertTrue(audio.allSatisfy { $0.allSatisfy(\.isFinite) }, sound.name)
            let lufs = LoudnessMeter.integratedLUFS(audio, sampleRate: rate)
            let peak = LoudnessMeter.samplePeak(audio)
            XCTAssertEqual(lufs, -16, accuracy: 2, sound.name)
            XCTAssertLessThanOrEqual(peak, Float(pow(10, -1.0 / 20)) + 1e-3, sound.name)
            // The very end has rung out.
            let n = audio[0].count
            let body = rms(audio[0][(n / 4)..<(n / 2)])
            let last = rms(audio[0][(n - Int(0.05 * rate))...])
            XCTAssertLessThan(last, body * 0.25, "\(sound.name) should fade out at the end")
            let bpm = sound.bpm.map(Double.init) ?? 0
            print(String(format: "music %-16@ %@  LUFS %.1f  peak %.1f dBFS  tempo %.0f (written %.0f)",
                         sound.name as NSString, sound.category as NSString, lufs, 20 * log10(Double(peak)), estimatedTempo(audio), bpm))
        }
    }

    func testGrooveIsInTimeAndRenderingIsDeterministic() {
        let sound = SoundLibrary.sound(id: "music.upbeat.goodvibes")!
        let audio = SoundLibrary.render(sound, duration: 16)
        let tempo = estimatedTempo(audio)
        // Beat, half-time or double-time all mean the groove sits on the grid.
        let ratios = [tempo / 122, tempo / 61, tempo / 244]
        XCTAssertTrue(ratios.contains { abs($0 - 1) < 0.04 }, "tempo \(tempo)")
        XCTAssertEqual(SoundLibrary.render(sound, duration: 16)[1], audio[1])
    }

    func testShortAndLongPiecesFitExactly() {
        let sound = SoundLibrary.sound(id: "music.upbeat.weekend")!
        for duration in [3.0, 41.3] {
            let audio = SoundLibrary.render(sound, duration: duration)
            XCTAssertEqual(audio[0].count, Int((duration * rate).rounded()))
            XCTAssertTrue(audio[0].allSatisfy(\.isFinite))
        }
    }

    func testCatalogSearchAndRecommendations() {
        XCTAssertEqual(Set(SoundLibrary.catalog.map(\.id)).count, SoundLibrary.catalog.count, "ids are unique")
        XCTAssertEqual(SoundLibrary.effects.count, SoundEffectKind.allCases.count)
        XCTAssertGreaterThanOrEqual(SoundLibrary.music.count, 12)
        XCTAssertTrue(SoundLibrary.search("whoosh").contains { $0.id == "sfx.whoosh" })
        XCTAssertTrue(SoundLibrary.search("hype gaming", kind: .music).allSatisfy { $0.kind == .music })
        XCTAssertFalse(SoundLibrary.search("hype gaming", kind: .music).isEmpty)
        XCTAssertTrue(SoundLibrary.search("", kind: .soundEffect, category: "Comedy").allSatisfy { $0.category == "Comedy" })
        XCTAssertEqual(SoundLibrary.recommendedMusic(for: [.funny]).id, "music.quirky.oops")
        XCTAssertEqual(SoundLibrary.recommendedMusic(for: [.gaming, .hype], seed: 0).category, MusicStyle.trap.displayName)
        XCTAssertEqual(SoundLibrary.recommendedMusic(for: []).category, MusicStyle.lofi.displayName)
        for id in SoundLibrary.aiEffectIDs { XCTAssertNotNil(SoundLibrary.sound(id: id)) }
        let tags = SoundLibrary.sound(id: "sfx.whoosh")!.assetTags(duration: nil)
        XCTAssertTrue(tags.contains("library:sfx.whoosh") && tags.contains("whoosh"))
    }
}
