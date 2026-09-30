import AppKit
import AVFoundation
import CoreText
import Foundation
import PulseCore

/// Procedurally generates the sample project media — a 75-second "stream" with gameplay, a
/// facecam overlay, loud reaction moments and a scripted transcript. Everything is synthesized
/// locally, so the demo ships with no third-party (copyrighted) footage or music.
public enum DemoMediaGenerator {
    public static let duration: Seconds = 75
    public static let width = 1280
    public static let height = 720
    public static let fps: Int32 = 30

    /// Loud "moments" in the demo.
    public static let events: [Seconds] = [22, 51]

    /// Webcam overlay rectangle (normalized, top-left origin).
    public static let webcamRect = NormRect(x: 0.72, y: 0.66, width: 0.26, height: 0.31)

    /// Scripted dialogue (start, end, text).
    public static let script: [(Seconds, Seconds, String)] = [
        (1.0, 4.2, "Alright chat, we are dropping into the final circle right now."),
        (4.8, 8.0, "I have like two heals left so we have to play this smart."),
        (9.0, 12.5, "Okay, um, there's a squad on the ridge, I can see them."),
        (13.2, 16.8, "If they push us here we are in so much trouble, no joke."),
        (17.5, 21.2, "Wait, wait, wait. Watch this. I'm going for it."),
        (21.8, 24.6, "NO WAY! Did you see that? That was insane!"),
        (24.8, 26.4, "hahaha I literally cannot believe that worked."),
        (27.5, 31.0, "Chat is going crazy right now, that was the cleanest shot of my life."),
        (33.0, 36.8, "Okay okay, focus. There's still one team left somewhere."),
        (37.5, 41.2, "So, um, basically we just have to hold this building."),
        (43.0, 46.5, "I hear footsteps. They're right below us, they're right below us."),
        (47.2, 50.4, "Here we go, here we go, one more fight."),
        (50.8, 54.0, "LET'S GO! We actually won! I can't believe it!"),
        (54.3, 56.2, "hahaha that was the craziest ending ever."),
        (58.0, 62.4, "Thank you so much for watching, that one was for the clip channel."),
        (63.5, 67.0, "Honestly, the worst decision of my life turned into the best play."),
        (68.5, 72.5, "Alright, let's queue up again, one more game and then we are done."),
    ]

    public struct Output: Sendable {
        public var videoURL: URL
        public var transcript: Transcript
        public var faces: [FaceSample]
    }

    /// Generates (or reuses) the demo stream.
    public static func generate(in directory: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Output {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let final = directory.appendingPathComponent("PULSE Demo Stream.mov")
        if !FileManager.default.fileExists(atPath: final.path) {
            let videoURL = directory.appendingPathComponent(".demo-video.mov")
            let audioURL = directory.appendingPathComponent(".demo-audio.caf")
            try await writeVideo(to: videoURL) { progress($0 * 0.8) }
            try writeAudio(to: audioURL)
            progress(0.9)
            try await mux(video: videoURL, audio: audioURL, to: final)
            try? FileManager.default.removeItem(at: videoURL)
            try? FileManager.default.removeItem(at: audioURL)
        }
        progress(1)
        return Output(videoURL: final, transcript: transcript(), faces: faces())
    }

    public static func transcript() -> Transcript {
        var words: [TranscriptWord] = []
        for (start, end, text) in script {
            words += TranscriptParser.distribute(text: text, over: TimeRange(start: start, end: end), speaker: 0)
        }
        return Transcript(language: "en-US", words: words, speakers: [Speaker(id: 0, name: "Streamer")], source: .demo)
    }

    public static func faces() -> [FaceSample] {
        stride(from: 0.0, to: duration, by: 2).map { t in
            let bob = sin(t * 0.9) * 0.006
            let face = NormRect(x: webcamRect.x + webcamRect.width * 0.36 + bob, y: webcamRect.y + webcamRect.height * 0.18,
                                width: webcamRect.width * 0.28, height: webcamRect.height * 0.46)
            return FaceSample(time: t, boxes: [face])
        }
    }

    // MARK: Video

    static func writeVideo(to url: URL, progress: @escaping (Double) -> Void) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000, AVVideoMaxKeyFrameIntervalKey: 60],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw EngineError.exportFailed(writer.error?.localizedDescription ?? "demo video") }
        writer.startSession(atSourceTime: .zero)
        let frames = Int(duration * Double(fps))
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            guard let pool = adaptor.pixelBufferPool else { break }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            guard let buffer = pixelBuffer else { break }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer),
               let ctx = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                drawFrame(ctx, time: Double(frame) / Double(fps))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
            if frame % 30 == 0 { progress(Double(frame) / Double(frames)) }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw EngineError.exportFailed(writer.error?.localizedDescription ?? "demo video") }
    }

    static func drawFrame(_ ctx: CGContext, time t: Double) {
        let w = CGFloat(width)
        let h = CGFloat(height)
        // Event intensity (flash + shake) around the big moments.
        let intensity = events.map { e -> Double in
            let d = t - e
            return d >= 0 && d < 3 ? exp(-d * 1.4) : 0
        }.max() ?? 0
        let shakeX = CGFloat(sin(t * 60) * 14 * intensity)
        let shakeY = CGFloat(cos(t * 47) * 10 * intensity)

        // Sky gradient (CG origin is bottom-left).
        let colors = [CGColor(srgbRed: 0.07, green: 0.09, blue: 0.2, alpha: 1), CGColor(srgbRed: 0.35, green: 0.18, blue: 0.45, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h * 0.35), options: [.drawsAfterEndLocation, .drawsBeforeStartLocation])
        }
        ctx.saveGState()
        ctx.translateBy(x: shakeX, y: shakeY)
        // Scrolling terrain blocks = "gameplay".
        for i in 0..<14 {
            let speed = 40.0 + Double(i % 4) * 25
            let span = Double(w) + 300
            let x = CGFloat(span - (t * speed + Double(i) * 170).truncatingRemainder(dividingBy: span)) - 150
            let bh = CGFloat(80 + (i * 37) % 160)
            ctx.setFillColor(CGColor(srgbRed: 0.1 + Double(i % 3) * 0.08, green: 0.35 + Double(i % 5) * 0.06, blue: 0.3, alpha: 1))
            ctx.fill(CGRect(x: x, y: 0, width: 140, height: bh))
        }
        // Player character.
        let px = w * 0.35 + CGFloat(sin(t * 0.7) * 120)
        let py = h * 0.32 + CGFloat(abs(sin(t * 3)) * 40)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0.24, blue: 0.43, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: px - 28, y: py - 28, width: 56, height: 56))
        // Enemies.
        for k in 0..<3 {
            let ex = w * 0.6 + CGFloat(k) * 90 + CGFloat(cos(t * 0.9 + Double(k)) * 60)
            ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.8, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: ex, y: h * 0.3, width: 36, height: 36))
        }
        ctx.restoreGState()

        // HUD.
        drawText(ctx, "KILLS \(Int(t / 6) + (t > 22 ? 3 : 0))   ALIVE \(max(2, 18 - Int(t / 4)))", at: CGPoint(x: 28, y: h - 48), size: 26, color: .white)
        if intensity > 0.05 {
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: intensity * 0.55))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            let label = t < 40 ? "TRIPLE ELIMINATION" : "VICTORY ROYALE"
            drawText(ctx, label, at: CGPoint(x: w * 0.22, y: h * 0.62), size: 64, color: CGColor(srgbRed: 1, green: 0.84, blue: 0.04, alpha: 1))
        }

        // Webcam overlay (bottom-right).
        let cam = CGRect(x: webcamRect.x * w, y: (1 - webcamRect.y - webcamRect.height) * h, width: webcamRect.width * w, height: webcamRect.height * h)
        ctx.setFillColor(CGColor(srgbRed: 0.16, green: 0.17, blue: 0.2, alpha: 1))
        ctx.fill(cam)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.24, blue: 0.43, alpha: 1))
        ctx.setLineWidth(4)
        ctx.stroke(cam)
        // Face: head, eyes, mouth (opens while "talking" and wide on events).
        let bob = CGFloat(sin(t * 0.9) * 0.006) * w
        let headW = cam.width * 0.3
        let headRect = CGRect(x: cam.midX - headW / 2 + bob, y: cam.minY + cam.height * 0.34, width: headW, height: headW * 1.18)
        ctx.setFillColor(CGColor(srgbRed: 0.93, green: 0.76, blue: 0.62, alpha: 1))
        ctx.fillEllipse(in: headRect)
        ctx.setFillColor(CGColor(srgbRed: 0.12, green: 0.1, blue: 0.1, alpha: 1))
        let eyeY = headRect.minY + headRect.height * 0.58
        ctx.fillEllipse(in: CGRect(x: headRect.minX + headW * 0.26, y: eyeY, width: headW * 0.12, height: headW * 0.12))
        ctx.fillEllipse(in: CGRect(x: headRect.minX + headW * 0.62, y: eyeY, width: headW * 0.12, height: headW * 0.12))
        let talking = script.contains { t >= $0.0 && t <= $0.1 }
        let mouthOpen = CGFloat(intensity > 0.05 ? 0.2 : (talking ? 0.06 + 0.05 * abs(sin(t * 18)) : 0.02))
        ctx.fillEllipse(in: CGRect(x: headRect.midX - headW * 0.16, y: headRect.minY + headRect.height * 0.2, width: headW * 0.32, height: headW * mouthOpen))
        // Shoulders.
        ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.45, blue: 0.95, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cam.midX - cam.width * 0.3 + bob, y: cam.minY - cam.height * 0.25, width: cam.width * 0.6, height: cam.height * 0.55))
        drawText(ctx, "● LIVE", at: CGPoint(x: cam.minX + 10, y: cam.maxY - 30), size: 18, color: CGColor(srgbRed: 1, green: 0.3, blue: 0.3, alpha: 1))
    }

    static func drawText(_ ctx: CGContext, _ text: String, at point: CGPoint, size: CGFloat, color: CGColor) {
        let font = NSFont.systemFont(ofSize: size, weight: .heavy)
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor(cgColor: color) ?? .white])
        let line = CTLineCreateWithAttributedString(attributed)
        ctx.textPosition = point
        CTLineDraw(line, ctx)
    }

    // MARK: Audio

    static func writeAudio(to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let sampleRate = 48_000.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let chunk = AVAudioFrameCount(sampleRate)
        var rng = SeededGenerator(seed: 42)
        var phase = 0.0
        var t = 0.0
        while t < duration {
            let frames = AVAudioFrameCount(min(Double(chunk), (duration - t) * sampleRate))
            guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { break }
            buffer.frameLength = frames
            let left = buffer.floatChannelData![0]
            let right = buffer.floatChannelData![1]
            for i in 0..<Int(frames) {
                let time = t + Double(i) / sampleRate
                // Low game ambience.
                phase += 2 * .pi * 55 / sampleRate
                var s = 0.02 * sin(phase) + 0.01 * sin(phase * 3.01)
                // "Speech": band-limited noise with syllable-rate amplitude modulation.
                if script.contains(where: { time >= $0.0 && time <= $0.1 }) {
                    let noise = Double.random(in: -1...1, using: &rng)
                    let syllables = 0.5 + 0.5 * sin(2 * .pi * 4.5 * time)
                    s += 0.12 * noise * syllables * (0.6 + 0.4 * sin(2 * .pi * 180 * time))
                }
                // Explosions / shouting at events.
                for e in events where time >= e && time < e + 2.5 {
                    let d = time - e
                    let env = exp(-d * 1.2)
                    s += 0.6 * env * Double.random(in: -1...1, using: &rng) + 0.3 * env * sin(2 * .pi * 90 * time)
                }
                let v = Float(max(-1, min(1, s)))
                left[i] = v
                right[i] = v
            }
            try file.write(from: buffer)
            t += Double(frames) / sampleRate
        }
    }

    static func mux(video: URL, audio: URL, to output: URL) async throws {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)
        guard let vTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let aTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
              let cv = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let ca = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw EngineError.exportFailed("demo tracks missing")
        }
        let range = CMTimeRange(start: .zero, duration: .seconds(duration))
        try cv.insertTimeRange(range, of: vTrack, at: .zero)
        try ca.insertTimeRange(range, of: aTrack, at: .zero)
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw EngineError.exportFailed("demo export unavailable")
        }
        try? FileManager.default.removeItem(at: output)
        session.outputURL = output
        session.outputFileType = .mov
        await session.export()
        guard session.status == .completed else {
            throw EngineError.exportFailed(session.error?.localizedDescription ?? "demo mux failed")
        }
    }
}
