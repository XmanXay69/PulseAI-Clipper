import Foundation

/// What a frame looks like on average (#311): brightness, colourfulness and warmth, from RGBA bytes.
public struct FrameStats: Hashable, Sendable {
    /// Mean luma (0…1).
    public var luma: Double
    /// Mean HSV saturation (0…1).
    public var saturation: Double
    /// Mean (red − blue) (−1…1): positive = warm.
    public var warmth: Double

    public init(luma: Double, saturation: Double, warmth: Double) {
        self.luma = luma
        self.saturation = saturation
        self.warmth = warmth
    }

    /// Averages over an 8-bit RGBA (or BGRA with `blueFirst`) buffer, sampling every `step`-th pixel.
    public static func compute(pixels: [UInt8], width: Int, height: Int, bytesPerRow: Int, blueFirst: Bool = false, step: Int = 2) -> FrameStats? {
        guard width > 0, height > 0, bytesPerRow >= width * 4, pixels.count >= bytesPerRow * height else { return nil }
        var luma = 0.0, sat = 0.0, warm = 0.0
        var n = 0
        let stride = max(step, 1)
        var y = 0
        while y < height {
            var x = 0
            while x < width {
                let i = y * bytesPerRow + x * 4
                let r = Double(pixels[i + (blueFirst ? 2 : 0)]) / 255
                let g = Double(pixels[i + 1]) / 255
                let b = Double(pixels[i + (blueFirst ? 0 : 2)]) / 255
                luma += 0.2126 * r + 0.7152 * g + 0.0722 * b
                let maxC = max(r, g, b)
                sat += maxC > 0 ? (maxC - min(r, g, b)) / maxC : 0
                warm += r - b
                n += 1
                x += stride
            }
            y += stride
        }
        guard n > 0 else { return nil }
        return FrameStats(luma: luma / Double(n), saturation: sat / Double(n), warmth: warm / Double(n))
    }
}

/// Makes one clip look like another (#311): the target's grade is set so its average brightness,
/// colourfulness and warmth land where the reference's do, keeping the reference's own grade as the base.
public enum GradeMatch {
    public static func match(reference: FrameStats, referenceGrade: ColorAdjustments,
                             target: FrameStats, targetGrade: ColorAdjustments) -> ColorAdjustments {
        var out = targetGrade
        let refLuma = max(reference.luma, 0.02), tgtLuma = max(target.luma, 0.02)
        out.exposure = (referenceGrade.exposure + log2(refLuma / tgtLuma)).clamped(-2, 2)
        out.saturation = (referenceGrade.saturation + (reference.saturation - target.saturation) * 2).clamped(-1, 1)
        out.temperature = (referenceGrade.temperature + (reference.warmth - target.warmth) * 3).clamped(-1, 1)
        out.contrast = referenceGrade.contrast
        out.bypass = false
        return out
    }
}
