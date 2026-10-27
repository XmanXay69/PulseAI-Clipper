import AppKit
import AVFoundation
import Foundation
import PulseCore
import VideoToolbox

/// Renders a timeline to a file with AVAssetReader (custom compositor) → AVAssetWriter
/// (VideoToolbox hardware H.264 / HEVC, or ProRes). Supports progress and cancellation.
public final class ExportEngine: @unchecked Sendable {
    public init() {}

    public func export(timeline: Timeline, assets: [UUID: MediaAsset], compounds: [UUID: Timeline] = [:], settings: ExportSettings, to destination: URL,
                       range: TimeRange? = nil,
                       progress: @escaping @Sendable (Double) -> Void, isCancelled: @escaping @Sendable () -> Bool = { false }) async throws {
        let size = settings.outputSize(for: timeline.canvas)
        let renderSize = CGSize(width: size.width, height: size.height)
        var buildOptions = CompositionBuilder.Options(renderSize: renderSize, useProxies: false, includeCaptions: settings.burnInCaptions)
        buildOptions.compounds = compounds
        buildOptions.watermark = settings.watermark
        buildOptions.transparentBackground = settings.transparentBackground && settings.codec.supportsAlpha
        let built = try await CompositionBuilder.build(timeline: timeline, assets: assets, options: buildOptions)
        if !built.missingAssetIDs.isEmpty {
            let names = built.missingAssetIDs.compactMap { assets[$0]?.name }.joined(separator: ", ")
            throw EngineError.exportFailed("media is offline (\(names)). Reconnect the files and try again.")
        }
        // In → out: only that stretch (clamped to the composition).
        let exportStart = range.map { max(0, min($0.start, built.duration)) } ?? 0
        let duration = range.map { max(0.1, min($0.end, built.duration) - exportStart) } ?? built.duration
        let fps = settings.frameRate ?? timeline.canvas.frameRate
        let audioOnly = settings.audioOnly
        let videoBitrate = settings.videoBitrate(for: duration)
        let estimatedBytes = Int64(Double((audioOnly ? 0 : videoBitrate) + settings.audioBitrate) * duration / 8 * 1.15)
        try DiskSpace.ensure(estimatedBytes, at: destination.deletingLastPathComponent())

        let videoComposition = built.videoComposition.mutableCopy() as! AVMutableVideoComposition
        videoComposition.frameDuration = CMTime(value: 1000, timescale: CMTimeScale(max(1, fps) * 1000))
        videoComposition.renderSize = renderSize

        let reader = try AVAssetReader(asset: built.composition)
        reader.timeRange = CMTimeRange(start: .seconds(exportStart), duration: .seconds(duration))
        let videoTracks = try await built.composition.loadTracks(withMediaType: .video)
        let audioTracks = try await built.composition.loadTracks(withMediaType: .audio)

        var videoOutput: AVAssetReaderVideoCompositionOutput?
        if !audioOnly {
            let output = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ])
            output.videoComposition = videoComposition
            output.alwaysCopiesSampleData = false
            // Two-pass (#343): the encoder asks to read stretches again, so the output must seek.
            if settings.runsTwoPasses { output.supportsRandomAccess = true }
            guard reader.canAdd(output) else { throw EngineError.exportFailed("couldn't read the composed video") }
            reader.add(output)
            videoOutput = output
        }

        var audioOutput: AVAssetReaderAudioMixOutput?
        if !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false,
            ])
            output.audioMix = built.audioMix
            output.audioTimePitchAlgorithm = .spectral
            if reader.canAdd(output) {
                reader.add(output)
                audioOutput = output
            }
        }

        let temp = destination.deletingLastPathComponent().appendingPathComponent(".pulse-export-\(UUID().uuidString).\(settings.outputExtension)")
        try? FileManager.default.removeItem(at: temp)
        let writer = try AVAssetWriter(outputURL: temp, fileType: audioOnly ? .m4a : (settings.codec.isProRes ? .mov : .mp4))
        writer.shouldOptimizeForNetworkUse = true
        writer.metadata = Self.metadata(for: timeline)

        var videoSettings: [String: Any] = [
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
        ]
        switch settings.codec {
        case .h264:
            videoSettings[AVVideoCodecKey] = AVVideoCodecType.h264
            videoSettings[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: videoBitrate,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: Int(fps * 2),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ] as [String: Any]
        case .hevc:
            videoSettings[AVVideoCodecKey] = AVVideoCodecType.hevc
            videoSettings[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: videoBitrate,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: Int(fps * 2),
            ] as [String: Any]
        case .hevc10:
            // Main 10 profile (#348): VideoToolbox takes the 8-bit frames and writes a 10-bit stream.
            videoSettings[AVVideoCodecKey] = AVVideoCodecType.hevc
            videoSettings[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: videoBitrate,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: Int(fps * 2),
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String,
            ] as [String: Any]
        case .proRes422:
            videoSettings[AVVideoCodecKey] = AVVideoCodecType.proRes422
        case .proRes4444:
            videoSettings[AVVideoCodecKey] = AVVideoCodecType.proRes4444
        }
        if settings.useHardwareEncoding && !settings.codec.isProRes {
            videoSettings[AVVideoEncoderSpecificationKey] = [
                kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true,
            ]
        }
        var videoInput: AVAssetWriterInput?
        if !audioOnly {
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            input.expectsMediaDataInRealTime = false
            if settings.runsTwoPasses { input.performsMultiPassEncodingIfSupported = true }
            guard writer.canAdd(input) else { throw EngineError.exportFailed("the encoder rejected these settings (\(settings.codec.displayName) \(size.width)×\(size.height))") }
            writer.add(input)
            videoInput = input
        }

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: settings.audioBitrate,
            ])
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }
        if audioOnly && audioInput == nil {
            throw EngineError.exportFailed("this timeline has no audio to export")
        }

        guard reader.startReading() else {
            throw EngineError.exportFailed(reader.error?.localizedDescription ?? "couldn't start reading")
        }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw EngineError.exportFailed(writer.error?.localizedDescription ?? "couldn't start writing")
        }
        writer.startSession(atSourceTime: .seconds(exportStart))

        let pump = ExportPump(reader: reader, writer: writer, start: exportStart, duration: duration, progress: progress, isCancelled: isCancelled)
        pump.multiPass = settings.runsTwoPasses
        await pump.run(videoOutput: videoOutput, videoInput: videoInput, audioOutput: audioOutput, audioInput: audioInput)
        if pump.multiPass { PulseLog.info("Two-pass export: \(pump.passes) pass\(pump.passes == 1 ? "" : "es")") }

        if pump.cancelled {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: temp)
            throw EngineError.cancelled
        }
        if reader.status == .failed {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: temp)
            throw EngineError.exportFailed(reader.error?.localizedDescription ?? "reading the composition failed")
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: temp)
            throw EngineError.exportFailed(writer.error?.localizedDescription ?? "the encoder failed")
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)

        // A representative frame as a PNG next to the video (#337): the payoff marker when there is one.
        if settings.exportThumbnail, !audioOnly {
            let at = Self.thumbnailTime(for: timeline, exportStart: exportStart, duration: duration)
            await Self.writeThumbnail(of: destination, at: at, to: destination.deletingPathExtension().appendingPathExtension("png"))
        }

        if settings.exportSRT, let captions = timeline.captions {
            let srt = CaptionLayoutEngine.srt(track: captions, timeline: timeline)
            try? srt.write(to: destination.deletingPathExtension().appendingPathExtension("srt"), atomically: true, encoding: .utf8)
        }
        progress(1)
    }
}

/// Moves samples from reader outputs to writer inputs on background queues.
extension ExportEngine {
    /// Title, artist, comment and the app in the file's own metadata (#354).
    static func metadata(for timeline: Timeline) -> [AVMetadataItem] {
        func item(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let m = AVMutableMetadataItem()
            m.identifier = identifier
            m.value = value as NSString
            m.extendedLanguageTag = "und"
            return m
        }
        var items = [item(.commonIdentifierTitle, timeline.copy?.titles.first ?? timeline.name),
                     item(.commonIdentifierSoftware, "PULSE"),
                     item(.quickTimeMetadataSoftware, "PULSE")]
        if let hashtags = timeline.copy?.hashtags, !hashtags.isEmpty { items.append(item(.commonIdentifierDescription, hashtags.joined(separator: " "))) }
        return items
    }

    /// The frame worth a thumbnail: the "Payoff" or "Hook" marker inside the export, else a third of the way in.
    static func thumbnailTime(for timeline: Timeline, exportStart: Seconds, duration: Seconds) -> Seconds {
        // The cover frame you picked (#70) wins when it's inside the export.
        if let cover = timeline.coverTime, cover >= exportStart, cover < exportStart + duration { return cover - exportStart }
        let inside = timeline.markers.filter { $0.time >= exportStart && $0.time < exportStart + duration }
        if let payoff = inside.first(where: { $0.name == "Payoff" || $0.name == "Hook" }) { return payoff.time - exportStart }
        return duration * 0.35
    }

    static func writeThumbnail(of video: URL, at time: Seconds, to destination: URL) async {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        guard let cg = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image,
              let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return }
        try? data.write(to: destination)
    }
}

final class ExportPump: @unchecked Sendable {
    let reader: AVAssetReader
    let writer: AVAssetWriter
    let start: Seconds
    let duration: Seconds
    let progress: @Sendable (Double) -> Void
    let isCancelled: @Sendable () -> Bool
    private let lock = NSLock()
    private var _cancelled = false
    /// Two-pass encoding (#343): the video input re-reads the stretches the encoder asks for.
    var multiPass = false
    private var _passes = 0
    var passes: Int {
        lock.lock(); defer { lock.unlock() }
        return _passes
    }
    var cancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _cancelled
    }

    init(reader: AVAssetReader, writer: AVAssetWriter, start: Seconds = 0, duration: Seconds, progress: @escaping @Sendable (Double) -> Void, isCancelled: @escaping @Sendable () -> Bool) {
        self.reader = reader
        self.writer = writer
        self.start = start
        self.duration = duration
        self.progress = progress
        self.isCancelled = isCancelled
    }

    func markCancelled() {
        lock.lock()
        _cancelled = true
        lock.unlock()
    }

    func run(videoOutput: AVAssetReaderOutput?, videoInput: AVAssetWriterInput?, audioOutput: AVAssetReaderOutput?, audioInput: AVAssetWriterInput?) async {
        await withTaskGroup(of: Void.self) { group in
            if let videoOutput, let videoInput {
                if self.multiPass, videoInput.canPerformMultiplePasses {
                    group.addTask { await self.transferMultiPass(from: videoOutput, to: videoInput) }
                } else {
                    group.addTask { await self.transfer(from: videoOutput, to: videoInput, reportsProgress: true, label: "video") }
                }
            }
            if let audioOutput, let audioInput {
                group.addTask { await self.transfer(from: audioOutput, to: audioInput, reportsProgress: videoOutput == nil, label: "audio") }
            }
        }
    }

    private final class TransferState: @unchecked Sendable {
        var finished = false
        var lastReported = -1.0
        var pass = 0
        var lastDescription: AVAssetWriterInputPassDescription?
    }

    /// Two-pass encoding (#343), the way AVFoundation's multi-pass API is meant to be driven: every pass begins
    /// with a pass description naming the stretches to read; the reader output is reset to them and media is
    /// requested for that pass alone. When the pass runs dry the input is told, and the next description (or
    /// nil, meaning done) arrives on the same queue. Progress runs 0…½ in pass 1 and ½…1 after.
    private func transferMultiPass(from output: AVAssetReaderOutput, to input: AVAssetWriterInput) async {
        let queue = DispatchQueue(label: "app.pulse.export.video")
        let state = TransferState()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            func finish() {
                guard !state.finished else { return }
                state.finished = true
                output.markConfigurationAsFinal()
                input.markAsFinished()
                continuation.resume()
            }
            func beginPass(_ description: AVAssetWriterInputPassDescription) {
                // The same description can be announced twice (once on registration, once on change): one request per pass.
                guard state.lastDescription !== description else { return }
                state.lastDescription = description
                state.pass += 1
                self.lock.lock(); self._passes = state.pass; self.lock.unlock()
                state.lastReported = -1
                // The first pass reads the reader's own range; a reset is only legal once the previous pass has
                // been read to its end, which is exactly when every later description arrives.
                if state.pass > 1 { output.reset(forReadingTimeRanges: description.sourceTimeRanges) }
                input.requestMediaDataWhenReady(on: queue) {
                    guard !state.finished else { return }
                    while input.isReadyForMoreMediaData {
                        if self.isCancelled() || self.cancelled {
                            self.markCancelled()
                            finish()
                            return
                        }
                        guard let sample = output.copyNextSampleBuffer() else {
                            // This pass is done; the next pass description decides whether another follows.
                            input.markCurrentPassAsFinished()
                            return
                        }
                        let t = CMSampleBufferGetPresentationTimeStamp(sample).secondsValue
                        let within = self.duration > 0 ? min(max(0, t - self.start) / self.duration, 0.999) : 0
                        let p = state.pass <= 1 ? within * 0.5 : 0.5 + within * 0.5
                        if p - state.lastReported >= 0.005 {
                            state.lastReported = p
                            self.progress(p)
                        }
                        if !input.append(sample) {
                            finish()
                            return
                        }
                    }
                }
            }
            input.respondToEachPassDescription(on: queue) {
                guard !state.finished else { return }
                if let description = input.currentPassDescription {
                    beginPass(description)
                } else {
                    finish()
                }
            }
            // Writing has already started, so the first pass may be waiting before the block above was registered.
            queue.async {
                guard !state.finished, state.pass == 0 else { return }
                if let description = input.currentPassDescription { beginPass(description) }
            }
        }
    }

    private func transfer(from output: AVAssetReaderOutput, to input: AVAssetWriterInput, reportsProgress: Bool, label: String) async {
        let queue = DispatchQueue(label: "app.pulse.export.\(label)")
        let state = TransferState()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: queue) {
                guard !state.finished else { return }
                while input.isReadyForMoreMediaData {
                    if self.isCancelled() || self.cancelled {
                        self.markCancelled()
                        state.finished = true
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                    guard let sample = output.copyNextSampleBuffer() else {
                        state.finished = true
                        // A seekable output (two-pass asked for, encoder declined) still has to be told reading is over.
                        if output.supportsRandomAccess { output.markConfigurationAsFinal() }
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                    if reportsProgress {
                        let t = CMSampleBufferGetPresentationTimeStamp(sample).secondsValue
                        let p = self.duration > 0 ? min(max(0, t - self.start) / self.duration, 0.999) : 0
                        if p - state.lastReported >= 0.005 {
                            state.lastReported = p
                            self.progress(p)
                        }
                    }
                    if !input.append(sample) {
                        state.finished = true
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }
    }
}
