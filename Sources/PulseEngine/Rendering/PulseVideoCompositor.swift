import AVFoundation
import CoreImage
import Foundation
import PulseCore

/// AVFoundation custom compositor. Used for both live playback (AVPlayer) and export
/// (AVAssetReaderVideoCompositionOutput) so what you see is exactly what you export.
public final class PulseVideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let renderQueue = DispatchQueue(label: "app.pulse.compositor", qos: .userInitiated)
    private var renderContext: AVVideoCompositionRenderContext?
    private var cancelGeneration = 0
    private let renderer = FrameRenderer.shared

    public var sourcePixelBufferAttributes: [String: Any]? {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
         kCVPixelBufferMetalCompatibilityKey as String: true]
    }

    public var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
         kCVPixelBufferMetalCompatibilityKey as String: true]
    }

    public var supportsWideColorSourceFrames: Bool { false }

    public func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderQueue.sync { renderContext = newRenderContext }
    }

    public func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        let generation = renderQueue.sync { cancelGeneration }
        renderQueue.async { [weak self] in
            guard let self else { return }
            if generation != self.cancelGeneration {
                request.finishCancelledRequest()
                return
            }
            guard let instruction = request.videoCompositionInstruction as? PulseCompositionInstruction else {
                request.finish(with: EngineError.exportFailed("unexpected composition instruction"))
                return
            }
            guard let output = request.renderContext.newPixelBuffer() else {
                request.finish(with: EngineError.exportFailed("out of video memory"))
                return
            }
            autoreleasepool {
                let time = request.compositionTime.secondsValue
                let image = self.renderer.render(instruction: instruction, at: time) { trackID in
                    request.sourceFrame(byTrackID: trackID)
                }
                let size = request.renderContext.size
                let scaleX = size.width / instruction.scene.renderSize.width
                let scaleY = size.height / instruction.scene.renderSize.height
                let fitted = (abs(scaleX - 1) > 0.001 || abs(scaleY - 1) > 0.001) ? image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY)) : image
                self.renderer.context.render(fitted, to: output, bounds: CGRect(origin: .zero, size: size), colorSpace: self.renderer.colorSpace)
            }
            request.finish(withComposedVideoFrame: output)
        }
    }

    public func cancelAllPendingVideoCompositionRequests() {
        renderQueue.sync { cancelGeneration += 1 }
    }
}
