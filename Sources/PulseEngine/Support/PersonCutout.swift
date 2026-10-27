import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Vision

/// Cuts the person out of a frame (#363) for the "big face" thumbnail style: Vision's person
/// segmentation as the alpha of the picture, so the subject can sit on a colour panel.
public enum PersonCutout {
    /// The frame with everything but the person transparent, or nil when no person is found.
    public static func cutout(_ image: CGImage) -> CGImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let mask = request.results?.first?.pixelBuffer else { return nil }
        let source = CIImage(cgImage: image)
        var maskImage = CIImage(cvPixelBuffer: mask)
        let sx = source.extent.width / maskImage.extent.width
        let sy = source.extent.height / maskImage.extent.height
        maskImage = maskImage.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        // Nothing worth cutting when the mask is almost empty.
        guard coverage(of: mask) > 0.02 else { return nil }
        let blend = CIFilter.blendWithMask()
        blend.inputImage = source
        blend.backgroundImage = CIImage(color: .clear).cropped(to: source.extent)
        blend.maskImage = maskImage
        guard let output = blend.outputImage else { return nil }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(output, from: source.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    /// Share of mask pixels that are "person".
    static func coverage(of mask: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return 0 }
        let width = CVPixelBufferGetWidth(mask), height = CVPixelBufferGetHeight(mask), stride = CVPixelBufferGetBytesPerRow(mask)
        guard width > 0, height > 0 else { return 0 }
        var on = 0
        var total = 0
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var y = 0
        while y < height {
            var x = 0
            while x < width {
                if bytes[y * stride + x] > 127 { on += 1 }
                total += 1
                x += 4
            }
            y += 4
        }
        return total > 0 ? Double(on) / Double(total) : 0
    }
}
