import AVFoundation
import Foundation
import PulseCore

/// Writes a reversed copy of a stretch of a video file (#172). Frames are read a second at a time from the
/// end backwards and written mirrored in time, so memory stays at about a second of NV12 frames whatever the
/// length. Audio is left out: a reversed clip is muted on the timeline.
public enum ReverseRenderer {
    /// Longer stretches are split first; this keeps renders to a few seconds of work.
    public static let maxDuration: Seconds = 60

    public static func reverse(url: URL, range: TimeRange, to destination: URL,
                               progress: (@Sendable (Double) -> Void)? = nil) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw EngineError.exportFailed("the file has no video track")
        }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let nominalFPS = try await track.load(.nominalFrameRate)
        let width = max(2, Int(naturalSize.width.rounded()) / 2 * 2)
        let height = max(2, Int(naturalSize.height.rounded()) / 2 * 2)
        let total = max(range.duration, 0.1)

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        let bitrate = min(60_000_000, max(4_000_000, width * height * 6))
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate, AVVideoExpectedSourceFrameRateKey: Int(max(24, nominalFPS))],
        ])
        input.expectsMediaDataInRealTime = false
        input.transform = transform
        let pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { throw EngineError.exportFailed("couldn't set up the encoder") }
        writer.add(input)
        guard writer.startWriting() else { throw EngineError.exportFailed(writer.error?.localizedDescription ?? "couldn't start writing") }
        writer.startSession(atSourceTime: .zero)

        let end = CMTime.seconds(range.end)
        var lastWritten = CMTime(value: -1, timescale: 600)
        var chunkEnd = range.end
        let chunk: Seconds = 1
        while chunkEnd > range.start + 0.0005 {
            try Task.checkCancellation()
            let chunkStart = max(range.start, chunkEnd - chunk)
            let reader = try AVAssetReader(asset: asset)
            reader.timeRange = CMTimeRange(start: .seconds(chunkStart), end: .seconds(chunkEnd))
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat])
            output.alwaysCopiesSampleData = true
            guard reader.canAdd(output) else { throw EngineError.exportFailed("couldn't read the video") }
            reader.add(output)
            guard reader.startReading() else { throw EngineError.exportFailed(reader.error?.localizedDescription ?? "couldn't read the video") }
            var frames: [(buffer: CVPixelBuffer, time: CMTime)] = []
            while let sample = output.copyNextSampleBuffer() {
                if let buffer = CMSampleBufferGetImageBuffer(sample) {
                    frames.append((buffer, CMSampleBufferGetPresentationTimeStamp(sample)))
                }
            }
            reader.cancelReading()
            for frame in frames.reversed() {
                // Mirror in time: the source's last frame becomes the output's first.
                let outTime = CMTimeSubtract(end, frame.time)
                guard CMTimeCompare(outTime, lastWritten) > 0, outTime >= .zero else { continue }
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 4_000_000)
                    try Task.checkCancellation()
                }
                if !adaptor.append(frame.buffer, withPresentationTime: outTime) {
                    throw EngineError.exportFailed(writer.error?.localizedDescription ?? "the encoder refused a frame")
                }
                lastWritten = outTime
            }
            frames.removeAll(keepingCapacity: false)
            chunkEnd = chunkStart
            progress?(min(1, (range.end - chunkEnd) / total))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            throw EngineError.exportFailed(writer.error?.localizedDescription ?? "the reversed file couldn't be finished")
        }
    }
}
