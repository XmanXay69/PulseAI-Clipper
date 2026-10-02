import AVFoundation
import CoreGraphics
import Foundation
import PulseCore
import Vision

/// Studies a reference video ("edit my VOD like this one"): the normal analysis (audio, speech,
/// cuts, faces), a finer frame pass on shorter references so quick cuts and punch-ins aren't
/// missed, and on-screen text reading for captions and pop-ups. Everything runs on this Mac.
public enum ReferenceScanner {
    public static func scan(asset: MediaAsset, ai: AISettings, cacheDirectory: URL, progress: @escaping ProgressHandler,
                            isCancelled: @escaping @Sendable () -> Bool = { false }) async throws -> ReferenceStyle {
        let url = MediaAccess.resolve(asset)
        let duration = asset.metadata.duration
        guard duration > 1 else { throw EngineError.fileMissing(url) }

        // 1. Audio, speech and the standard frame pass (0–60 %).
        let pipeline = AnalysisPipeline(cacheDirectory: cacheDirectory)
        let options = AnalysisPipeline.Options(transcribe: true, detectFaces: true, ai: ai, speed: ai.analysisSpeed)
        var analysis = try await pipeline.run(asset: asset, options: options, progress: { p in
            progress(EngineProgress(stage: "Listening to the reference — \(p.stage.lowercased())", fraction: p.fraction * 0.6))
        }, isCancelled: isCancelled).analysis

        // 2. A finer look at the cuts and zooms (60–85 %): ≤ 1,200 frames, faces on every one.
        if asset.metadata.hasVideo || asset.kind == .video {
            let interval = max(0.5, duration / 1200)
            if interval < (analysis.visual?.hop ?? 1) || (analysis.visual?.faces.count ?? 0) < Int(duration / 2) {
                let fine = try await VisualAnalyzer().analyze(url: url, duration: duration,
                                                              options: VisualAnalyzer.Options(interval: interval, faceEvery: 1, detectFaces: true),
                                                              progress: { p in
                    progress(EngineProgress(stage: "Watching the cuts and zooms", fraction: 0.6 + p.fraction * 0.25))
                }, isCancelled: isCancelled)
                analysis.visual = fine
            }
        }

        // 3. Read the on-screen text (85–100 %): ≤ 300 frames.
        let text = try await readText(url: url, duration: duration, progress: { fraction in
            progress(EngineProgress(stage: "Reading the captions", fraction: 0.85 + fraction * 0.15))
        }, isCancelled: isCancelled)

        var size = asset.metadata.size
        if size.isEmpty { size = Size2(1920, 1080) }
        let name = asset.name.isEmpty ? url.deletingPathExtension().lastPathComponent : asset.name
        let style = ReferenceStyleAnalyzer.measure(name: name, analysis: analysis, text: text, frameSize: size)
        PulseLog.info("Reference “\(name)”: \(style.summary) — \(String(format: "%.1f", style.cutsPerMinute)) cuts/min, "
                      + "\(String(format: "%.1f", style.zoomsPerMinute)) zooms/min, captions \(style.hasCaptions), music \(String(format: "%.2f", style.musicBed))")
        return style
    }

    /// Text lines on evenly spaced frames, in normalized top-left coordinates.
    static func readText(url: URL, duration: Seconds, progress: @escaping (Double) -> Void,
                         isCancelled: @escaping @Sendable () -> Bool) async throws -> [TextSample] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard !tracks.isEmpty else { return [] }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)
        let interval = max(1, duration / 300)
        let tolerance = CMTime(seconds: min(0.25, interval / 4), preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        let count = max(1, Int(duration / interval))
        var samples: [TextSample] = []
        for i in 0..<count {
            if isCancelled() { throw EngineError.cancelled }
            let t = (Double(i) + 0.5) * interval
            guard let image = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image else { continue }
            samples.append(TextSample(time: t, boxes: recognizeText(in: image)))
            if i % 10 == 0 { progress(Double(i) / Double(count)) }
        }
        return samples
    }

    public static func recognizeText(in image: CGImage) -> [TextBox] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.02
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first, candidate.confidence > 0.3 else { return nil }
            let b = observation.boundingBox // normalized, bottom-left origin
            return TextBox(rect: NormRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height), text: candidate.string)
        }
    }
}
