import AVFoundation
import Foundation
import PulseCore

/// One stretch transcribed again (#42) after a name was fixed or vocabulary added: the stretch is cut to a
/// 16 kHz WAV, run through the chosen engine, and the words come back in source time.
public enum Retranscriber {
    public static func transcribe(asset: MediaAsset, range: TimeRange, settings: AISettings, voiceSource: URL? = nil) async throws -> [TranscriptWord] {
        let source = voiceSource ?? MediaAccess.resolve(asset)
        let wav = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-retranscribe-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wav) }
        try await writeWAV(of: source, range: range, to: wav)
        let engines = TranscriptionEngineFactory.candidates(settings: settings)
        guard !engines.isEmpty else { throw EngineError.transcriptionUnavailable("No transcription engine is available") }
        var lastError: Error?
        for engine in engines {
            do {
                let heard = try await engine.transcribe(audioURL: wav, language: settings.transcriptionLanguage) { _ in }
                PulseLog.info("Re-transcribed \(Timecode.duration(range.duration)) with \(engine.displayName): \(heard.words.count) words")
                return heard.words.map { w in
                    var moved = w
                    moved.start += range.start
                    moved.end += range.start
                    return moved
                }
            } catch {
                lastError = error
            }
        }
        throw lastError ?? EngineError.transcriptionUnavailable("Transcription failed")
    }

    /// 16 kHz mono PCM of `range`, the format every engine takes.
    static func writeWAV(of url: URL, range: TimeRange, to target: URL) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw EngineError.noAudioTrack(url) }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: max(0, range.start), preferredTimescale: 600),
                                       duration: CMTime(seconds: max(0.5, range.duration), preferredTimescale: 600))
        guard reader.startReading() else { throw EngineError.readerFailed(reader.error?.localizedDescription ?? "couldn't start reading audio") }
        try? FileManager.default.removeItem(at: target)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: target, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == noErr,
                  let pointer else { continue }
            let count = length / MemoryLayout<Float>.size
            guard count > 0, let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { continue }
            pcm.frameLength = AVAudioFrameCount(count)
            pointer.withMemoryRebound(to: Float.self, capacity: count) { p in
                pcm.floatChannelData![0].update(from: p, count: count)
            }
            try file.write(from: pcm)
        }
        reader.cancelReading()
    }
}
