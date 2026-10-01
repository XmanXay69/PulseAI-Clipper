import Accelerate
import Foundation

/// Neural speaker embeddings: a pretrained GE2E speaker encoder (3-layer LSTM, 40 mel bands → 256-d
/// voice embedding) from Resemblyzer (Apache-2.0, trained on LibriSpeech + VoxCeleb), run with
/// Accelerate. Voices of the same person land close together regardless of what is said.
///
/// The front end and the windowing follow Resemblyzer exactly (16 kHz, 25 ms / 10 ms mel power
/// spectrogram, 1.6 s partial windows averaged), and `Tests/PulseEngineTests` checks the output
/// against embeddings computed by the original PyTorch model.
public final class SpeakerEncoder: @unchecked Sendable {
    public static let sampleRate = 16_000.0
    static let fftSize = 400
    static let hop = 160
    static let bins = 201
    static let mels = 40
    static let hidden = 256
    static let gates = 1024
    static let partialFrames = 160

    struct Layer {
        let input: Int
        let wih: [Float]   // gates × input
        let whh: [Float]   // gates × hidden
        let bias: [Float]  // gates (ih + hh)
    }

    let layers: [Layer]
    let linearW: [Float]   // hidden × hidden
    let linearB: [Float]
    let melFilters: [Float]  // mels × bins
    let window: [Float]
    let dftCos: [Float]    // fftSize × bins
    let dftSin: [Float]

    // MARK: Loading

    /// Where the weights live: inside PULSE.app, next to the sources (swift run / tests), or in
    /// Application Support/PULSE/Models.
    public static var modelURL: URL? {
        var candidates: [URL] = []
        if let bundled = Bundle.main.url(forResource: "SpeakerEncoder", withExtension: "bin") { candidates.append(bundled) }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Models/SpeakerEncoder.bin")
        candidates.append(repo)
        candidates.append(PulseDirectories.applicationSupport.appendingPathComponent("Models/SpeakerEncoder.bin"))
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static let loaded: SpeakerEncoder? = modelURL.flatMap { try? SpeakerEncoder(contentsOf: $0) }

    /// The shared encoder, or nil when the weights aren't installed.
    public static var shared: SpeakerEncoder? { loaded }

    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        guard data.count > 8, data.prefix(4) == Data("PSPK".utf8) else { throw EngineError.readerFailed("not a PULSE speaker model") }
        let halfCount = (data.count - 8) / 2
        var floats = [Float](repeating: 0, count: halfCount)
        data.withUnsafeBytes { raw in
            var source = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: raw.baseAddress! + 8), height: 1, width: vImagePixelCount(halfCount), rowBytes: halfCount * 2)
            floats.withUnsafeMutableBytes { out in
                var destination = vImage_Buffer(data: out.baseAddress!, height: 1, width: vImagePixelCount(halfCount), rowBytes: halfCount * 4)
                vImageConvert_Planar16FtoPlanarF(&source, &destination, 0)
            }
        }
        var offset = 0
        func take(_ n: Int) throws -> [Float] {
            guard offset + n <= floats.count else { throw EngineError.readerFailed("speaker model is truncated") }
            defer { offset += n }
            return Array(floats[offset..<(offset + n)])
        }
        var layers: [Layer] = []
        for l in 0..<3 {
            let input = l == 0 ? Self.mels : Self.hidden
            layers.append(Layer(input: input, wih: try take(Self.gates * input), whh: try take(Self.gates * Self.hidden), bias: try take(Self.gates)))
        }
        self.layers = layers
        linearW = try take(Self.hidden * Self.hidden)
        linearB = try take(Self.hidden)
        melFilters = try take(Self.mels * Self.bins)
        guard offset == floats.count else { throw EngineError.readerFailed("unexpected speaker model size") }
        let n = Self.fftSize
        window = (0..<n).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(n))) }   // periodic Hann
        var c = [Float](repeating: 0, count: n * Self.bins), s = c
        for i in 0..<n {
            for k in 0..<Self.bins {
                let angle = 2 * Double.pi * Double(k * i % n) / Double(n)
                c[i * Self.bins + k] = Float(cos(angle))
                s[i * Self.bins + k] = Float(-sin(angle))
            }
        }
        dftCos = c
        dftSin = s
    }

    // MARK: Front end

    /// Mel power spectrogram (frames × 40, row-major), centred frames with zero padding.
    public func melSpectrogram(_ wav: [Float]) -> (values: [Float], frames: Int) {
        let n = Self.fftSize, hop = Self.hop, bins = Self.bins
        let frames = 1 + wav.count / hop
        let padded = [Float](repeating: 0, count: n / 2) + wav + [Float](repeating: 0, count: n / 2 + hop)
        var framed = [Float](repeating: 0, count: frames * n)
        framed.withUnsafeMutableBufferPointer { out in
            padded.withUnsafeBufferPointer { src in
                for f in 0..<frames {
                    vDSP_vmul(src.baseAddress! + f * hop, 1, window, 1, out.baseAddress! + f * n, 1, vDSP_Length(n))
                }
            }
        }
        var re = [Float](repeating: 0, count: frames * bins), im = re
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans, Int32(frames), Int32(bins), Int32(n), 1, framed, Int32(n), dftCos, Int32(bins), 0, &re, Int32(bins))
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans, Int32(frames), Int32(bins), Int32(n), 1, framed, Int32(n), dftSin, Int32(bins), 0, &im, Int32(bins))
        var power = [Float](repeating: 0, count: frames * bins)
        vDSP_vmul(re, 1, re, 1, &power, 1, vDSP_Length(frames * bins))
        power.withUnsafeMutableBufferPointer { p in
            vDSP_vma(im, 1, im, 1, p.baseAddress!, 1, p.baseAddress!, 1, vDSP_Length(p.count))
        }
        var mel = [Float](repeating: 0, count: frames * Self.mels)
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasTrans, Int32(frames), Int32(Self.mels), Int32(bins), 1, power, Int32(bins), melFilters, Int32(bins), 0, &mel, Int32(Self.mels))
        return (mel, frames)
    }

    /// Resemblyzer's volume normalisation: raise quiet audio to −30 dBFS (never lowers).
    static func normalized(_ wav: [Float]) -> [Float] {
        guard !wav.isEmpty else { return wav }
        var ms: Float = 0
        vDSP_measqv(wav, 1, &ms, vDSP_Length(wav.count))
        let rms = Double(ms).squareRoot()
        guard rms > 0 else { return wav }
        let change = -30 - 20 * log10(rms)
        guard change > 0 else { return wav }
        var gain = Float(pow(10, change / 20))
        var out = [Float](repeating: 0, count: wav.count)
        vDSP_vsmul(wav, 1, &gain, &out, 1, vDSP_Length(wav.count))
        return out
    }

    /// Frame offsets of the 1.6 s partial windows covering `samples` (Resemblyzer's rate 1.3, coverage 0.75).
    static func partials(samples: Int) -> [Int] {
        let frames = Int(ceil(Double(samples + 1) / Double(hop)))
        let step = Int((sampleRate / 1.3 / Double(hop)).rounded())
        let steps = max(1, frames - partialFrames + step + 1)
        var starts = Array(stride(from: 0, to: steps, by: step))
        let coverage = Double(samples - starts.last! * hop) / Double(partialFrames * hop)
        if coverage < 0.75 && starts.count > 1 { starts.removeLast() }
        return starts
    }

    // MARK: Network

    /// Embeddings for a batch of mel windows, laid out time-major: [t][b][mel].
    func forward(timeMajor input: [Float], batch b: Int, frames t: Int) -> [[Float]] {
        let h = Self.hidden, g = Self.gates
        var x = input
        var lastHidden = [Float](repeating: 0, count: b * h)
        for layer in layers {
            // Input projections for every step at once.
            var pre = [Float](repeating: 0, count: t * b * g)
            for row in 0..<(t * b) { pre.replaceSubrange((row * g)..<((row + 1) * g), with: layer.bias) }
            cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasTrans, Int32(t * b), Int32(g), Int32(layer.input), 1, x, Int32(layer.input), layer.wih, Int32(layer.input), 1, &pre, Int32(g))
            var hState = [Float](repeating: 0, count: b * h)
            var cState = [Float](repeating: 0, count: b * h)
            var output = [Float](repeating: 0, count: t * b * h)
            var gatesBuffer = [Float](repeating: 0, count: b * g)
            var scratch = [Float](repeating: 0, count: h)
            var count = Int32(h)
            for step in 0..<t {
                gatesBuffer.withUnsafeMutableBufferPointer { gb in
                    pre.withUnsafeBufferPointer { p in gb.baseAddress!.update(from: p.baseAddress! + step * b * g, count: b * g) }
                }
                cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasTrans, Int32(b), Int32(g), Int32(h), 1, hState, Int32(h), layer.whh, Int32(h), 1, &gatesBuffer, Int32(g))
                gatesBuffer.withUnsafeMutableBufferPointer { gb in
                    hState.withUnsafeMutableBufferPointer { hs in
                        cState.withUnsafeMutableBufferPointer { cs in
                            scratch.withUnsafeMutableBufferPointer { sc in
                                for row in 0..<b {
                                    let base = gb.baseAddress! + row * g
                                    let i = base, f = base + h, cell = base + 2 * h, o = base + 3 * h
                                    Self.sigmoid(i, &count); Self.sigmoid(f, &count); Self.sigmoid(o, &count)
                                    vvtanhf(cell, cell, &count)
                                    let c = cs.baseAddress! + row * h, hh = hs.baseAddress! + row * h
                                    vDSP_vmul(c, 1, f, 1, c, 1, vDSP_Length(h))           // c = f·c
                                    vDSP_vma(i, 1, cell, 1, c, 1, c, 1, vDSP_Length(h))     // c += i·g
                                    vvtanhf(sc.baseAddress!, c, &count)
                                    vDSP_vmul(o, 1, sc.baseAddress!, 1, hh, 1, vDSP_Length(h)) // h = o·tanh(c)
                                }
                            }
                        }
                    }
                }
                output.replaceSubrange((step * b * h)..<((step + 1) * b * h), with: hState)
            }
            x = output
            lastHidden = hState
        }
        // Linear + ReLU + L2 normalisation.
        var embedded = [Float](repeating: 0, count: b * h)
        for row in 0..<b { embedded.replaceSubrange((row * h)..<((row + 1) * h), with: linearB) }
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasTrans, Int32(b), Int32(h), Int32(h), 1, lastHidden, Int32(h), linearW, Int32(h), 1, &embedded, Int32(h))
        return (0..<b).map { row in
            var v = Array(embedded[(row * h)..<((row + 1) * h)]).map { max(0, $0) }
            Self.normalize(&v)
            return v
        }
    }

    static func sigmoid(_ x: UnsafeMutablePointer<Float>, _ count: inout Int32) {
        var minusOne: Float = -1, one: Float = 1
        let n = vDSP_Length(count)
        vDSP_vsmul(x, 1, &minusOne, x, 1, n)
        vvexpf(x, x, &count)
        vDSP_vsadd(x, 1, &one, x, 1, n)
        vvrecf(x, x, &count)
    }

    static func normalize(_ v: inout [Float]) {
        var norm: Float = 0
        vDSP_svesq(v, 1, &norm, vDSP_Length(v.count))
        norm = norm.squareRoot()
        guard norm > 0 else { return }
        var inv = 1 / norm
        v.withUnsafeMutableBufferPointer { p in vDSP_vsmul(p.baseAddress!, 1, &inv, p.baseAddress!, 1, vDSP_Length(p.count)) }
    }

    // MARK: Utterances

    /// One embedding per utterance (16 kHz mono), batching their partial windows through the network.
    public func embed(_ utterances: [[Float]], batchSize: Int = 32) -> [[Float]] {
        struct Window { let utterance: Int; let mels: ArraySlice<Float> }
        var windows: [Window] = []
        for (u, raw) in utterances.enumerated() {
            let wav = Self.normalized(raw)
            let starts = Self.partials(samples: wav.count)
            let needed = (starts.last! + Self.partialFrames) * Self.hop
            let padded = wav.count <= needed ? wav + [Float](repeating: 0, count: needed - wav.count + 1) : wav
            let (mel, frames) = melSpectrogram(padded)
            for s in starts where s + Self.partialFrames <= frames {
                windows.append(Window(utterance: u, mels: mel[(s * Self.mels)..<((s + Self.partialFrames) * Self.mels)]))
            }
        }
        var sums = [[Float]](repeating: [Float](repeating: 0, count: Self.hidden), count: utterances.count)
        var start = 0
        while start < windows.count {
            let chunk = Array(windows[start..<min(windows.count, start + batchSize)])
            let b = chunk.count, t = Self.partialFrames, m = Self.mels
            var timeMajor = [Float](repeating: 0, count: t * b * m)
            for (k, w) in chunk.enumerated() {
                let base = w.mels.startIndex
                for step in 0..<t {
                    for j in 0..<m { timeMajor[(step * b + k) * m + j] = w.mels[base + step * m + j] }
                }
            }
            for (k, e) in forward(timeMajor: timeMajor, batch: b, frames: t).enumerated() {
                let u = chunk[k].utterance
                for j in 0..<Self.hidden { sums[u][j] += e[j] }
            }
            start += batchSize
        }
        return sums.map { s in var v = s; Self.normalize(&v); return v }
    }

    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        var d: Float = 0
        vDSP_dotpr(a, 1, b, 1, &d, vDSP_Length(min(a.count, b.count)))
        return d
    }
}
