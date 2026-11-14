import Foundation

/// A rendered frame in numbers: enough to tell a real picture from a black or one-colour one, and to tell
/// whether it is still the picture it used to be.
public struct RenderedFrame: Hashable, Sendable {
    public var width: Int
    public var height: Int
    /// Mean brightness, 0…1.
    public var luma: Double
    /// How much the brightness varies across the frame, 0…1. A flat colour is 0.
    public var detail: Double
    /// The share of the frame that is near black.
    public var dark: Double
    /// The picture as a 16×16 grid of mean colours, row by row from the top, three bytes a cell.
    public var signature: [UInt8]

    public var aspect: Double { height > 0 ? Double(width) / Double(height) : 0 }
}

/// Checks the frame the viewer really renders (#1021). The window screenshots CI takes can't see the
/// viewer's picture: it is drawn by the player, not by the views. So the walk-through renders the frame
/// itself, and this decides whether it is a picture at all, whether it has the edit's shape, and whether it
/// has changed from the frame kept as the reference.
public enum FrameCheck {
    public static let grid = 16

    public enum Verdict: String, Sendable {
        /// Nothing wrong found.
        case ok
        /// A picture, but not the one in the reference. Worth a look; not a failure on its own.
        case changed
        /// Black, one flat colour, the wrong shape, or nothing like the reference.
        case failed
    }

    /// Differences below these are the same picture. Measured on CI: the same commit rendered ten times over
    /// gave identical signatures, so anything above rounding is a real change.
    public static let sameMean = 0.004, sameWorst = 0.06
    /// A mean difference above this is a different picture: a missing layer, a moved layout, swapped
    /// colours. (Losing the facecam from the sample short moves it 0.06; a black frame, 0.32.)
    public static let differentMean = 0.05

    /// Reads an RGBA frame (8 bits a channel, rows from the top). Nil when the buffer doesn't match the size.
    public static func stats(rgba: [UInt8], width: Int, height: Int) -> RenderedFrame? {
        guard width >= grid, height >= grid, rgba.count >= width * height * 4 else { return nil }
        var sum = 0.0, squares = 0.0, dark = 0
        var cells = [Double](repeating: 0, count: grid * grid * 3)
        var counts = [Int](repeating: 0, count: grid * grid)
        for y in 0..<height {
            let row = min(grid - 1, y * grid / height)
            for x in 0..<width {
                let i = (y * width + x) * 4
                let r = Double(rgba[i]), g = Double(rgba[i + 1]), b = Double(rgba[i + 2])
                let luma = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
                sum += luma
                squares += luma * luma
                if luma < 0.04 { dark += 1 }
                let cell = row * grid + min(grid - 1, x * grid / width)
                cells[cell * 3] += r
                cells[cell * 3 + 1] += g
                cells[cell * 3 + 2] += b
                counts[cell] += 1
            }
        }
        let n = Double(width * height)
        let mean = sum / n
        var signature = [UInt8](repeating: 0, count: cells.count)
        for cell in 0..<(grid * grid) {
            let count = Double(max(counts[cell], 1))
            for channel in 0..<3 { signature[cell * 3 + channel] = UInt8((cells[cell * 3 + channel] / count).rounded().clamped(0, 255)) }
        }
        return RenderedFrame(width: width, height: height, luma: mean, detail: max(0, squares / n - mean * mean).squareRoot(),
                          dark: Double(dark) / n, signature: signature)
    }

    /// How far two signatures are apart: the mean difference over the whole frame, and the difference in the
    /// cell that differs most (a caption that vanished changes a few cells a lot and the mean hardly at all).
    /// Both 0…1; 1 when the signatures aren't the same size.
    public static func distance(_ a: [UInt8], _ b: [UInt8]) -> (mean: Double, worst: Double) {
        guard a.count == b.count, !a.isEmpty, a.count % 3 == 0 else { return (1, 1) }
        var total = 0.0, worst = 0.0
        for cell in 0..<(a.count / 3) {
            var here = 0.0
            for channel in 0..<3 { here += abs(Double(a[cell * 3 + channel]) - Double(b[cell * 3 + channel])) }
            here /= 3 * 255
            total += here
            worst = max(worst, here)
        }
        return (total / Double(a.count / 3), worst)
    }

    public static func hex(_ signature: [UInt8]) -> String {
        signature.map { String(format: "%02x", $0) }.joined()
    }

    public static func signature(hex: String) -> [UInt8]? {
        let characters = Array(hex.utf8)
        guard characters.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(characters.count / 2)
        func value(_ c: UInt8) -> UInt8? {
            switch c {
            case 48...57: return c - 48
            case 97...102: return c - 87
            case 65...70: return c - 55
            default: return nil
            }
        }
        for i in stride(from: 0, to: characters.count, by: 2) {
            guard let high = value(characters[i]), let low = value(characters[i + 1]) else { return nil }
            out.append(high << 4 | low)
        }
        return out
    }

    /// The frames kept to compare against, by capture name.
    public struct Reference: Codable, Hashable, Sendable {
        public var frames: [String: String]

        public init(frames: [String: String] = [:]) { self.frames = frames }

        public init?(json: Data) {
            guard let decoded = try? JSONDecoder().decode(Reference.self, from: json) else { return nil }
            self = decoded
        }

        /// One frame a line, names in order, so a change to it reads cleanly in a diff.
        public var json: String {
            let lines = frames.keys.sorted().map { "    \"\($0)\": \"\(frames[$0] ?? "")\"" }
            return "{\n  \"frames\": {\n" + lines.joined(separator: ",\n") + "\n  }\n}\n"
        }
    }

    public struct Result: Hashable, Sendable {
        public var name: String
        public var stats: RenderedFrame
        public var verdict: Verdict
        /// What is wrong or different, in words; empty when nothing is.
        public var findings: [String]
        /// Distance from the reference, when there is one for this frame.
        public var mean: Double?
        public var worst: Double?

        /// One log line: "UI-FRAME 06-editor 720x1280 luma 0.31 detail 0.22 dark 2% · same as the reference".
        public var line: String {
            let tag: String
            switch verdict {
            case .ok: tag = "UI-FRAME"
            case .changed: tag = "UI-FRAME-CHANGED"
            case .failed: tag = "UI-FRAME-FAIL"
            }
            let numbers = String(format: "%dx%d luma %.2f detail %.2f dark %d%%", stats.width, stats.height, stats.luma, stats.detail,
                                 Int((stats.dark * 100).rounded()))
            return "\(tag) \(name) \(numbers) · \(findings.isEmpty ? "a picture; no reference kept for it" : findings.joined(separator: "; "))"
        }
    }

    /// Judges one frame. `expectedAspect` is the edit's own shape (width over height).
    public static func judge(name: String, stats: RenderedFrame, expectedAspect: Double? = nil, reference: Reference? = nil) -> Result {
        var findings: [String] = []
        var verdict = Verdict.ok
        if stats.detail < 0.01 {
            verdict = .failed
            findings.append(stats.luma < 0.03 ? "the frame is black: nothing was rendered" : "the frame is one flat colour: nothing was rendered over it")
        }
        if let expectedAspect, expectedAspect > 0, abs(stats.aspect / expectedAspect - 1) > 0.02 {
            verdict = .failed
            findings.append(String(format: "the frame is %.3f wide for its height and the edit is %.3f", stats.aspect, expectedAspect))
        }
        var mean: Double?, worst: Double?
        if let kept = reference?.frames[name].flatMap(signature(hex:)) {
            let apart = distance(stats.signature, kept)
            mean = apart.mean
            worst = apart.worst
            if apart.mean > differentMean {
                verdict = .failed
                findings.append(String(format: "not the picture in the reference (%.3f apart, limit %.2f)", apart.mean, differentMean))
            } else if apart.mean > sameMean || apart.worst > sameWorst {
                if verdict == .ok { verdict = .changed }
                findings.append(String(format: "differs from the reference (%.3f over the frame, %.2f in one place)", apart.mean, apart.worst))
            } else if findings.isEmpty {
                findings.append("same as the reference")
            }
        }
        return Result(name: name, stats: stats, verdict: verdict, findings: findings, mean: mean, worst: worst)
    }
}
