import AVFoundation
import CoreGraphics
import Foundation
import PulseCore
import Vision

/// Samples frames across a recording (keyframe-tolerant, hardware decoded) to measure motion,
/// brightness and scene cuts, and runs Vision face detection on a subset of frames.
public final class VisualAnalyzer: @unchecked Sendable {
    public struct Options: Sendable {
        /// Seconds between analysed frames. nil = automatic (1 s up to an hour, 2 s beyond).
        public var interval: Seconds?
        /// Run face detection on every Nth sample.
        public var faceEvery: Int = 2
        public var detectFaces: Bool = true

        public init(interval: Seconds? = nil, faceEvery: Int = 2, detectFaces: Bool = true) {
            self.interval = interval
            self.faceEvery = faceEvery
            self.detectFaces = detectFaces
        }
    }

    static let gridWidth = 32
    static let gridHeight = 18

    public init() {}

    public func analyze(url: URL, duration: Seconds, options: Options = Options(), progress: ProgressHandler? = nil,
                        isCancelled: @escaping @Sendable () -> Bool = { false }) async throws -> VisualFeatureSeries {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard !tracks.isEmpty else { throw EngineError.noVideoTrack(url) }
        let interval = options.interval ?? (duration > 3600 ? 2 : 1)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        let tolerance = CMTime(seconds: interval / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let count = max(1, Int(duration / interval))
        var motion: [Float] = []
        var brightness: [Float] = []
        var cuts: [Seconds] = []
        var faces: [FaceSample] = []
        var previousGrid: [Float]?
        var previousHistogram: [Float]?
        var cutScores: [Float] = []
        motion.reserveCapacity(count)
        brightness.reserveCapacity(count)

        for i in 0..<count {
            if isCancelled() { throw EngineError.cancelled }
            let t = Double(i) * interval
            guard let cg = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image else {
                motion.append(motion.last ?? 0)
                brightness.append(brightness.last ?? 0)
                continue
            }
            let (grid, histogram) = VisualAnalyzer.features(of: cg)
            let mean = grid.reduce(0, +) / Float(grid.count)
            brightness.append(mean)
            if let prev = previousGrid {
                var diff: Float = 0
                for k in grid.indices { diff += abs(grid[k] - prev[k]) }
                motion.append(diff / Float(grid.count))
            } else {
                motion.append(0)
            }
            if let prevHist = previousHistogram {
                // Chi-square-like histogram distance.
                var d: Float = 0
                for k in histogram.indices {
                    let s = histogram[k] + prevHist[k]
                    if s > 0 { d += (histogram[k] - prevHist[k]) * (histogram[k] - prevHist[k]) / s }
                }
                cutScores.append(d)
                if d > 0.5 { cuts.append(t) }
            }
            previousGrid = grid
            previousHistogram = histogram

            if options.detectFaces && i % max(1, options.faceEvery) == 0 {
                let boxes = VisualAnalyzer.detectFaces(in: cg)
                faces.append(FaceSample(time: t, boxes: boxes))
            }
            if i % 20 == 0 {
                progress?(EngineProgress(stage: "Analyzing video", fraction: Double(i) / Double(count)))
            }
        }
        // Discard cut bursts (fast motion flashes): keep cuts at least 1 s apart.
        var filtered: [Seconds] = []
        for c in cuts where filtered.last.map({ c - $0 >= 1 }) ?? true { filtered.append(c) }
        return VisualFeatureSeries(hop: interval, motion: motion, brightness: brightness, sceneCuts: filtered, faces: faces)
    }

    /// Luminance grid (32×18) and a 4×4×4 RGB histogram, normalized.
    static func features(of image: CGImage) -> (grid: [Float], histogram: [Float]) {
        let w = gridWidth
        let h = gridHeight
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        pixels.withUnsafeMutableBytes { raw in
            if let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: colorSpace,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.interpolationQuality = .low
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
        var grid = [Float](repeating: 0, count: w * h)
        var histogram = [Float](repeating: 0, count: 64)
        for p in 0..<(w * h) {
            let r = Float(pixels[p * 4]) / 255
            let g = Float(pixels[p * 4 + 1]) / 255
            let b = Float(pixels[p * 4 + 2]) / 255
            grid[p] = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let bin = min(Int(r * 4), 3) * 16 + min(Int(g * 4), 3) * 4 + min(Int(b * 4), 3)
            histogram[bin] += 1
        }
        let total = Float(w * h)
        for k in histogram.indices { histogram[k] /= total }
        return (grid, histogram)
    }

    /// Face rectangles in normalized TOP-LEFT coordinates (PulseCore convention).
    public static func detectFaces(in image: CGImage) -> [NormRect] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        let results = request.results ?? []
        return results.filter { $0.confidence > 0.5 }.map { obs in
            let b = obs.boundingBox // normalized, bottom-left origin
            return NormRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
        }
    }
}
