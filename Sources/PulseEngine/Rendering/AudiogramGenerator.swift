import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import PulseCore

/// Draws a waveform video for an audio-only recording (#9): bars that move with the voice, the recording's
/// name and a progress line, written as an H.264 movie the length of the recording so the long-form edit
/// can cut it like any camera.
public enum AudiogramGenerator {
    public struct Style: Sendable {
        public var width = 1280
        public var height = 720
        public var fps: Int32 = 24
        public var bars = 64
        public var span: Seconds = 4
        /// Accent RGB (0…1) for the bars.
        public var accent: (Double, Double, Double) = (0.98, 0.43, 0.27)
        public init() {}
    }

    /// Renders `duration` seconds to `url`. `peaks` is the whole file's envelope at `perSecond` samples a second
    /// (what `WaveformService` gives). Throws on an encoder failure; `isCancelled` stops early and removes the file.
    public static func render(peaks: [Float], perSecond: Double, duration: Seconds, title: String, to url: URL, style: Style = Style(),
                              progress: @escaping @Sendable (Double) -> Void = { _ in },
                              isCancelled: @escaping @Sendable () -> Bool = { false }) async throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        let width = style.width, height = style.height, fps = style.fps
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000, AVVideoMaxKeyFrameIntervalKey: Int(fps) * 2],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw EngineError.exportFailed(writer.error?.localizedDescription ?? "waveform video") }
        writer.startSession(atSourceTime: .zero)
        let frames = max(1, Int((duration * Double(fps)).rounded(.up)))
        let backdrop = makeBackdrop(width: width, height: height, accent: style.accent)
        let titleLine = makeTitle(title, width: width)
        var smoothed = [Float](repeating: 0, count: style.bars)
        for frame in 0..<frames {
            if isCancelled() {
                input.markAsFinished()
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: url)
                return
            }
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            guard let pool = adaptor.pixelBufferPool else { break }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            guard let buffer = pixelBuffer else { break }
            let t = Double(frame) / Double(fps)
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer),
               let ctx = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                ctx.draw(backdrop, in: CGRect(x: 0, y: 0, width: width, height: height))
                let raw = AudiogramLayout.bars(peaks: peaks, perSecond: perSecond, at: t, count: style.bars, span: style.span)
                for i in 0..<smoothed.count where i < raw.count {
                    let target = AudiogramLayout.eased(raw[i])
                    // Rise fast, fall slowly, like a meter.
                    smoothed[i] = target > smoothed[i] ? target : smoothed[i] * 0.78 + target * 0.22
                }
                drawBars(ctx, heights: smoothed, width: width, height: height, accent: style.accent)
                drawProgress(ctx, fraction: duration > 0 ? t / duration : 0, width: width, height: height, accent: style.accent)
                if let titleLine {
                    ctx.textPosition = CGPoint(x: Double(width) * 0.06, y: Double(height) * 0.82)
                    CTLineDraw(titleLine, ctx)
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps)) else {
                input.markAsFinished()
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: url)
                throw EngineError.exportFailed(writer.error?.localizedDescription ?? "the waveform video's encoder refused frame \(frame + 1)")
            }
            if frame % 48 == 0 { progress(Double(frame) / Double(frames)) }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw EngineError.exportFailed(writer.error?.localizedDescription ?? "waveform video") }
        progress(1)
    }

    // MARK: Drawing

    static func makeBackdrop(width: Int, height: Int, accent: (Double, Double, Double)) -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        let colors = [CGColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1), CGColor(red: 0.03, green: 0.03, blue: 0.05, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(height)), end: CGPoint(x: 0, y: 0), options: [])
        }
        // A soft accent glow behind the bars.
        let glow = [CGColor(red: accent.0, green: accent.1, blue: accent.2, alpha: 0.22), CGColor(red: accent.0, green: accent.1, blue: accent.2, alpha: 0)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: glow, locations: [0, 1]) {
            ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) * 0.45), startRadius: 0,
                                   endCenter: CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) * 0.45), endRadius: CGFloat(width) * 0.45, options: [])
        }
        return ctx.makeImage()!
    }

    static func makeTitle(_ title: String, width: Int) -> CTLine? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let font = NSFont.systemFont(ofSize: CGFloat(width) * 0.032, weight: .bold)
        let attributed = NSAttributedString(string: trimmed, attributes: [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.92)])
        return CTLineCreateWithAttributedString(attributed)
    }

    static func drawBars(_ ctx: CGContext, heights: [Float], width: Int, height: Int, accent: (Double, Double, Double)) {
        guard !heights.isEmpty else { return }
        let w = Double(width), h = Double(height)
        let span = w * 0.88
        let left = (w - span) / 2
        let slot = span / Double(heights.count)
        let barWidth = slot * 0.62
        let maxHeight = h * 0.5
        let baseline = h * 0.45
        let centre = AudiogramLayout.centreIndex(count: heights.count)
        for (i, value) in heights.enumerated() {
            let distance = abs(i - centre)
            let fade = max(0.25, 1 - Double(distance) / Double(heights.count) * 1.6)
            let alpha = i <= centre ? fade : fade * 0.55
            let barHeight = max(slot * 0.3, Double(value) * maxHeight * (i == centre ? 1.08 : 1))
            let rect = CGRect(x: left + Double(i) * slot + (slot - barWidth) / 2, y: baseline - barHeight / 2, width: barWidth, height: barHeight)
            let path = CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
            ctx.setFillColor(CGColor(red: accent.0, green: accent.1, blue: accent.2, alpha: alpha))
            ctx.addPath(path)
            ctx.fillPath()
        }
    }

    static func drawProgress(_ ctx: CGContext, fraction: Double, width: Int, height: Int, accent: (Double, Double, Double)) {
        let w = Double(width), h = Double(height)
        let y = h * 0.12
        let left = w * 0.06, right = w * 0.94
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.18))
        ctx.setLineWidth(max(2, h * 0.004))
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: left, y: y))
        ctx.addLine(to: CGPoint(x: right, y: y))
        ctx.strokePath()
        ctx.setStrokeColor(CGColor(red: accent.0, green: accent.1, blue: accent.2, alpha: 0.9))
        ctx.move(to: CGPoint(x: left, y: y))
        ctx.addLine(to: CGPoint(x: left + (right - left) * min(1, max(0, fraction)), y: y))
        ctx.strokePath()
    }
}
