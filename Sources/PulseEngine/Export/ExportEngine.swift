import AVFoundation
import Foundation
import PulseCore
import VideoToolbox

/// Renders a timeline to a file with AVAssetReader (custom compositor) → AVAssetWriter
/// (VideoToolbox hardware H.264 / HEVC, or ProRes). Supports progress and cancellation.
public final class ExportEngine: @unchecked Sendable {
    public init() {}

    public func export(timeline: Timeline, assets: [UUID: MediaAsset], settings: ExportSettings, to destination: URL,
                       progress: @escaping @Sendable (Double) -> Void, isCancelled: @escaping @Sendable () -> Bool = { false }) async throws {
        let size = settings.outputSize(for: timeline.canvas)
        let renderSize = CGSize(width: size.width, height: size.height)
        let built = try await CompositionBuilder.build(timeline: timeline, assets: assets,
                                                       options: .init(renderSize: renderSize, useProxies: false, includeCaptions: settings.burnInCaptions))
        if !built.missingAssetIDs.isEmpty {
            let names = built.missingAssetIDs.compactMap { assets[$0]?.name }.joined(separator: ", ")
            throw EngineError.exportFailed("media is offline (\(names)). Reconnect the files and try again.")
        }
        let duration = built.duration
        let fps = settings.frameRate ?? timeline.canvas.frameRate
        let estimatedBytes = Int64(Double(settings.effectiveVideoBitrate + settings.audioBitrate) * duration / 8 * 1.15)
        try DiskSpace.ensure(estimatedBytes, at: destination.deletingLastPathComponent())

        let videoComposition = built.videoComposition.mutableCopy() as! AVMutableVideoComposition
        videoComposition.frameDuration = CMTime(value: 1000, timescale: CMTimeScale(max(1, fps) * 1000))
        videoComposition.renderSize = renderSize

        let reader = try AVAssetReader(asset: built.composition)
        reader.timeRange = CMTimeRange(start: .zero, duration: .seconds(duration))
        let videoTracks = try await built.composition.loadTracks(withMediaType: .video)
        let audioTracks = try await built.composition.loadTracks(withMediaType: .audio)

        let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        videoOutput.videoComposition = videoComposition
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw EngineError.exportFailed("couldn't read the composed video") }
        reader.add(videoOutput)

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

        let temp = destination.deletingLastPathComponent().appendingPathComponent(".pulse-export-\(UUID().uuidString).\(settings.codec.fileExtension)")
        try? FileManager.default.removeItem(at: temp)
        let writer = try AVAssetWriter(outputURL: temp, fileType: settings.codec == .proRes422 ? .mov : .mp4)
        writer.shouldOptimizeForNetworkUse = true

        var videoSettings: [String: Any] = [
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
        ]
        switch settings.codec {
        case .h264:
            videoSettings[AVVideoCodecKey] = AVVideoCodecType.h264
            videoSettings[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: settings.effectiveVideoBitrate,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: Int(fps * 2),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ] as [String: Any]
        case .hevc:
            videoSettings[AVVideoCodecKey] = AVVideoCodecType.hevc
            videoSettings[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: settings.effectiveVideoBitrate,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: Int(fps * 2),
            ] as [String: Any]
        case .proRes422:
            videoSettings[AVVideoCodecKey] = AVVideoCodecType.proRes422
        }
        if settings.useHardwareEncoding && settings.codec != .proRes422 {
            videoSettings[AVVideoEncoderSpecificationKey] = [
                kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true,
            ]
        }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw EngineError.exportFailed("the encoder rejected these settings (\(settings.codec.displayName) \(size.width)×\(size.height))") }
        writer.add(videoInput)

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

        guard reader.startReading() else {
            throw EngineError.exportFailed(reader.error?.localizedDescription ?? "couldn't start reading")
        }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw EngineError.exportFailed(writer.error?.localizedDescription ?? "couldn't start writing")
        }
        writer.startSession(atSourceTime: .zero)

        let pump = ExportPump(reader: reader, writer: writer, duration: duration, progress: progress, isCancelled: isCancelled)
        await pump.run(videoOutput: videoOutput, videoInput: videoInput, audioOutput: audioOutput, audioInput: audioInput)

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

        if settings.exportSRT, let captions = timeline.captions {
            let srt = CaptionLayoutEngine.srt(track: captions, timeline: timeline)
            try? srt.write(to: destination.deletingPathExtension().appendingPathExtension("srt"), atomically: true, encoding: .utf8)
        }
        progress(1)
    }
}

/// Moves samples from reader outputs to writer inputs on background queues.
final class ExportPump: @unchecked Sendable {
    let reader: AVAssetReader
    let writer: AVAssetWriter
    let duration: Seconds
    let progress: @Sendable (Double) -> Void
    let isCancelled: @Sendable () -> Bool
    private let lock = NSLock()
    private var _cancelled = false
    var cancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _cancelled
    }

    init(reader: AVAssetReader, writer: AVAssetWriter, duration: Seconds, progress: @escaping @Sendable (Double) -> Void, isCancelled: @escaping @Sendable () -> Bool) {
        self.reader = reader
        self.writer = writer
        self.duration = duration
        self.progress = progress
        self.isCancelled = isCancelled
    }

    func markCancelled() {
        lock.lock()
        _cancelled = true
        lock.unlock()
    }

    func run(videoOutput: AVAssetReaderOutput, videoInput: AVAssetWriterInput, audioOutput: AVAssetReaderOutput?, audioInput: AVAssetWriterInput?) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.transfer(from: videoOutput, to: videoInput, reportsProgress: true, label: "video") }
            if let audioOutput, let audioInput {
                group.addTask { await self.transfer(from: audioOutput, to: audioInput, reportsProgress: false, label: "audio") }
            }
        }
    }

    private final class TransferState: @unchecked Sendable {
        var finished = false
        var lastReported = -1.0
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
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                    if reportsProgress {
                        let t = CMSampleBufferGetPresentationTimeStamp(sample).secondsValue
                        let p = self.duration > 0 ? min(t / self.duration, 0.999) : 0
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
