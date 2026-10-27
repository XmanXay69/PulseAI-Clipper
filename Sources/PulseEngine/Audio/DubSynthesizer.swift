import AVFoundation
import Foundation
import PulseCore

/// Speaks dub lines with the system voice for a language (#486) and writes one audio file the length of the
/// timeline: each line starts at its time (or right after the previous one when speech runs long), silence in
/// between. No network; the voices are the ones installed in System Settings → Accessibility → Spoken Content.
public enum DubSynthesizer {
    /// The best installed voice for a language code ("es", "pt-BR"…): enhanced or premium quality first.
    public static func voice(for language: String) -> AVSpeechSynthesisVoice? {
        let code = language.lowercased()
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix(code) }
        return voices.max { a, b in a.quality.rawValue < b.quality.rawValue } ?? AVSpeechSynthesisVoice(language: language)
    }

    /// Languages a voice is installed for, as codes.
    public static var installedLanguages: Set<String> {
        Set(AVSpeechSynthesisVoice.speechVoices().map { String($0.language.prefix(2)).lowercased() })
    }

    public static func synthesize(lines: [DubLine], language: String, duration: Seconds, to url: URL,
                                  progress: @escaping @Sendable (Double) -> Void = { _ in },
                                  isCancelled: @escaping @Sendable () -> Bool = { false }) async throws {
        guard !lines.isEmpty else { throw EngineError.exportFailed("nothing to dub") }
        guard let voice = voice(for: language) else { throw EngineError.exportFailed("no \(CaptionTranslator.name(for: language)) voice is installed (System Settings → Accessibility → Spoken Content)") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        let synthesizer = AVSpeechSynthesizer()
        var file: AVAudioFile?
        var format: AVAudioFormat?
        var cursor: Seconds = 0   // seconds written so far

        func writeSilence(until time: Seconds) throws {
            guard let file, let format, time > cursor else { return }
            let frames = AVAudioFrameCount((time - cursor) * format.sampleRate)
            guard frames > 0, let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
            silence.frameLength = frames
            // A fresh buffer's memory isn't promised to be zero. Interleaved audio is one plane holding every
            // channel; planar audio is one plane per channel.
            let channels = Int(format.channelCount)
            let planes = format.isInterleaved ? 1 : channels
            let perPlane = Int(frames) * (format.isInterleaved ? channels : 1)
            if let data = silence.floatChannelData {
                for c in 0..<planes { data[c].update(repeating: 0, count: perPlane) }
            } else if let data = silence.int16ChannelData {
                for c in 0..<planes { data[c].update(repeating: 0, count: perPlane) }
            } else if let data = silence.int32ChannelData {
                for c in 0..<planes { data[c].update(repeating: 0, count: perPlane) }
            }
            try file.write(from: silence)
            cursor = time
        }

        for (i, line) in lines.enumerated() {
            if isCancelled() { throw EngineError.cancelled }
            let utterance = AVSpeechUtterance(string: line.text)
            utterance.voice = voice
            utterance.rate = Float(DubPlanner.rate(wordCount: line.wordCount, seconds: line.duration))
            let buffers = await Self.speak(utterance, with: synthesizer)
            guard let firstBuffer = buffers.first else { continue }
            if file == nil {
                format = firstBuffer.format
                file = try AVAudioFile(forWriting: url, settings: firstBuffer.format.settings, commonFormat: firstBuffer.format.commonFormat, interleaved: firstBuffer.format.isInterleaved)
            }
            guard let file, let format else { continue }
            try writeSilence(until: line.start)
            for buffer in buffers where buffer.format.sampleRate == format.sampleRate && buffer.format.channelCount == format.channelCount {
                try file.write(from: buffer)
                cursor += Double(buffer.frameLength) / format.sampleRate
            }
            progress(Double(i + 1) / Double(lines.count))
        }
        try writeSilence(until: duration)
        guard file != nil else { throw EngineError.exportFailed("the voice produced no audio") }
    }

    /// The PCM buffers for one utterance. The synthesizer ends every utterance with an empty buffer; the
    /// continuation resumes on the first of those and ignores anything after it, and a voice that never
    /// finishes is given up on after a minute rather than hanging the job.
    static func speak(_ utterance: AVSpeechUtterance, with synthesizer: AVSpeechSynthesizer) async -> [AVAudioPCMBuffer] {
        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var collected: [AVAudioPCMBuffer] = []
            var continuation: CheckedContinuation<[AVAudioPCMBuffer], Never>?
            var isPending: Bool { lock.lock(); defer { lock.unlock() }; return continuation != nil }
            func finish() {
                lock.lock()
                let c = continuation
                continuation = nil
                let result = collected
                lock.unlock()
                c?.resume(returning: result)
            }
        }
        let box = Box()
        return await withCheckedContinuation { continuation in
            box.continuation = continuation
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    box.finish()
                } else {
                    box.lock.lock(); box.collected.append(pcm); box.lock.unlock()
                }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 60) {
                if box.isPending {
                    synthesizer.stopSpeaking(at: .immediate)
                    box.finish()
                }
            }
        }
    }
}
