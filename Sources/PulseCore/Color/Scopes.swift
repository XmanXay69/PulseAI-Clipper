import Foundation

/// Waveform and vectorscope data for one frame (#310), computed from RGBA bytes so the viewer can draw them.
public struct ScopeData: Hashable, Sendable {
    /// `columns` × `bins`: how much of each column's pixels fall in each luma bin (0 = black at index 0), each
    /// column normalized to its peak.
    public var waveform: [[Float]]
    public var columns: Int
    public var bins: Int
    /// `grid` × `grid` chroma histogram (Cb across, Cr down), normalized to its peak.
    public var vectorscope: [Float]
    public var grid: Int
    /// Share of pixels at or near clipping (luma ≥ 0.98) and crushed (luma ≤ 0.02).
    public var clippedShare: Double
    public var crushedShare: Double

    public static func compute(pixels: [UInt8], width: Int, height: Int, bytesPerRow: Int, blueFirst: Bool = false,
                               columns: Int = 64, bins: Int = 32, grid: Int = 24) -> ScopeData? {
        guard width > 0, height > 0, bytesPerRow >= width * 4, pixels.count >= bytesPerRow * height, columns > 0, bins > 1, grid > 1 else { return nil }
        var wave = [[Float]](repeating: [Float](repeating: 0, count: bins), count: columns)
        var vector = [Float](repeating: 0, count: grid * grid)
        var clipped = 0, crushed = 0, total = 0
        let stepX = max(1, width / 160), stepY = max(1, height / 90)
        var y = 0
        while y < height {
            var x = 0
            while x < width {
                let i = y * bytesPerRow + x * 4
                let r = Double(pixels[i + (blueFirst ? 2 : 0)]) / 255
                let g = Double(pixels[i + 1]) / 255
                let b = Double(pixels[i + (blueFirst ? 0 : 2)]) / 255
                let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                let column = min(columns - 1, x * columns / width)
                let bin = min(bins - 1, Int(luma * Double(bins)))
                wave[column][bin] += 1
                // BT.709 chroma, centred: Cb horizontal, Cr vertical.
                let cb = (b - luma) / 1.8556
                let cr = (r - luma) / 1.5748
                let gx = min(grid - 1, max(0, Int((cb + 0.5) * Double(grid))))
                let gy = min(grid - 1, max(0, Int((0.5 - cr) * Double(grid))))
                vector[gy * grid + gx] += 1
                if luma >= 0.98 { clipped += 1 } else if luma <= 0.02 { crushed += 1 }
                total += 1
                x += stepX
            }
            y += stepY
        }
        guard total > 0 else { return nil }
        for c in 0..<columns {
            let peak = wave[c].max() ?? 0
            if peak > 0 { for b in 0..<bins { wave[c][b] /= peak } }
        }
        let vPeak = vector.max() ?? 0
        if vPeak > 0 { for i in vector.indices { vector[i] = Float(sqrt(Double(vector[i] / vPeak))) } }
        return ScopeData(waveform: wave, columns: columns, bins: bins, vectorscope: vector, grid: grid,
                         clippedShare: Double(clipped) / Double(total), crushedShare: Double(crushed) / Double(total))
    }
}
