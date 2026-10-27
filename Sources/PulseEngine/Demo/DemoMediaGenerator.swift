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

    /// Sample projects per genre (#449): the gaming stream, a two-host podcast and a handheld IRL vlog.
    public enum Genre: String, CaseIterable, Sendable {
        case gaming, podcast, irl

        public var displayName: String {
            switch self {
            case .gaming: return "Gaming Stream"
            case .podcast: return "Podcast"
            case .irl: return "IRL Vlog"
            }
        }

        public var projectName: String {
            switch self {
            case .gaming: return "PULSE Sample Stream"
            case .podcast: return "PULSE Sample Podcast"
            case .irl: return "PULSE Sample IRL"
            }
        }

        public var assetName: String {
            switch self {
            case .gaming: return "PULSE Demo Stream"
            case .podcast: return "PULSE Demo Podcast"
            case .irl: return "PULSE Demo Vlog"
            }
        }

        var fileName: String { assetName + ".mov" }

        /// Loud or funny moments.
        var events: [Seconds] {
            switch self {
            case .gaming: return DemoMediaGenerator.events
            case .podcast: return [19, 44, 61]
            case .irl: return [26, 55]
            }
        }

        /// (start, end, speaker, text).
        var script: [(Seconds, Seconds, Int, String)] {
            switch self {
            case .gaming: return DemoMediaGenerator.script.map { ($0.0, $0.1, 0, $0.2) }
            case .podcast: return DemoMediaGenerator.podcastScript
            case .irl: return DemoMediaGenerator.irlScript
            }
        }

        var speakers: [Speaker] {
            switch self {
            case .gaming: return [Speaker(id: 0, name: "Streamer")]
            case .podcast: return [Speaker(id: 0, name: "Host"), Speaker(id: 1, name: "Guest")]
            case .irl: return [Speaker(id: 0, name: "Vlogger")]
            }
        }
    }

    /// Two hosts across a table (start, end, speaker, text).
    static let podcastScript: [(Seconds, Seconds, Int, String)] = [
        (1.0, 4.5, 0, "Welcome back to the show, today we are talking about the worst advice we ever got."),
        (5.0, 8.5, 1, "Oh I have one. Someone told me to never, ever use a tripod."),
        (9.0, 12.0, 0, "Wait, for everything? Like, for interviews?"),
        (12.4, 15.5, 1, "For everything. Handheld only. It was a disaster."),
        (16.2, 19.4, 0, "That is genuinely the funniest thing I have heard all week."),
        (19.6, 22.0, 1, "hahaha I know, I know, I still cringe."),
        (23.0, 27.0, 0, "Okay so the real question is, what advice would you give instead?"),
        (27.8, 32.5, 1, "Honestly? Record more than you think you need, and cut it down later."),
        (33.5, 37.0, 0, "That's basically what this whole app does, which, um, is convenient."),
        (38.0, 42.5, 1, "Right. The hard part was never recording, the hard part was the edit."),
        (43.2, 46.0, 0, "Did you ever ship something you regretted?"),
        (46.4, 49.5, 1, "NO WAY am I answering that on the record. hahaha"),
        (50.5, 55.0, 0, "Fine, fine. Let's do a quick round: tripod, yes or no?"),
        (55.4, 57.5, 1, "Yes. Obviously yes."),
        (58.5, 62.0, 0, "Gimbal? Microphone on a boom? Okay that was a laugh, I'll take it."),
        (63.0, 68.0, 1, "If you take one thing from this episode: the audio matters more than the picture."),
        (69.0, 73.5, 0, "Thanks for listening, we are back next week with a guest you will not believe."),
    ]

    /// A walk through town with a handheld camera (start, end, speaker, text).
    static let irlScript: [(Seconds, Seconds, Int, String)] = [
        (1.0, 4.0, 0, "Okay so we are finally in the city and the plan is simple."),
        (4.6, 8.0, 0, "Find the best coffee, find the best view, and not get lost."),
        (9.0, 12.5, 0, "I have, um, already failed the last one. We are lost."),
        (13.5, 17.0, 0, "But look at this street, this is exactly what I wanted to show you."),
        (18.0, 21.5, 0, "There's a market down there, let's go see what they have."),
        (22.5, 25.5, 0, "Wait, wait, is that a street performer? We have to watch."),
        (26.0, 29.0, 0, "NO WAY, did you see that flip? That was unreal!"),
        (29.4, 31.5, 0, "hahaha the crowd went crazy."),
        (33.0, 37.0, 0, "Okay coffee time. This place has a queue, which is always a good sign."),
        (38.0, 42.0, 0, "So, um, I ordered the thing I can't pronounce. Risky."),
        (43.5, 47.0, 0, "It's actually incredible. Best coffee of the trip, easily."),
        (48.0, 52.0, 0, "Last stop, the viewpoint. It's a bit of a climb, bear with me."),
        (53.5, 57.0, 0, "LOOK AT THAT! That is the whole city. Totally worth it."),
        (57.5, 60.0, 0, "hahaha I'm out of breath, but look at it."),
        (62.0, 66.5, 0, "Thank you for walking around with me today, this was such a good day."),
        (67.5, 72.5, 0, "Tomorrow we take the train up the coast, so make sure you are subscribed for that one."),
    ]

    /// Generates (or reuses) the demo recording for a genre.
    public static func generate(in directory: URL, genre: Genre = .gaming, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Output {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let final = directory.appendingPathComponent(genre.fileName)
        if !FileManager.default.fileExists(atPath: final.path) {
            let videoURL = directory.appendingPathComponent(".demo-video.mov")
            let audioURL = directory.appendingPathComponent(".demo-audio.caf")
            try await writeVideo(to: videoURL, genre: genre) { progress($0 * 0.8) }
            try writeAudio(to: audioURL, genre: genre)
            progress(0.9)
            try await mux(video: videoURL, audio: audioURL, to: final)
            try? FileManager.default.removeItem(at: videoURL)
            try? FileManager.default.removeItem(at: audioURL)
        }
        progress(1)
        return Output(videoURL: final, transcript: transcript(genre: genre), faces: faces(genre: genre))
    }

    public static func transcript(genre: Genre = .gaming) -> Transcript {
        var words: [TranscriptWord] = []
        for (start, end, speaker, text) in genre.script {
            words += TranscriptParser.distribute(text: text, over: TimeRange(start: start, end: end), speaker: speaker)
        }
        return Transcript(language: "en-US", words: words, speakers: genre.speakers, source: .demo)
    }

    public static func faces(genre: Genre = .gaming) -> [FaceSample] {
        switch genre {
        case .gaming:
            return stride(from: 0.0, to: duration, by: 2).map { t in
                let bob = sin(t * 0.9) * 0.006
                let face = NormRect(x: webcamRect.x + webcamRect.width * 0.36 + bob, y: webcamRect.y + webcamRect.height * 0.18,
                                    width: webcamRect.width * 0.28, height: webcamRect.height * 0.46)
                return FaceSample(time: t, boxes: [face])
            }
        case .podcast:
            return stride(from: 0.0, to: duration, by: 2).map { t in
                let bob = sin(t * 0.8) * 0.004
                let host = NormRect(x: 0.24 + bob, y: 0.3, width: 0.11, height: 0.24)
                let guest = NormRect(x: 0.65 - bob, y: 0.31, width: 0.11, height: 0.24)
                return FaceSample(time: t, boxes: [host, guest])
            }
        case .irl:
            return stride(from: 0.0, to: duration, by: 2).map { t in
                let sway = sin(t * 0.5) * 0.03
                let face = NormRect(x: 0.42 + sway, y: 0.28, width: 0.16, height: 0.34)
                return FaceSample(time: t, boxes: [face])
            }
        }
    }

    // MARK: Video

    static func writeVideo(to url: URL, genre: Genre = .gaming, progress: @escaping (Double) -> Void) async throws {
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
                switch genre {
                case .gaming: drawFrame(ctx, time: Double(frame) / Double(fps))
                case .podcast: drawPodcastFrame(ctx, time: Double(frame) / Double(fps))
                case .irl: drawIRLFrame(ctx, time: Double(frame) / Double(fps))
                }
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

    /// Two hosts across a table in a warm studio; the one talking leans in, laughs open both mouths.
    static func drawPodcastFrame(_ ctx: CGContext, time t: Double) {
        let w = CGFloat(width)
        let h = CGFloat(height)
        let laugh = Genre.podcast.events.map { e -> Double in let d = t - e; return d >= 0 && d < 2.5 ? exp(-d * 1.3) : 0 }.max() ?? 0
        let colors = [CGColor(srgbRed: 0.16, green: 0.1, blue: 0.08, alpha: 1), CGColor(srgbRed: 0.32, green: 0.2, blue: 0.14, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])
        }
        // Acoustic panels and a neon sign.
        for i in 0..<6 {
            ctx.setFillColor(CGColor(srgbRed: 0.22, green: 0.14, blue: 0.1, alpha: 1))
            ctx.fill(CGRect(x: CGFloat(i) * w / 6 + 12, y: h * 0.45, width: w / 6 - 24, height: h * 0.5))
        }
        drawText(ctx, "ON AIR", at: CGPoint(x: w * 0.42, y: h * 0.84), size: 40, color: CGColor(srgbRed: 1, green: 0.3, blue: 0.45, alpha: 0.6 + 0.4 * abs(sin(t * 2))))
        // Table.
        ctx.setFillColor(CGColor(srgbRed: 0.28, green: 0.18, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.22))
        let current = Genre.podcast.script.first { t >= $0.0 && t <= $0.1 }?.2
        for (speaker, cx) in [(0, w * 0.3), (1, w * 0.7)] {
            let talking = current == speaker
            let lean = CGFloat(talking ? 10 : 0) * (speaker == 0 ? 1 : -1)
            let bob = CGFloat(sin(t * 0.8 + Double(speaker))) * 4
            let headW = w * 0.11
            let head = CGRect(x: cx - headW / 2 + lean, y: h * 0.45 + bob, width: headW, height: headW * 1.2)
            // Shoulders, head, mic.
            ctx.setFillColor(speaker == 0 ? CGColor(srgbRed: 0.2, green: 0.45, blue: 0.95, alpha: 1) : CGColor(srgbRed: 0.85, green: 0.5, blue: 0.2, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: cx - w * 0.12 + lean, y: h * 0.18, width: w * 0.24, height: h * 0.34))
            ctx.setFillColor(CGColor(srgbRed: speaker == 0 ? 0.93 : 0.6, green: speaker == 0 ? 0.76 : 0.42, blue: speaker == 0 ? 0.62 : 0.3, alpha: 1))
            ctx.fillEllipse(in: head)
            ctx.setFillColor(CGColor(srgbRed: 0.12, green: 0.1, blue: 0.1, alpha: 1))
            let eyeY = head.minY + head.height * 0.58
            ctx.fillEllipse(in: CGRect(x: head.minX + headW * 0.26, y: eyeY, width: headW * 0.12, height: headW * 0.12))
            ctx.fillEllipse(in: CGRect(x: head.minX + headW * 0.62, y: eyeY, width: headW * 0.12, height: headW * 0.12))
            let mouthOpen = CGFloat(laugh > 0.05 ? 0.2 : (talking ? 0.06 + 0.05 * abs(sin(t * 18)) : 0.02))
            ctx.fillEllipse(in: CGRect(x: head.midX - headW * 0.16, y: head.minY + head.height * 0.2, width: headW * 0.32, height: headW * mouthOpen))
            ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 1))
            ctx.fill(CGRect(x: cx + (speaker == 0 ? headW * 0.7 : -headW * 0.9), y: h * 0.22, width: 10, height: h * 0.3))
            ctx.fillEllipse(in: CGRect(x: cx + (speaker == 0 ? headW * 0.55 : -headW * 1.05), y: h * 0.48, width: 40, height: 60))
        }
        if laugh > 0.05 {
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0.9, blue: 0.6, alpha: laugh * 0.18))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        drawText(ctx, "EP. 42 · WORST ADVICE", at: CGPoint(x: 28, y: 20), size: 22, color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.75))
    }

    /// A handheld walk through town: sky, scrolling buildings, a crowd, the vlogger centred and the camera never quite still.
    static func drawIRLFrame(_ ctx: CGContext, time t: Double) {
        let w = CGFloat(width)
        let h = CGFloat(height)
        let intensity = Genre.irl.events.map { e -> Double in let d = t - e; return d >= 0 && d < 3 ? exp(-d * 1.2) : 0 }.max() ?? 0
        let shakeX = CGFloat(sin(t * 7.3) * 6 + sin(t * 23) * 2 * (1 + intensity * 3))
        let shakeY = CGFloat(cos(t * 5.1) * 5 + cos(t * 19) * 2 * (1 + intensity * 3))
        let sky = [CGColor(srgbRed: 0.55, green: 0.78, blue: 0.95, alpha: 1), CGColor(srgbRed: 0.95, green: 0.85, blue: 0.7, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sky, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h * 0.3), options: [.drawsAfterEndLocation, .drawsBeforeStartLocation])
        }
        ctx.saveGState()
        ctx.translateBy(x: shakeX, y: shakeY)
        // Buildings drifting past as we walk.
        for i in 0..<10 {
            let span = Double(w) + 400
            let x = CGFloat(span - (t * 28 + Double(i) * 190).truncatingRemainder(dividingBy: span)) - 200
            let bh = CGFloat(180 + (i * 53) % 220)
            ctx.setFillColor(CGColor(srgbRed: 0.75 - Double(i % 3) * 0.08, green: 0.6 - Double(i % 4) * 0.05, blue: 0.5, alpha: 1))
            ctx.fill(CGRect(x: x, y: h * 0.28, width: 170, height: bh))
            ctx.setFillColor(CGColor(srgbRed: 0.95, green: 0.9, blue: 0.6, alpha: 0.8))
            for r in 0..<3 { for c in 0..<3 { ctx.fill(CGRect(x: x + 20 + CGFloat(c) * 48, y: h * 0.28 + 24 + CGFloat(r) * 56, width: 24, height: 32)) } }
        }
        // Street and crowd.
        ctx.setFillColor(CGColor(srgbRed: 0.45, green: 0.44, blue: 0.46, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.3))
        for k in 0..<7 {
            let px = CGFloat((Double(k) * 160 + t * 20).truncatingRemainder(dividingBy: Double(w)))
            ctx.setFillColor(CGColor(srgbRed: 0.3 + Double(k % 3) * 0.2, green: 0.3, blue: 0.5, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: px, y: h * 0.26, width: 22, height: 44))
        }
        // The vlogger, arm's length from the camera.
        let sway = CGFloat(sin(t * 0.5) * 0.03) * w
        let headW = w * 0.16
        let head = CGRect(x: w * 0.5 - headW / 2 + sway, y: h * 0.38, width: headW, height: headW * 1.15)
        ctx.setFillColor(CGColor(srgbRed: 0.95, green: 0.35, blue: 0.3, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: w * 0.5 - w * 0.2 + sway, y: h * 0.02, width: w * 0.4, height: h * 0.45))
        ctx.setFillColor(CGColor(srgbRed: 0.85, green: 0.65, blue: 0.5, alpha: 1))
        ctx.fillEllipse(in: head)
        ctx.setFillColor(CGColor(srgbRed: 0.12, green: 0.1, blue: 0.1, alpha: 1))
        let eyeY = head.minY + head.height * 0.58
        ctx.fillEllipse(in: CGRect(x: head.minX + headW * 0.26, y: eyeY, width: headW * 0.12, height: headW * 0.12))
        ctx.fillEllipse(in: CGRect(x: head.minX + headW * 0.62, y: eyeY, width: headW * 0.12, height: headW * 0.12))
        let talking = Genre.irl.script.contains { t >= $0.0 && t <= $0.1 }
        let mouthOpen = CGFloat(intensity > 0.05 ? 0.2 : (talking ? 0.06 + 0.05 * abs(sin(t * 18)) : 0.02))
        ctx.fillEllipse(in: CGRect(x: head.midX - headW * 0.16, y: head.minY + head.height * 0.2, width: headW * 0.32, height: headW * mouthOpen))
        ctx.restoreGState()
        if intensity > 0.05 {
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: intensity * 0.3))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        drawText(ctx, "DAY 3 · OLD TOWN", at: CGPoint(x: 28, y: h - 48), size: 24, color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9))
    }

    static func drawText(_ ctx: CGContext, _ text: String, at point: CGPoint, size: CGFloat, color: CGColor) {
        let font = NSFont.systemFont(ofSize: size, weight: .heavy)
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor(cgColor: color) ?? .white])
        let line = CTLineCreateWithAttributedString(attributed)
        ctx.textPosition = point
        CTLineDraw(line, ctx)
    }

    // MARK: Audio

    static func writeAudio(to url: URL, genre: Genre = .gaming) throws {
        let lines = genre.script
        let moments = genre.events
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
                // Room tone: a low hum for the game, a quiet studio for the podcast, traffic and wind outdoors.
                phase += 2 * .pi * (genre == .irl ? 38 : 55) / sampleRate
                var s = genre == .podcast ? 0.004 * sin(phase) : 0.02 * sin(phase) + 0.01 * sin(phase * 3.01)
                if genre == .irl { s += 0.03 * Double.random(in: -1...1, using: &rng) * (0.5 + 0.5 * sin(2 * .pi * 0.3 * time)) }
                // "Speech": band-limited noise with syllable-rate amplitude modulation; the guest's voice sits lower.
                if let line = lines.first(where: { time >= $0.0 && time <= $0.1 }) {
                    let noise = Double.random(in: -1...1, using: &rng)
                    let syllables = 0.5 + 0.5 * sin(2 * .pi * 4.5 * time)
                    let pitch = line.2 == 1 ? 120.0 : 180.0
                    s += 0.12 * noise * syllables * (0.6 + 0.4 * sin(2 * .pi * pitch * time))
                }
                // Explosions and shouting (gaming), laughs (podcast), a cheering crowd (IRL) at the moments.
                for e in moments where time >= e && time < e + 2.5 {
                    let d = time - e
                    let env = exp(-d * 1.2)
                    switch genre {
                    case .gaming: s += 0.6 * env * Double.random(in: -1...1, using: &rng) + 0.3 * env * sin(2 * .pi * 90 * time)
                    case .podcast: s += 0.45 * env * Double.random(in: -1...1, using: &rng) * (0.5 + 0.5 * sin(2 * .pi * 6 * time))
                    case .irl: s += 0.5 * env * Double.random(in: -1...1, using: &rng) * (0.7 + 0.3 * sin(2 * .pi * 3 * time))
                    }
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
