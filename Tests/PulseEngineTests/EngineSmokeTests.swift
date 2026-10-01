import AppKit
import AVFoundation
import XCTest
@testable import PulseCore
@testable import PulseEngine

/// End-to-end engine test on real media: generate the demo stream → probe → analyze →
/// find clips → build a 9:16 short → export with the custom compositor → verify the file.
/// Frames are written to build/snapshots for visual inspection (uploaded by CI).
final class EngineSmokeTests: XCTestCase {
    static var workDir: URL = FileManager.default.temporaryDirectory.appendingPathComponent("PulseEngineTests", isDirectory: true)
    static var snapshotDir: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/snapshots", isDirectory: true)
    }

    func testVersion() {
        XCTAssertFalse(PulseEngineInfo.version.isEmpty)
    }

    func testCubeLUTParser() {
        var text = "TITLE \"test\"\nLUT_3D_SIZE 2\n"
        for b in 0..<2 { for g in 0..<2 { for r in 0..<2 { text += "\(r) \(g) \(b)\n" } } }
        let lut = CubeLUT.parse(text)
        XCTAssertEqual(lut?.dimension, 2)
        XCTAssertEqual(lut?.data.count, 2 * 2 * 2 * 4 * 4)
    }

    /// Audio "Enhance": renders a quiet, noisy mono recording through the voice preset and checks
    /// the cached file is sample-accurate, stereo when panned, and loudness-normalized.
    func testAudioEnhanceRender() async throws {
        let dir = Self.workDir.appendingPathComponent("enhance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rate = 48_000.0
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let source = dir.appendingPathComponent("voice.caf")
        let frames = Int(rate * 4)
        do {
            let file = try AVAudioFile(forWriting: source, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
            buffer.frameLength = AVAudioFrameCount(frames)
            var generator = SeededGenerator(seed: 3)
            for i in 0..<frames {
                let t = Double(i) / rate
                let voice = (t > 1 && t < 3) ? 0.05 * sin(2 * Double.pi * 220 * t) : 0
                buffer.floatChannelData![0][i] = Float(voice) + Float.random(in: -0.002...0.002, using: &generator)
            }
            try file.write(from: buffer)
        }
        var settings = AudioSettings()
        settings.applyVoicePreset()
        settings.pan = -0.3
        let range = TimeRange(start: 0.5, end: 3.5)
        let output = try await AudioEnhancer.shared.render(sourceURL: source, range: range, settings: settings, cacheDirectory: dir)
        let again = try await AudioEnhancer.shared.render(sourceURL: source, range: range, settings: settings, cacheDirectory: dir)
        XCTAssertEqual(output, again, "second render should hit the cache")

        let rendered = try AVAudioFile(forReading: output)
        XCTAssertEqual(rendered.processingFormat.channelCount, 2)
        XCTAssertEqual(Double(rendered.length), range.duration * rate, accuracy: 64)
        let buffer = AVAudioPCMBuffer(pcmFormat: rendered.processingFormat, frameCapacity: AVAudioFrameCount(rendered.length))!
        try rendered.read(into: buffer)
        let channels = (0..<2).map { c in Array(UnsafeBufferPointer(start: buffer.floatChannelData![c], count: Int(buffer.frameLength))) }
        let lufs = LoudnessMeter.integratedLUFS(channels, sampleRate: rate)
        XCTAssertEqual(lufs, AudioEnhanceChain.targetLUFS, accuracy: 2.5)
        XCTAssertLessThanOrEqual(LoudnessMeter.samplePeak(channels), 0.9)

        // A different setting produces a different cache entry.
        settings.noiseReduction = 0.8
        let other = try await AudioEnhancer.shared.render(sourceURL: source, range: range, settings: settings, cacheDirectory: dir)
        XCTAssertNotEqual(other, output)
    }

    /// Speech buried in keyboard clicks, music and fan noise: the neural voice isolator must recover it
    /// far better than the noisy input (scored as SI-SDR against the clean voice), and beat classic mode.
    func testVoiceIsolationRemovesNonSteadyNoise() throws {
        guard VoiceIsolation.isAvailable else { throw XCTSkip("AUSoundIsolation isn't on this Mac") }
        let dir = Self.workDir.appendingPathComponent("isolate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rate = 48_000.0
        let url = dir.appendingPathComponent("voice.wav")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", url.path, "--file-format=WAVE", "--data-format=LEF32@48000",
                         "Okay chat, we are finally back. Let me show you the build I have been working on all week. It is honestly so good."]
        try say.run()
        say.waitUntilExit()
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let speech = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        // Half a second of silence either side, then scale the voice to about −20 dBFS RMS.
        var clean = [Float](repeating: 0, count: Int(0.5 * rate)) + speech + [Float](repeating: 0, count: Int(0.5 * rate))
        let voiceRMS = (clean.reduce(Float(0)) { $0 + $1 * $1 } / Float(speech.count)).squareRoot()
        clean = clean.map { $0 * 0.1 / max(voiceRMS, 1e-6) }

        var rng = SeededGenerator(seed: 21)
        var noise = [Float](repeating: 0, count: clean.count)
        // Mechanical keyboard: sharp decaying clicks at irregular intervals.
        var next = 0
        while next < noise.count {
            for i in 0..<min(600, noise.count - next) {
                noise[next + i] += Float.random(in: -1...1, using: &rng) * 0.35 * exp(-Float(i) / 90)
            }
            next += Int(Double.random(in: 0.07...0.25, using: &rng) * rate)
        }
        // Music: a chord with a pulsing beat.
        for i in noise.indices {
            let t = Double(i) / rate
            let beat = Float(0.5 + 0.5 * sin(2 * Double.pi * 2 * t))
            let chord = sin(2 * Double.pi * 196 * t) + sin(2 * Double.pi * 247 * t) + sin(2 * Double.pi * 294 * t) + 0.5 * sin(2 * Double.pi * 587 * t)
            noise[i] += Float(chord) * 0.02 * beat
        }
        // Fan: low-passed noise.
        var fan: Float = 0
        for i in noise.indices {
            fan = 0.97 * fan + 0.03 * Float.random(in: -1...1, using: &rng)
            noise[i] += fan * 0.25
        }
        let noisy = zip(clean, noise).map(+)

        func siSDR(_ estimate: [Float]) -> Double {
            var dot = 0.0, energy = 0.0
            for i in clean.indices { dot += Double(estimate[i] * clean[i]); energy += Double(clean[i] * clean[i]) }
            let scale = dot / max(energy, 1e-12)
            var target = 0.0, error = 0.0
            for i in clean.indices {
                let t = scale * Double(clean[i])
                target += t * t
                error += (Double(estimate[i]) - t) * (Double(estimate[i]) - t)
            }
            return 10 * log10(target / max(error, 1e-12))
        }
        var settings = AudioSettings()
        settings.noiseReduction = 1
        settings.noiseMethod = .spectral
        var classic = [noisy]
        AudioEnhanceChain.process(&classic, sampleRate: rate, settings: settings)
        settings.noiseMethod = .voiceIsolation
        var isolated = [noisy]
        let start = Date()
        let used = AudioEnhanceChain.process(&isolated, sampleRate: rate, settings: settings, voiceIsolator: VoiceIsolation.isolator)
        let seconds = Date().timeIntervalSince(start)
        XCTAssertEqual(used, .voiceIsolation, "isolator failed: \(VoiceIsolation.lastError ?? "?")")
        XCTAssertEqual(isolated[0].count, noisy.count)
        let aligned = SignalAlignment.delay(of: isolated[0] + [Float](repeating: 0, count: 4800), relativeTo: clean, maxLag: 4800)

        let before = siSDR(noisy), afterClassic = siSDR(classic[0]), afterAI = siSDR(isolated[0])
        print(String(format: "voice isolation: SI-SDR noisy %.1f dB, classic %.1f dB, AI %.1f dB; residual lag %d samples; %.1fs audio in %.2fs",
                     before, afterClassic, afterAI, aligned.lag, Double(noisy.count) / rate, seconds))
        XCTAssertLessThan(aligned.lag, 48, "output must stay aligned with the source")
        XCTAssertGreaterThan(afterAI, before + 6)
        XCTAssertGreaterThan(afterAI, afterClassic + 2)
    }

    /// Library sounds render to AAC files of the right length and loudness, and are cached.
    func testSoundLibraryStoreRendersCachedFiles() async throws {
        let dir = Self.workDir.appendingPathComponent("library-\(UUID().uuidString)", isDirectory: true)
        let sound = SoundLibrary.sound(id: "music.lofi.sunday")!
        let start = Date()
        let url = try await SoundLibraryStore.shared.file(for: sound, duration: 12.34, directory: dir)
        let seconds = Date().timeIntervalSince(start)
        let again = try await SoundLibraryStore.shared.file(for: sound, duration: 12.3, directory: dir)
        XCTAssertEqual(url, again, "same length (to 0.1 s) hits the cache")
        let meta = try await MediaProbe.probe(url)
        XCTAssertEqual(meta.duration, 12.3, accuracy: 0.06)
        XCTAssertTrue(meta.hasAudio)
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let channels = (0..<Int(buffer.format.channelCount)).map { Array(UnsafeBufferPointer(start: buffer.floatChannelData![$0], count: Int(buffer.frameLength))) }
        XCTAssertEqual(channels.count, 2)
        let lufs = LoudnessMeter.integratedLUFS(channels, sampleRate: file.processingFormat.sampleRate)
        XCTAssertEqual(lufs, -16, accuracy: 2)
        let pop = try await SoundLibraryStore.shared.file(for: SoundLibrary.sound(id: "sfx.pop")!, directory: dir)
        let asset = try await SoundLibraryStore.asset(for: SoundLibrary.sound(id: "sfx.pop")!, url: pop, duration: nil, cacheRoot: dir)
        XCTAssertEqual(asset.role, .soundEffect)
        XCTAssertTrue(asset.tags.contains("library:sfx.pop"))
        print(String(format: "sound library: 12.3 s of %@ rendered + encoded in %.2fs, %.1f LUFS after AAC", sound.name, seconds, lufs))
    }

    /// Captions take each speaker's color and show a name tag when labels are on.
    func testSpeakerCaptionColorsAndLabels() throws {
        var words: [CaptionWord] = []
        for i in 0..<6 { words.append(CaptionWord(text: "HELLO\(i)", start: Double(i), end: Double(i) + 0.8, speaker: i < 3 ? 0 : 1)) }
        var track = CaptionTrack(sourceAssetID: UUID(), words: words, style: .bold)
        track.speakerNames = [0: "Host", 1: "Guest"]
        track.colorBySpeaker()
        let timed = track.words.map { TimedCaptionWord(id: $0.id, text: $0.text, start: $0.start, end: $0.end, isEmphasized: false, speaker: $0.speaker) }
        var styles: [Int: CaptionStyle] = [:]
        for id in track.speakerStyles.keys { styles[id] = track.style(forSpeaker: id) }
        let plain = CaptionRenderData(pages: CaptionLayoutEngine.pages(timed, style: track.style), style: track.style, speakerStyles: styles)
        let labelled = CaptionRenderData(pages: plain.pages, style: track.style, speakerStyles: styles, labels: [0: "Host", 1: "Guest"])
        let scene = RenderScene(canvas: .vertical1080, renderSize: CGSize(width: 540, height: 960), captions: plain)
        let renderer = FrameRenderer.shared
        // Mean (blue − red) of the visible caption pixels: white text ≈ 0, cyan text > 0.
        func blueBias(_ image: CIImage) -> Double {
            let rect = image.extent.intersection(CGRect(x: 0, y: 0, width: 540, height: 960))
            guard let cg = renderer.context.createCGImage(image, from: rect) else { return 0 }
            let w = cg.width, h = cg.height
            var data = [UInt8](repeating: 0, count: w * h * 4)
            let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            var total = 0.0, count = 0.0
            for i in stride(from: 0, to: data.count, by: 4) {
                let r = Int(data[i]), g = Int(data[i + 1]), b = Int(data[i + 2]), a = Int(data[i + 3])
                let brightness: Int = r + g + b
                guard a > 200, brightness > 450 else { continue }
                total += Double(b - r)
                count += 1
            }
            return count > 0 ? total / count : 0
        }
        let host = try XCTUnwrap(renderer.renderCaptions(plain, at: 0.5, scene: scene))
        let guest = try XCTUnwrap(renderer.renderCaptions(plain, at: 3.5, scene: scene))
        let hostBias = blueBias(host), guestBias = blueBias(guest)
        let withLabel = try XCTUnwrap(renderer.renderCaptions(labelled, at: 3.5, scene: scene))
        print(String(format: "speaker captions: host blue-bias %.0f, guest %.0f; height %.0f → %.0f with name tag",
                     hostBias, guestBias, guest.extent.height, withLabel.extent.height))
        XCTAssertGreaterThan(guestBias, hostBias + 40, "the guest's captions are cyan")
        XCTAssertGreaterThan(withLabel.extent.height, guest.extent.height + 10, "a name tag sits above the caption")
    }

    /// Mean absolute pixel difference (0–255) between two frames, compared at 90×160.
    static func meanDifference(_ a: CGImage, _ b: CGImage) -> Double {
        func pixels(_ image: CGImage) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: 90 * 160 * 4)
            let context = CGContext(data: &data, width: 90, height: 160, bitsPerComponent: 8, bytesPerRow: 90 * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 90, height: 160))
            return data
        }
        let pa = pixels(a), pb = pixels(b)
        var total = 0
        for i in pa.indices where i % 4 != 3 { total += abs(Int(pa[i]) - Int(pb[i])) }
        return Double(total) / Double(pa.count / 4 * 3)
    }

    /// The deterministic test signal also generated by the reference script (harmonics under formants).
    static func referenceSignal(seconds: Double, f0Base: Double, formants: [(Double, Double)], seed: UInt64) -> [Float] {
        let rate = 16_000.0
        let n = Int(seconds * rate)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        var x = seed
        for i in 0..<n {
            let t = Double(i) / rate
            let f0 = f0Base + 0.15 * f0Base * sin(2 * Double.pi * 0.7 * t)
            phase += 2 * Double.pi * f0 / rate
            var s = 0.0
            for k in 1...30 {
                let fk = Double(k) * f0
                if fk > 7800 { break }
                let g = formants.reduce(0.0) { $0 + exp(-pow((fk - $1.0) / 180, 2)) * $1.1 } + 0.02
                s += g / Double(k) * sin(Double(k) * phase)
            }
            x = (1_103_515_245 &* x &+ 12345) % 2_147_483_648
            s += (Double(x) / 2_147_483_648 - 0.5) * 0.02
            let env = 0.5 + 0.5 * sin(2 * Double.pi * 3.1 * t)
            out[i] = Float(0.3 * s * env)
        }
        return out
    }

    /// The Swift speaker encoder reproduces the original PyTorch model (reference values computed by
    /// Resemblyzer's network on the same signals).
    func testSpeakerEncoderMatchesPyTorchReference() throws {
        let encoder = try XCTUnwrap(SpeakerEncoder.shared, "speaker model missing")
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/speaker-reference.json")
        let reference = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        func floats(_ key: String) -> [Float] { (reference[key] as? [Double] ?? []).map(Float.init) }
        let a = Self.referenceSignal(seconds: 2.5, f0Base: 120, formants: [(700, 1.0), (1200, 0.7), (2600, 0.4)], seed: 7)
        let b = Self.referenceSignal(seconds: 1.2, f0Base: 210, formants: [(400, 1.0), (2000, 0.8), (2900, 0.5)], seed: 11)
        // Front end: same mel frames (on the normalised, padded signal the reference used).
        let normalizedA = SpeakerEncoder.normalized(a)
        let starts = SpeakerEncoder.partials(samples: normalizedA.count)
        XCTAssertEqual(starts.count, reference["partialsA"] as? Int)
        XCTAssertEqual(SpeakerEncoder.partials(samples: b.count).count, reference["partialsB"] as? Int)
        let needed = (starts.last! + 160) * 160
        let (mel, frames) = encoder.melSpectrogram(normalizedA + [Float](repeating: 0, count: max(0, needed - normalizedA.count)))
        XCTAssertEqual(frames, reference["melFrames"] as? Int)
        for (frame, key) in [(20, "melFrame20A"), (60, "melFrame60A")] {
            let expected = floats(key)
            let got = Array(mel[(frame * 40)..<((frame + 1) * 40)])
            let scale = expected.map(abs).max() ?? 1
            let error = zip(got, expected).map { abs($0 - $1) }.max() ?? 0
            XCTAssertLessThan(error / scale, 2e-3, "mel frame \(frame)")
        }
        // Network: embeddings match.
        let embeddings = encoder.embed([a, b])
        let cosA = SpeakerEncoder.cosine(embeddings[0], floats("embeddingA"))
        let cosB = SpeakerEncoder.cosine(embeddings[1], floats("embeddingB"))
        print(String(format: "speaker encoder vs PyTorch: cos %.6f / %.6f; A·B %.4f (reference %.4f)", cosA, cosB,
                     SpeakerEncoder.cosine(embeddings[0], embeddings[1]), reference["cosineAB"] as? Double ?? 0))
        XCTAssertGreaterThan(cosA, 0.999)
        XCTAssertGreaterThan(cosB, 0.999)
    }

    /// A conversation between system voices, alternating lines, plus evenly spread word timings.
    static func voiceConversation(_ voices: [String], lines: [String], in dir: URL) throws -> (url: URL, transcript: Transcript, turns: [(range: TimeRange, voice: String)]) {
        let rate = 16_000.0
        var samples: [Float] = []
        var turns: [(range: TimeRange, voice: String)] = []
        for (i, line) in lines.enumerated() {
            let voice = voices[i % voices.count]
            let url = dir.appendingPathComponent("line\(i)-\(voice).wav")
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-v", voice, "-o", url.path, "--file-format=WAVE", "--data-format=LEF32@16000", line]
            try say.run()
            say.waitUntilExit()
            let file = try AVAudioFile(forReading: url)
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
            try file.read(into: buffer)
            let start = Double(samples.count) / rate
            samples += Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
            turns.append((TimeRange(start: start, end: Double(samples.count) / rate), voice))
            samples += [Float](repeating: 0, count: Int(0.6 * rate))
        }
        let combined = dir.appendingPathComponent("conversation-\(voices.joined(separator: "-")).wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let out = try AVAudioFile(forWriting: combined, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        try out.write(from: buffer)
        var words: [TranscriptWord] = []
        for turn in turns {
            var t = turn.range.start + 0.15
            while t + 0.3 < turn.range.end - 0.1 {
                words.append(TranscriptWord(text: "w", start: t, end: t + 0.28))
                t += 0.34
            }
        }
        return (combined, Transcript(words: words, source: .demo), turns)
    }

    static func wordAccuracy(_ result: Transcript, _ original: Transcript, turns: [(range: TimeRange, voice: String)]) -> Double {
        var votes: [Int: [String: Int]] = [:]
        for (w, word) in result.words.enumerated() {
            guard let s = word.speaker, let turn = turns.first(where: { $0.range.contains(original.words[w].start) }) else { continue }
            votes[s, default: [:]][turn.voice, default: 0] += 1
        }
        // Each detected speaker counts for the voice it mostly covers; unlabelled words are wrong.
        let correct = votes.values.map { $0.values.max() ?? 0 }.reduce(0, +)
        let distinctVoices = Set(votes.values.compactMap { $0.max { $0.value < $1.value }?.key }).count
        let total = result.words.count
        return distinctVoices < Set(turns.map(\.voice)).count ? Double(correct) / Double(total) * 0.5 : Double(correct) / Double(total)
    }

    /// Neural embeddings vs MFCC voiceprints on pairs of system voices, including same-gender pairs.
    func testNeuralDiarizationOfVoicePairs() async throws {
        _ = try XCTUnwrap(SpeakerEncoder.shared, "speaker model missing")
        let list = Process()
        list.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        list.arguments = ["-v", "?"]
        let pipe = Pipe()
        list.standardOutput = pipe
        try list.run()
        list.waitUntilExit()
        let installed = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        func has(_ name: String) -> Bool { installed.split(separator: "\n").contains { $0.hasPrefix(name + " ") } }
        let pairs = [["Samantha", "Fred"], ["Samantha", "Karen"], ["Moira", "Tessa"], ["Daniel", "Fred"], ["Daniel", "Rishi"], ["Karen", "Moira"]]
            .filter { $0.allSatisfy(has) }
        guard !pairs.isEmpty else { throw XCTSkip("no system voices") }
        let lines = [
            "Welcome back to the show, today we are talking about the best moments from last night's stream.",
            "Thanks for having me, honestly that final round was the craziest thing I have ever played.",
            "Walk me through it, because from the chat it looked like you had no chance at all.",
            "I was down to one health point with three players left and somehow I pulled it off.",
            "That is incredible, the clip already has thousands of views on every platform.",
            "I still can't believe it, my hands were shaking for about ten minutes afterwards.",
            "So what is next for you, are you going to keep streaming the same game this season?",
            "Probably, the community has been amazing and there is a tournament coming up next month.",
        ]
        let dir = Self.workDir.appendingPathComponent("pairs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var neuralScores: [Double] = [], classicScores: [Double] = []
        for pair in pairs {
            let (url, transcript, turns) = try Self.voiceConversation(pair, lines: lines, in: dir)
            let neural = try await SpeakerDiarization.diarize(transcript, audioURL: url, method: .neural)
            let classic = try await SpeakerDiarization.diarize(transcript, audioURL: url, method: .voiceprint)
            let n = Self.wordAccuracy(neural, transcript, turns: turns), c = Self.wordAccuracy(classic, transcript, turns: turns)
            neuralScores.append(n)
            classicScores.append(c)
            // Embedding similarity within / across the true voices (for calibrating the threshold).
            let segments = SpeechSegmenter.segments(from: transcript)
            let vectors = try await SpeakerDiarization.embeddings(url: url, ranges: segments.map(\.range), encoder: SpeakerEncoder.shared!)
            var kept: [[Float]] = [], truth: [Int] = []
            for (i, v) in vectors.enumerated() {
                guard let v, let turn = turns.firstIndex(where: { $0.range.contains(segments[i].range.start + 0.05) }) else { continue }
                kept.append(v)
                truth.append(pair.firstIndex(of: turns[turn].voice) ?? 0)
            }
            let sep = EmbeddingClustering.separation(kept, labels: truth)
            print(String(format: "voices %@ + %@: neural %d speakers %.0f%%, classic %d speakers %.0f%%; similarity within %.3f across %.3f (%d segments)",
                         pair[0], pair[1], neural.speakerIDs.count, n * 100, classic.speakerIDs.count, c * 100, sep.within, sep.between, kept.count))
        }
        let meanNeural = neuralScores.reduce(0, +) / Double(neuralScores.count)
        let meanClassic = classicScores.reduce(0, +) / Double(classicScores.count)
        print(String(format: "voice pairs: neural %.0f%% vs classic %.0f%% of words on average", meanNeural * 100, meanClassic * 100))
        XCTAssertGreaterThan(meanNeural, 0.9)
        XCTAssertGreaterThanOrEqual(meanNeural, meanClassic)
        for (pair, score) in zip(pairs, neuralScores) { XCTAssertGreaterThan(score, 0.8, pair.joined(separator: " + ")) }

        // One voice reading everything stays one speaker (no labels).
        let solo = try Self.voiceConversation([pairs[0][0]], lines: lines, in: dir)
        let soloResult = try await SpeakerDiarization.diarize(solo.transcript, audioURL: solo.url, method: .neural)
        let soloVectors = try await SpeakerDiarization.embeddings(url: solo.url, ranges: SpeechSegmenter.segments(from: solo.transcript).map(\.range), encoder: SpeakerEncoder.shared!)
        print("one voice: \(soloResult.speakerIDs.count) speakers, silhouettes \(EmbeddingClustering.estimate(soloVectors.compactMap { $0 }).silhouettes)")
        XCTAssertLessThanOrEqual(soloResult.speakerIDs.count, 1)

        // Three voices taking turns.
        let trio = ["Samantha", "Fred", "Daniel"].filter(has)
        if trio.count == 3 {
            let three = try Self.voiceConversation(trio, lines: lines + lines.prefix(4), in: dir)
            let result = try await SpeakerDiarization.diarize(three.transcript, audioURL: three.url, method: .neural)
            let score = Self.wordAccuracy(result, three.transcript, turns: three.turns)
            print(String(format: "three voices: %d speakers, %.0f%% of words", result.speakerIDs.count, score * 100))
            XCTAssertEqual(result.speakerIDs.count, 3)
            XCTAssertGreaterThan(score, 0.85)
        }
    }

    /// Two synthesized voices take turns; diarization must find two speakers and who said what.
    func testSpeakerDiarizationOfTwoVoices() async throws {
        let list = Process()
        list.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        list.arguments = ["-v", "?"]
        let pipe = Pipe()
        list.standardOutput = pipe
        try list.run()
        list.waitUntilExit()
        let voices = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        func has(_ name: String) -> Bool { voices.split(separator: "\n").contains { $0.hasPrefix(name + " ") } }
        guard let female = ["Samantha", "Karen", "Moira", "Tessa", "Victoria"].first(where: has),
              let male = ["Fred", "Daniel", "Alex", "Ralph", "Aaron"].first(where: has) else {
            throw XCTSkip("no pair of system voices available")
        }
        let lines = [
            (female, "Welcome back to the show, today we are talking about the best moments from last night's stream."),
            (male, "Thanks for having me, honestly that final round was the craziest thing I have ever played."),
            (female, "Walk me through it, because from the chat it looked like you had no chance at all."),
            (male, "I was down to one health point with three players left and somehow I pulled it off."),
            (female, "That is incredible, the clip already has thousands of views on every platform."),
            (male, "I still can't believe it, my hands were shaking for about ten minutes afterwards."),
            (female, "So what is next for you, are you going to keep streaming the same game this season?"),
            (male, "Probably, the community has been amazing and there is a tournament coming up next month."),
            (female, "Well good luck with that, and thanks again for joining us today."),
            (male, "Thank you, it was a lot of fun, see everybody in the next stream."),
        ]
        let dir = Self.workDir.appendingPathComponent("diarize-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rate = 16_000.0
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        var samples: [Float] = []
        var turns: [(range: TimeRange, voice: String)] = []
        for (i, line) in lines.enumerated() {
            let url = dir.appendingPathComponent("line\(i).wav")
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-v", line.0, "-o", url.path, "--file-format=WAVE", "--data-format=LEF32@16000", line.1]
            try say.run()
            say.waitUntilExit()
            guard say.terminationStatus == 0 else { throw XCTSkip("say failed for \(line.0)") }
            let file = try AVAudioFile(forReading: url)
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
            try file.read(into: buffer)
            let start = Double(samples.count) / rate
            samples += Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
            turns.append((TimeRange(start: start, end: Double(samples.count) / rate), line.0))
            samples += [Float](repeating: 0, count: Int(0.6 * rate))
        }
        let combined = dir.appendingPathComponent("conversation.wav")
        do {
            let out = try AVAudioFile(forWriting: combined, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
            try out.write(from: buffer)
        }
        // Word timings: evenly spread through each turn (the test is about voices, not ASR).
        var words: [TranscriptWord] = []
        for turn in turns {
            var t = turn.range.start + 0.15
            while t + 0.3 < turn.range.end - 0.1 {
                words.append(TranscriptWord(text: "w", start: t, end: t + 0.28))
                t += 0.34
            }
        }
        let transcript = Transcript(words: words, source: .demo)
        let result = try await SpeakerDiarization.diarize(transcript, audioURL: combined)
        // The evidence behind the speaker count (printed for the CI log).
        let segments = SpeechSegmenter.segments(from: transcript)
        let prints = try await SpeakerDiarization.voiceprints(url: combined, ranges: segments.map(\.range)).compactMap { $0 }
        for trial in SpeakerClustering.estimate(prints).trials {
            print(String(format: "diarization trial: %d speakers, separation %.2f vs reference %.2f (needs %.2f), %d segments",
                         trial.speakers, trial.separation, trial.reference, trial.threshold, prints.count))
        }
        XCTAssertEqual(result.speakerIDs.count, 2, "found \(result.speakerIDs.count) speakers")
        // Map each detected speaker to the voice it mostly covers, then score every word.
        var votes: [Int: [String: Int]] = [:]
        for (w, word) in result.words.enumerated() {
            guard let s = word.speaker, let turn = turns.first(where: { $0.range.contains(transcript.words[w].start) }) else { continue }
            votes[s, default: [:]][turn.voice, default: 0] += 1
        }
        let voiceOf = votes.mapValues { $0.max { $0.value < $1.value }!.key }
        let correct = result.words.enumerated().filter { w, word in
            guard let s = word.speaker, let turn = turns.first(where: { $0.range.contains(transcript.words[w].start) }) else { return false }
            return voiceOf[s] == turn.voice
        }.count
        let accuracy = Double(correct) / Double(result.words.count)
        print(String(format: "diarization: %@ vs %@, %d speakers, %.0f%% of words correct", female, male, result.speakerIDs.count, accuracy * 100))
        XCTAssertGreaterThan(accuracy, 0.85)
        XCTAssertNotEqual(voiceOf[0], voiceOf[1], "the two speakers are different voices")
    }

    /// Real speech-to-text: macOS `say` speaks a sentence, whisper.cpp transcribes it with word timings.
    /// Runs when CI (or you) installs whisper.cpp and sets PULSE_WHISPER_MODEL to a ggml model path.
    func testWhisperTranscriptionOfSynthesizedSpeech() async throws {
        guard let modelPath = ProcessInfo.processInfo.environment["PULSE_WHISPER_MODEL"], FileManager.default.fileExists(atPath: modelPath),
              let executable = WhisperCppTranscriber.locateExecutable() else {
            throw XCTSkip("whisper.cpp or PULSE_WHISPER_MODEL not available")
        }
        let dir = Self.workDir.appendingPathComponent("whisper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let wav = dir.appendingPathComponent("speech.wav")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", wav.path, "--file-format=WAVE", "--data-format=LEI16@16000",
                         "No way, that was the craziest clutch I have ever seen. Let's go!"]
        try say.run()
        say.waitUntilExit()
        XCTAssertEqual(say.terminationStatus, 0)

        let transcriber = WhisperCppTranscriber(executable: executable, model: URL(fileURLWithPath: modelPath))
        let transcript = try await transcriber.transcribe(audioURL: wav, language: "en-US", progress: { _ in })
        let text = transcript.fullText.lowercased()
        print("whisper transcript:", transcript.fullText)
        XCTAssertTrue(text.contains("clutch") || text.contains("craziest"), "unexpected transcript: \(transcript.fullText)")
        XCTAssertGreaterThan(transcript.words.count, 6)
        for (a, b) in zip(transcript.words, transcript.words.dropFirst()) {
            XCTAssertLessThanOrEqual(a.start, b.start + 0.01, "word timings must be ordered")
        }
        XCTAssertLessThan(transcript.words.last?.end ?? 99, 10)
    }

    func testEndToEndDemoPipeline() async throws {
        try FileManager.default.createDirectory(at: Self.workDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: Self.snapshotDir, withIntermediateDirectories: true)

        // 1. Generate sample media.
        let demo = try await DemoMediaGenerator.generate(in: Self.workDir)
        let meta = try await MediaProbe.probe(demo.videoURL)
        XCTAssertEqual(meta.width, DemoMediaGenerator.width)
        XCTAssertEqual(meta.height, DemoMediaGenerator.height)
        XCTAssertEqual(meta.duration, DemoMediaGenerator.duration, accuracy: 0.2)
        XCTAssertTrue(meta.hasAudio)
        let asset = MediaAsset(name: "Demo Stream", path: demo.videoURL.path, kind: .video, role: .main, metadata: meta)

        // 2. Analyze (transcript comes from the demo script; speech engines need entitlements).
        let pipeline = AnalysisPipeline(cacheDirectory: Self.workDir)
        let output = try await pipeline.run(asset: asset, options: .init(transcribe: false, detectFaces: true, importedTranscript: demo.transcript), progress: { _ in })
        var analysis = output.analysis
        XCTAssertNotNil(analysis.audio)
        XCTAssertNotNil(analysis.visual)
        XCTAssertGreaterThan(analysis.audio!.count, 700)
        // Loud events are louder than the rest.
        XCTAssertGreaterThan(analysis.audio!.maxRMS(in: TimeRange(start: 22, end: 23)), analysis.audio!.meanRMS(in: TimeRange(start: 60, end: 70)) + 6)
        if analysis.webcam == nil {
            // Vision may not see a cartoon face; fall back to the scripted face track.
            analysis.visual?.faces = demo.faces
            analysis.webcam = WebcamEstimator.estimate(faces: demo.faces, frameSize: meta.size)
            analysis.profile = .gameplayWithFacecam
        }
        XCTAssertEqual(analysis.profile, .gameplayWithFacecam)

        // 3. Clips.
        let generator = ClipGenerator(input: ClipGenerationInput(analysis: analysis), settings: ClipGenerationSettings(targetDuration: 15, minimumPotential: 0))
        let candidates = generator.generate()
        XCTAssertFalse(candidates.isEmpty)
        let best = try XCTUnwrap(candidates.first { $0.range.contains(22.5) } ?? candidates.first { $0.range.contains(51.5) })

        // 4. Short timeline, with a music bed and a payoff hit from the built-in sound library.
        let libraryDir = Self.workDir.appendingPathComponent("library", isDirectory: true)
        let musicSound = SoundLibrary.recommendedMusic(for: best.tags)
        let musicURL = try await SoundLibraryStore.shared.file(for: musicSound, duration: 30, directory: libraryDir)
        let music = try await SoundLibraryStore.asset(for: musicSound, url: musicURL, duration: 30, cacheRoot: Self.workDir)
        let impactSound = SoundLibrary.sound(id: "sfx.impact")!
        let impact = try await SoundLibraryStore.asset(for: impactSound, url: try await SoundLibraryStore.shared.file(for: impactSound, directory: libraryDir),
                                                       duration: nil, cacheRoot: Self.workDir)
        var shortOptions = ShortBuildOptions.oneClick
        shortOptions.soundEffects = true
        let short = ShortBuilder.build(ShortBuildInput(candidate: best, asset: asset, analysis: analysis, soundEffects: [impact], music: music), options: shortOptions)
        XCTAssertEqual(short.layout, .splitScreen)
        XCTAssertNotNil(short.captions)
        XCTAssertTrue(short.allClips.contains { $0.assetID == music.id && $0.audio.duckUnderDialogue }, "library music bed, ducked under speech")
        let allAssets = [asset.id: asset, music.id: music, impact.id: impact]

        // 5. Render a still through the compositor pipeline (fast visual check).
        let built = try await CompositionBuilder.build(timeline: short, assets: allAssets)
        XCTAssertTrue(built.missingAssetIDs.isEmpty)
        let usedFiles = Set(built.composition.tracks.flatMap { $0.segments.compactMap { $0.sourceURL?.lastPathComponent } })
        XCTAssertTrue(usedFiles.contains(musicURL.lastPathComponent), "music is in the mix: \(usedFiles)")
        // One-click shorts normalize dialogue, so the audio must come from the enhance renders.
        var enhancedSegments = 0
        for track in built.composition.tracks where track.mediaType == .audio {
            for segment in track.segments where segment.sourceURL?.lastPathComponent.hasPrefix("enh-") == true {
                enhancedSegments += 1
            }
        }
        XCTAssertGreaterThan(enhancedSegments, 0, "expected enhanced (normalized) audio in the short")
        let generatorStill = AVAssetImageGenerator(asset: built.composition)
        generatorStill.videoComposition = built.videoComposition
        generatorStill.requestedTimeToleranceBefore = .zero
        generatorStill.requestedTimeToleranceAfter = .zero
        for (i, t) in [0.5, short.duration / 2, max(0, short.duration - 0.5)].enumerated() {
            let image = try await generatorStill.image(at: .seconds(t)).image
            XCTAssertEqual(image.width, 1080)
            XCTAssertEqual(image.height, 1920)
            Self.writePNG(image, name: "short-frame-\(i).png")
        }

        // 6. Export.
        let exportURL = Self.workDir.appendingPathComponent("short-export.mp4")
        let settings = ExportSettings(preset: .tiktok, outputDirectory: Self.workDir.path, quality: .draft)
        try await ExportEngine().export(timeline: short, assets: allAssets, settings: settings, to: exportURL, progress: { _ in })
        let exported = try await MediaProbe.probe(exportURL)
        XCTAssertEqual(exported.width, 1080)
        XCTAssertEqual(exported.height, 1920)
        XCTAssertEqual(exported.duration, short.duration, accuracy: 0.25)
        XCTAssertTrue(exported.hasAudio)
        let exportedFrames = AVAssetImageGenerator(asset: AVURLAsset(url: exportURL))
        exportedFrames.maximumSize = CGSize(width: 540, height: 960)
        let mid = try await exportedFrames.image(at: .seconds(short.duration / 2)).image
        Self.writePNG(mid, name: "export-mid.png")

        // 7. Landscape re-layout of the same short (aspect ratio change stays editable).
        var landscape = short
        landscape.canvas = .landscape1080
        LayoutEngine.apply(.facecamCorner, to: &landscape, context: LayoutContext(analysis: analysis, sourceSize: meta.size))
        let builtLandscape = try await CompositionBuilder.build(timeline: landscape, assets: allAssets)
        let gl = AVAssetImageGenerator(asset: builtLandscape.composition)
        gl.videoComposition = builtLandscape.videoComposition
        let landscapeFrame = try await gl.image(at: .seconds(1)).image
        XCTAssertEqual(landscapeFrame.width, 1920)
        Self.writePNG(landscapeFrame, name: "landscape-facecam-corner.png")

        // 7b. Layout morph: split screen → circle facecam over one second, no clips split.
        var morphing = short
        let clipCountBefore = morphing.allClips.count
        LayoutMorpher.addChange(.circleFacecam, at: 2, duration: 1, to: &morphing, context: LayoutContext(analysis: analysis, sourceSize: meta.size))
        XCTAssertEqual(morphing.allClips.count, clipCountBefore)
        let builtMorph = try await CompositionBuilder.build(timeline: morphing, assets: allAssets)
        let gmorph = AVAssetImageGenerator(asset: builtMorph.composition)
        gmorph.videoComposition = builtMorph.videoComposition
        gmorph.requestedTimeToleranceBefore = .zero
        gmorph.requestedTimeToleranceAfter = .zero
        var morphFrames: [CGImage] = []
        for (name, t) in [("before", 1.5), ("mid", 2.5), ("after", 3.6)] {
            let image = try await gmorph.image(at: .seconds(t)).image
            Self.writePNG(image, name: "layout-morph-\(name).png")
            morphFrames.append(image)
        }
        let beforeMid = Self.meanDifference(morphFrames[0], morphFrames[1]), midAfter = Self.meanDifference(morphFrames[1], morphFrames[2])
        print(String(format: "layout morph: frame difference before→mid %.1f, mid→after %.1f", beforeMid, midAfter))
        XCTAssertGreaterThan(beforeMid, 2, "mid-morph frame should differ from the split screen")
        XCTAssertGreaterThan(midAfter, 2, "mid-morph frame should differ from the finished circle layout")

        // 8. True cross-dissolve: during the blend both clips are on screen and moving.
        var dissolve = Timeline.empty(name: "Dissolve", canvas: .landscape1080)
        let videoTrack = dissolve.tracks.first { $0.kind == .video }!.id
        let groupA = UUID(), groupB = UUID()
        let clipA = TimelineClip(name: "A", content: .media(assetID: asset.id), start: 0, sourceIn: 10, sourceDuration: 3, linkGroup: groupA)
        let clipB = TimelineClip(name: "B", content: .media(assetID: asset.id), start: 3, sourceIn: 40, sourceDuration: 3,
                                 transitionIn: ClipTransition(kind: .crossDissolve, duration: 1), linkGroup: groupB)
        try dissolve.insert(clipA, onTrack: videoTrack)
        try dissolve.insert(clipB, onTrack: videoTrack)
        let audioTrack = dissolve.tracks.first { $0.kind == .audio }!.id
        try dissolve.insert(TimelineClip(name: "A audio", content: .media(assetID: asset.id), start: 0, sourceIn: 10, sourceDuration: 3, linkGroup: groupA), onTrack: audioTrack)
        try dissolve.insert(TimelineClip(name: "B audio", content: .media(assetID: asset.id), start: 3, sourceIn: 40, sourceDuration: 3, linkGroup: groupB), onTrack: audioTrack)
        let builtDissolve = try await CompositionBuilder.build(timeline: dissolve, assets: [asset.id: asset])
        let during = builtDissolve.videoComposition.instructions
            .compactMap { $0 as? PulseCompositionInstruction }
            .first { $0.timeRange.containsTime(.seconds(3.5)) }
        let videoTrackIDs = Set(during?.layers.compactMap { layer -> CMPersistentTrackID? in
            if case .video(let trackID, _, _) = layer.content { return trackID }
            return nil
        } ?? [])
        XCTAssertEqual(videoTrackIDs.count, 2, "clip A's handle and clip B should both render during the dissolve")
        // The linked audio crossfades too: A's audio continues on a helper track under B.
        XCTAssertEqual(builtDissolve.composition.tracks.filter { $0.mediaType == .audio }.count, 2)
        XCTAssertEqual(builtDissolve.audioMix.inputParameters.count, 2)
        let gd = AVAssetImageGenerator(asset: builtDissolve.composition)
        gd.videoComposition = builtDissolve.videoComposition
        gd.requestedTimeToleranceBefore = .zero
        gd.requestedTimeToleranceAfter = .zero
        Self.writePNG(try await gd.image(at: .seconds(3.5)).image, name: "dissolve-mid.png")

        // 9. Multicam: the same stream as two synced "angles" 20 s apart; live-cut between them.
        let session = UUID()
        var angleA = asset
        angleA.id = UUID(); angleA.name = "Cam A"; angleA.role = .camera; angleA.syncGroupID = session; angleA.syncOffset = 0
        var angleB = asset
        angleB.id = UUID(); angleB.name = "Cam B"; angleB.role = .camera; angleB.syncGroupID = session; angleB.syncOffset = -20
        let group = try XCTUnwrap(MulticamGroup.groups(in: [angleA, angleB]).first)
        var multicam = MulticamEditor.timeline(cuts: [MulticamCut(range: TimeRange(start: 5, end: 15), assetID: angleA.id)], group: group,
                                               audioAssetID: angleA.id, canvas: .landscape1080, name: "Multicam")
        try MulticamEditor.cut(&multicam, at: 4, to: angleB.id, group: group)
        let cams = multicam.tracks[0].clips.sorted { $0.start < $1.start }
        XCTAssertEqual(cams.map(\.assetID), [angleA.id, angleB.id])
        XCTAssertEqual(cams[1].sourceIn, 29, accuracy: 1e-6, "session 9 s is source 29 s on Cam B")
        let builtMulticam = try await CompositionBuilder.build(timeline: multicam, assets: [angleA.id: angleA, angleB.id: angleB])
        XCTAssertTrue(builtMulticam.missingAssetIDs.isEmpty)
        XCTAssertEqual(builtMulticam.duration, 10, accuracy: 0.05)
        let gm = AVAssetImageGenerator(asset: builtMulticam.composition)
        gm.videoComposition = builtMulticam.videoComposition
        Self.writePNG(try await gm.image(at: .seconds(6)).image, name: "multicam-cam-b.png")

        // 9b. Grid shot: both angles on screen at once in a vertical 2-up.
        var grid = MulticamEditor.timeline(cuts: [MulticamCut(range: TimeRange(start: 25, end: 31), assetID: angleA.id, extraAngles: [angleB.id])],
                                           group: group, audioAssetID: angleA.id, canvas: .vertical1080, name: "Grid")
        XCTAssertEqual(MulticamEditor.gridPartners(of: grid.tracks[0].clips[0].id, in: grid).count, 1)
        try MulticamEditor.applyGrid(&grid, clipID: grid.tracks[0].clips[0].id, angles: [angleA.id, angleB.id], layout: .twoUp, group: group)
        let builtGrid = try await CompositionBuilder.build(timeline: grid, assets: [angleA.id: angleA, angleB.id: angleB])
        XCTAssertTrue(builtGrid.missingAssetIDs.isEmpty)
        let gridLayers = builtGrid.videoComposition.instructions.compactMap { $0 as? PulseCompositionInstruction }
            .first { $0.timeRange.containsTime(.seconds(3)) }?.layers.count ?? 0
        XCTAssertEqual(gridLayers, 2, "both cells render")
        let gg = AVAssetImageGenerator(asset: builtGrid.composition)
        gg.videoComposition = builtGrid.videoComposition
        Self.writePNG(try await gg.image(at: .seconds(3)).image, name: "multicam-grid-2up.png")

        // 10. Compound clip: two video clips + a title collapsed, then scaled down as one picture.
        var compoundEdit = Timeline.empty(name: "Compound", canvas: .landscape1080)
        let cv = compoundEdit.tracks[0].id, ct = compoundEdit.tracks[2].id, ca = compoundEdit.tracks[3].id
        try compoundEdit.insert(TimelineClip(name: "Shot 1", content: .media(assetID: asset.id), start: 0, sourceIn: 5, sourceDuration: 2), onTrack: cv)
        try compoundEdit.insert(TimelineClip(name: "Shot 2", content: .media(assetID: asset.id), start: 2, sourceIn: 40, sourceDuration: 2), onTrack: cv)
        try compoundEdit.insert(TimelineClip(name: "Shot audio", content: .media(assetID: asset.id), start: 0, sourceIn: 5, sourceDuration: 4), onTrack: ca)
        try compoundEdit.insert(TimelineClip(name: "Title", content: .text(TextElement(text: "COMPOUND")), start: 0.5, sourceDuration: 3), onTrack: ct)
        let (nestedTimeline, compoundID) = try CompoundEditor.makeCompound(in: &compoundEdit, clipIDs: compoundEdit.allClips.map(\.id), name: "Group")
        compoundEdit.updateClip(id: compoundID) { $0.transform.scale = AnimatedDouble(0.5) }
        var compoundOptions = CompositionBuilder.Options()
        compoundOptions.compounds = [nestedTimeline.id: nestedTimeline]
        let builtCompound = try await CompositionBuilder.build(timeline: compoundEdit, assets: [asset.id: asset], options: compoundOptions)
        XCTAssertTrue(builtCompound.missingAssetIDs.isEmpty)
        XCTAssertEqual(builtCompound.duration, 4, accuracy: 0.05)
        let groupInstruction = builtCompound.videoComposition.instructions
            .compactMap { $0 as? PulseCompositionInstruction }
            .first { $0.timeRange.containsTime(.seconds(2.5)) }
        let groupLayer = groupInstruction?.layers.first { if case .group = $0.content { return true }; return false }
        XCTAssertNotNil(groupLayer, "the compound renders as one group layer")
        if case .group(let children)? = groupLayer?.content {
            XCTAssertEqual(children.count, 2, "Shot 2 + the title are inside the group at 2.5 s")
        }
        XCTAssertEqual(builtCompound.composition.tracks.filter { $0.mediaType == .audio }.count, 1, "nested audio is mixed in")
        let gc = AVAssetImageGenerator(asset: builtCompound.composition)
        gc.videoComposition = builtCompound.videoComposition
        Self.writePNG(try await gc.image(at: .seconds(2.5)).image, name: "compound-scaled.png")
    }

    /// Live screen capture through ScreenCaptureKit. Skips when the runner has no Screen Recording permission.
    func testScreenRecordingWhenPermitted() async throws {
        let sources: [CaptureSource]
        do {
            sources = try await withThrowingTaskGroup(of: [CaptureSource].self) { group in
                group.addTask { try await SessionRecorder.sources() }
                group.addTask {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                    throw CaptureError.screenPermission
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }
        } catch {
            throw XCTSkip("Screen Recording not permitted on this machine: \(error.localizedDescription)")
        }
        guard let display = sources.first(where: { $0.kind == .display }) else { throw XCTSkip("no display") }
        let dir = Self.workDir.appendingPathComponent("capture-\(UUID().uuidString)", isDirectory: true)
        let recorder = SessionRecorder()
        do {
            try await recorder.start(RecordingOptions(source: display, captureSystemAudio: false, frameRate: 30, codec: .h264, outputDirectory: dir))
        } catch CaptureError.screenPermission {
            throw XCTSkip("Screen Recording not permitted")
        }
        // Record 1.5 s, pause 2 s, record 1.5 s: the file holds ~3 s with no gap.
        try await Task.sleep(nanoseconds: 1_500_000_000)
        recorder.pause()
        XCTAssertTrue(recorder.isPaused)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        recorder.resume()
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(recorder.elapsed, 3, accuracy: 0.5)
        let result = try await recorder.stop()
        let screen = try XCTUnwrap(result.files.first { $0.role == .gameplay })
        let meta = try await MediaProbe.probe(screen.url)
        XCTAssertTrue(meta.hasVideo)
        XCTAssertEqual(meta.duration, 3, accuracy: 0.6, "paused time is excluded; a static screen still records until Stop")
        print("screen capture:", screen.url.lastPathComponent, meta.width, "x", meta.height, String(format: "%.1fs", meta.duration))
    }

    func testPlaybackItemBuildsForTextOnlyTimeline() async throws {
        var timeline = Timeline.empty(name: "Titles", canvas: .vertical1080)
        let element = TextElement(text: "HELLO PULSE", style: TextStyle(fontSize: 120, weight: .black, strokeWidth: 10))
        try timeline.insert(TimelineClip(name: "Title", content: .text(element), start: 0, sourceDuration: 3), onTrack: timeline.tracks[2].id)
        let built = try await CompositionBuilder.build(timeline: timeline, assets: [:])
        XCTAssertEqual(built.duration, 3, accuracy: 0.01)
        let g = AVAssetImageGenerator(asset: built.composition)
        g.videoComposition = built.videoComposition
        let frame = try await g.image(at: .seconds(1.5)).image
        XCTAssertEqual(frame.width, 1080)
        try FileManager.default.createDirectory(at: Self.snapshotDir, withIntermediateDirectories: true)
        Self.writePNG(frame, name: "text-only.png")
    }

    static func writePNG(_ image: CGImage, name: String) {
        let rep = NSBitmapImageRep(cgImage: image)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: snapshotDir.appendingPathComponent(name))
        }
    }
}
