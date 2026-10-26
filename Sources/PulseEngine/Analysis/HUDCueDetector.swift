import AVFoundation
import CoreGraphics
import Foundation
import PulseCore
import Vision

/// Reads the game's own banners — "VICTORY ROYALE", "ELIMINATED", "DOUBLE KILL", "YOU DIED" — off sampled
/// frames with on-device text recognition, so wins and deaths count as moments even when nobody shouts.
/// Only big text is read (banners are large; chat overlays and kill feeds are small), at a frame every two
/// seconds, on the fast recognizer: about a minute per hour of gameplay on Apple silicon.
public enum HUDCueDetector {
    public static func detect(url: URL, duration: Seconds, interval: Seconds = 2, progress: ProgressHandler? = nil,
                              isCancelled: @escaping @Sendable () -> Bool = { false }) async throws -> [HUDEvent] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard !tracks.isEmpty else { return [] }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)
        let tolerance = CMTime(seconds: interval / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let count = max(1, Int(duration / interval))
        var events: [HUDEvent] = []
        for i in 0..<count {
            if isCancelled() { throw EngineError.cancelled }
            let t = Double(i) * interval
            guard let cg = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image else { continue }
            for (text, confidence) in recognizeBigText(in: cg) {
                if let event = HUDCues.event(forText: text, at: t, confidence: Double(confidence)) { events.append(event) }
            }
            if i % 30 == 0 {
                progress?(EngineProgress(stage: "Reading game banners", fraction: Double(i) / Double(count)))
            }
        }
        return HUDCues.coalesce(events)
    }

    /// Text at least 3 % of the frame tall, with the recognizer's confidence.
    static func recognizeBigText(in image: CGImage) -> [(String, Float)] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.03
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return (request.results ?? []).compactMap { observation in
            guard let top = observation.topCandidates(1).first, top.confidence >= 0.4 else { return nil }
            return (top.string, top.confidence)
        }
    }
}
