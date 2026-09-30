import AppKit
import AVFoundation
import Foundation
import PulseCore

/// Generates and caches poster frames and filmstrips. Uses AVAssetImageGenerator with keyframe
/// tolerance for speed (hardware decode, no full-frame decode of long recordings).
public actor ThumbnailService {
    public static let shared = ThumbnailService()

    private let cacheDirectory: URL
    private var memory: [String: CGImage] = [:]
    private var memoryOrder: [String] = []
    private let memoryLimit = 600
    private var generators: [String: AVAssetImageGenerator] = [:]

    public init(cacheDirectory: URL = PulseDirectories.cache("Thumbnails")) {
        self.cacheDirectory = cacheDirectory
    }

    private func generator(for url: URL, maxSize: CGSize, precise: Bool) -> AVAssetImageGenerator {
        let key = "\(url.path)|\(Int(maxSize.width))x\(Int(maxSize.height))|\(precise)"
        if let g = generators[key] { return g }
        let asset = AVURLAsset(url: url)
        let g = AVAssetImageGenerator(asset: asset)
        g.appliesPreferredTrackTransform = true
        g.maximumSize = maxSize
        if precise {
            g.requestedTimeToleranceBefore = .zero
            g.requestedTimeToleranceAfter = .zero
        } else {
            g.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
            g.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)
        }
        if generators.count > 24 { generators.removeAll() }
        generators[key] = g
        return g
    }

    private func cacheKey(_ url: URL, _ time: Seconds, _ width: Int) -> String {
        let t = Int((time * 10).rounded())
        return "\(abs(url.path.hashValue))-\(t)-\(width)"
    }

    /// Thumbnail at a time. Cached in memory and on disk (JPEG).
    public func image(for url: URL, at time: Seconds, maxWidth: Int = 320, precise: Bool = false) async -> CGImage? {
        let key = cacheKey(url, time, maxWidth)
        if let hit = memory[key] { return hit }
        let file = cacheDirectory.appendingPathComponent(key + ".jpg")
        if let src = CGImageSourceCreateWithURL(file as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            remember(key, img)
            return img
        }
        if MediaTypes.kind(for: url) == .image {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxWidth, kCGImageSourceCreateThumbnailWithTransform: true]
            let img = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
            if let img { remember(key, img) }
            return img
        }
        let g = generator(for: url, maxSize: CGSize(width: maxWidth, height: maxWidth), precise: precise)
        guard let result = try? await g.image(at: CMTime(seconds: max(0, time), preferredTimescale: 600)) else { return nil }
        let img = result.image
        remember(key, img)
        writeJPEG(img, to: file)
        return img
    }

    /// Evenly spaced frames across a range (timeline filmstrips, candidate previews).
    public func filmstrip(for url: URL, range: TimeRange, count: Int, maxWidth: Int = 160) async -> [CGImage?] {
        guard count > 0 else { return [] }
        var result: [CGImage?] = []
        for i in 0..<count {
            let t = range.start + range.duration * (Double(i) + 0.5) / Double(count)
            result.append(await image(for: url, at: t, maxWidth: maxWidth))
        }
        return result
    }

    private func remember(_ key: String, _ image: CGImage) {
        memory[key] = image
        memoryOrder.append(key)
        if memoryOrder.count > memoryLimit {
            let drop = memoryOrder.removeFirst()
            memory[drop] = nil
        }
    }

    private nonisolated func writeJPEG(_ image: CGImage, to url: URL) {
        let rep = NSBitmapImageRep(cgImage: image)
        if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.78]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Writes a poster image (used for project thumbnails).
    public func writePoster(for url: URL, at time: Seconds, to destination: URL, maxWidth: Int = 640) async -> Bool {
        guard let img = await image(for: url, at: time, maxWidth: maxWidth) else { return false }
        writeJPEG(img, to: destination)
        return FileManager.default.fileExists(atPath: destination.path)
    }

    public func clearMemory() {
        memory.removeAll()
        memoryOrder.removeAll()
        generators.removeAll()
    }
}

/// Audio waveform peaks for timeline drawing, streamed with AVAssetReader and cached to disk.
public actor WaveformService {
    public static let shared = WaveformService()

    /// Peaks per second stored in the cache (zoomed-out views downsample further).
    public static let peaksPerSecond = 50

    private let cacheDirectory: URL
    private var memory: [String: [Float]] = [:]
    private var inFlight: [String: Task<[Float], Never>] = [:]

    public init(cacheDirectory: URL = PulseDirectories.cache("Waveforms")) {
        self.cacheDirectory = cacheDirectory
    }

    /// Normalized peak amplitudes (0…1) at `peaksPerSecond` for the whole file.
    public func peaks(for url: URL) async -> [Float] {
        let key = "\(abs(url.path.hashValue))"
        if let hit = memory[key] { return hit }
        if let running = inFlight[key] { return await running.value }
        let file = cacheDirectory.appendingPathComponent(key + ".wave")
        if let data = try? Data(contentsOf: file), let series = try? JSONDecoder().decode(FloatSeries.self, from: data) {
            memory[key] = series.values
            return series.values
        }
        let task = Task.detached(priority: .utility) { () -> [Float] in
            (try? WaveformService.compute(url: url)) ?? []
        }
        inFlight[key] = task
        let values = await task.value
        inFlight[key] = nil
        memory[key] = values
        if !values.isEmpty, let data = try? JSONEncoder().encode(FloatSeries(values)) {
            try? data.write(to: file, options: .atomic)
        }
        return values
    }

    static func compute(url: URL) throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let semaphore = DispatchSemaphore(value: 0)
        var audioTrack: AVAssetTrack?
        asset.loadTracks(withMediaType: .audio) { tracks, _ in
            audioTrack = tracks?.first
            semaphore.signal()
        }
        semaphore.wait()
        guard let track = audioTrack else { return [] }
        let reader = try AVAssetReader(asset: asset)
        let sampleRate = 8000.0
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
        guard reader.startReading() else { throw EngineError.readerFailed(reader.error?.localizedDescription ?? "unknown") }
        let samplesPerPeak = Int(sampleRate) / peaksPerSecond
        var peaks: [Float] = []
        var current: Float = 0
        var counter = 0
        while let buffer = output.copyNextSampleBuffer() {
            let samples = SampleBufferReader.floats(from: buffer)
            for sample in samples {
                current = max(current, abs(sample))
                counter += 1
                if counter >= samplesPerPeak {
                    peaks.append(min(current, 1))
                    current = 0
                    counter = 0
                }
            }
        }
        if counter > 0 { peaks.append(min(current, 1)) }
        return peaks
    }

    /// Downsamples peaks for a pixel width.
    public static func downsample(_ peaks: [Float], range: TimeRange, buckets: Int) -> [Float] {
        guard buckets > 0, !peaks.isEmpty else { return [] }
        let pps = Double(peaksPerSecond)
        var out = [Float](repeating: 0, count: buckets)
        for b in 0..<buckets {
            let t0 = range.start + range.duration * Double(b) / Double(buckets)
            let t1 = range.start + range.duration * Double(b + 1) / Double(buckets)
            let i0 = max(0, Int(t0 * pps))
            let i1 = min(peaks.count, max(i0 + 1, Int(t1 * pps)))
            guard i0 < peaks.count else { break }
            var m: Float = 0
            for i in i0..<i1 { m = max(m, peaks[i]) }
            out[b] = m
        }
        return out
    }
}
