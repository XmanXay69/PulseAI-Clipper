import AVFoundation
import CoreGraphics
import Foundation
import PulseCore
import Vision

/// Reads the face on camera (#501): on a frame every second or two, the outline of the mouth, eyes and
/// brows is found with on-device face landmarks and turned into four shape measures. A jaw-drop nobody
/// voiced then counts as a reaction beside the sound.
///
/// Everything runs on this Mac. No face is identified, no picture is kept: only the four numbers per frame.
/// A facecam in a corner is cropped out of a larger decode first, since a face a few dozen pixels across has
/// no readable mouth.
public enum FaceExpressionAnalyzer {
    /// `regionAt` gives where the face is expected at a time of the recording (the facecam overlay), in
    /// normalized top-left coordinates; nil looks at the whole frame. Returns nil when a face was found on
    /// fewer than one frame in twenty: nothing reliable can be said about so little.
    public static func analyze(url: URL, duration: Seconds, interval: Seconds? = nil, regionAt: @escaping @Sendable (Seconds) -> NormRect?,
                               progress: ProgressHandler? = nil, isCancelled: @escaping @Sendable () -> Bool = { false }) async throws -> ExpressionSeries? {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard !tracks.isEmpty, duration > 0 else { return nil }
        let step = interval ?? (duration > 3600 ? 2 : 1)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        let tolerance = CMTime(seconds: step / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let count = max(1, Int(duration / step))
        var mouthOpen = [Float](repeating: ExpressionSeries.absent, count: count)
        var mouthWidth = mouthOpen, eyeOpen = mouthOpen, browRaise = mouthOpen
        for i in 0..<count {
            if isCancelled() { throw EngineError.cancelled }
            let time = Double(i) * step
            if i % 30 == 0 { progress?(EngineProgress(stage: "Reading reactions on camera", fraction: Double(i) / Double(count))) }
            guard let frame = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image else { continue }
            let picture = crop(frame, to: regionAt(time)) ?? frame
            guard let found = measures(in: picture) else { continue }
            mouthOpen[i] = Float(found.mouthOpen)
            mouthWidth[i] = Float(found.mouthWidth)
            eyeOpen[i] = Float(found.eyeOpen)
            browRaise[i] = Float(found.browRaise)
        }
        let series = ExpressionSeries(hop: step, mouthOpen: mouthOpen, mouthWidth: mouthWidth, eyeOpen: eyeOpen, browRaise: browRaise)
        return series.coverage >= 0.05 ? series : nil
    }

    /// The facecam with a margin, so a face at its edge is still whole. Nil when there is no region or it is
    /// too small to hold a readable face.
    static func crop(_ image: CGImage, to region: NormRect?) -> CGImage? {
        guard let region else { return nil }
        let width = Double(image.width), height = Double(image.height)
        let x = max(0, (region.x - region.width * 0.1) * width)
        let y = max(0, (region.y - region.height * 0.1) * height)
        let rect = CGRect(x: x, y: y, width: min(width - x, region.width * 1.2 * width), height: min(height - y, region.height * 1.2 * height)).integral
        guard rect.width >= 48, rect.height >= 48 else { return nil }
        return image.cropping(to: rect)
    }

    /// The four measures for the largest face in the picture; nil when there is none or its mouth and eyes
    /// weren't outlined.
    static func measures(in image: CGImage) -> FaceExpressionMath.Measures? {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let faces = (request.results ?? []).filter { $0.confidence > 0.5 }
        guard let face = faces.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }),
              let landmarks = face.landmarks else { return nil }
        // Landmark points come relative to the face box, x across and y up: the form the measures expect.
        func points(_ region: VNFaceLandmarkRegion2D?) -> [FaceExpressionMath.Point] {
            (region?.normalizedPoints ?? []).map { FaceExpressionMath.Point(Double($0.x), Double($0.y)) }
        }
        return FaceExpressionMath.measures(FaceExpressionMath.Landmarks(
            outerLips: points(landmarks.outerLips), innerLips: points(landmarks.innerLips),
            leftEye: points(landmarks.leftEye), rightEye: points(landmarks.rightEye),
            leftBrow: points(landmarks.leftEyebrow), rightBrow: points(landmarks.rightEyebrow)))
    }
}
