import AVFoundation
import Foundation
import PulseCore
import Speech

/// Apple's on-device speech recognizer. Runs fully locally (requiresOnDeviceRecognition) and
/// transcribes long recordings in ~50 s chunks split at quiet moments.
public final class AppleSpeechTranscriber: TranscriptionProvider, @unchecked Sendable {
    public let id = "apple.speech"
    public let displayName = "Apple On-Device Speech"
    public let location = ProcessingLocation.local
    public let capabilities: Set<AICapability> = [.transcription]

    public init() {}

    public static var hasUsageDescription: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil
    }

    public static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        guard hasUsageDescription else { return .denied }
        let current = SFSpeechRecognizer.authorizationStatus()
        if current != .notDetermined { return current }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status) }
        }
    }

    public func transcribe(audioURL: URL, language: String?, progress: @escaping @Sendable (Double) -> Void) async throws -> Transcript {
        guard AppleSpeechTranscriber.hasUsageDescription else {
            throw EngineError.transcriptionUnavailable("Apple speech recognition needs the PULSE app bundle (run scripts/build-app.sh). Install whisper.cpp (`brew install whisper-cpp`) to transcribe from a development build.")
        }
        let status = await AppleSpeechTranscriber.requestAuthorization()
        guard status == .authorized else {
            throw EngineError.transcriptionUnavailable("Speech recognition permission is off. Enable it in System Settings → Privacy & Security → Speech Recognition, or use Whisper in Settings → AI.")
        }
        let locale = Locale(identifier: language ?? Locale.current.identifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer() else {
            throw EngineError.transcriptionUnavailable("Speech recognition isn't available for \(locale.identifier).")
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw EngineError.transcriptionUnavailable("On-device speech recognition isn't installed for \(locale.identifier). PULSE never sends audio to the cloud without permission — enable Dictation in System Settings → Keyboard to download it, or use Whisper.")
        }
        let file = try AVAudioFile(forReading: audioURL)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let totalFrames = file.length
        let boundaries = try chunkBoundaries(file: file, targetChunk: 50, searchWindow: 8)
        var words: [TranscriptWord] = []
        let chunkDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-speech-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: chunkDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: chunkDirectory) }

        for (index, range) in boundaries.enumerated() {
            try Task.checkCancellation()
            let startFrame = AVAudioFramePosition(range.start * sampleRate)
            let frameCount = AVAudioFrameCount(min(Double(totalFrames - startFrame), range.duration * sampleRate))
            guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { continue }
            file.framePosition = startFrame
            try file.read(into: buffer, frameCount: frameCount)
            let chunkURL = chunkDirectory.appendingPathComponent("chunk-\(index).caf")
            let chunkFile = try AVAudioFile(forWriting: chunkURL, settings: format.settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            try chunkFile.write(from: buffer)
            let chunkWords = try await recognize(url: chunkURL, recognizer: recognizer)
            words.append(contentsOf: chunkWords.map { w in
                TranscriptWord(text: w.text, start: w.start + range.start, end: w.end + range.start, confidence: w.confidence)
            })
            progress(Double(index + 1) / Double(boundaries.count))
        }
        return Transcript(language: locale.identifier, words: words, source: .appleSpeech)
    }

    private func recognize(url: URL, recognizer: SFSpeechRecognizer) async throws -> [TranscriptWord] {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation
        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var finished = false
            func finish(_ result: Result<[TranscriptWord], Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                continuation.resume(with: result)
            }
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    let segments = result.bestTranscription.segments
                    let words = segments.map { s in
                        TranscriptWord(text: s.substring, start: s.timestamp, end: s.timestamp + max(s.duration, 0.05), confidence: s.confidence)
                    }
                    finish(.success(words))
                } else if let error {
                    let nsError = error as NSError
                    // "No speech detected" is not a failure for a quiet chunk.
                    if nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 1110 || nsError.code == 203) {
                        finish(.success([]))
                    } else {
                        finish(.failure(EngineError.transcriptionFailed(error.localizedDescription)))
                    }
                }
            }
        }
    }

    /// Chunk ranges of ~`targetChunk` seconds, each ending at the quietest 0.1 s window near the target.
    private func chunkBoundaries(file: AVAudioFile, targetChunk: Seconds, searchWindow: Seconds) throws -> [TimeRange] {
        let sampleRate = file.processingFormat.sampleRate
        let duration = Double(file.length) / sampleRate
        guard duration > targetChunk + searchWindow else { return [TimeRange(start: 0, end: duration)] }
        // Energy per 0.1 s.
        let hopFrames = AVAudioFrameCount(sampleRate * 0.1)
        var energy: [Float] = []
        file.framePosition = 0
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: hopFrames * 100) else { return [TimeRange(start: 0, end: duration)] }
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: hopFrames * 100)
            guard let data = buffer.floatChannelData?[0] else { break }
            let n = Int(buffer.frameLength)
            var i = 0
            while i < n {
                let end = min(n, i + Int(hopFrames))
                var sum: Float = 0
                for k in i..<end { sum += data[k] * data[k] }
                energy.append(sum / Float(max(end - i, 1)))
                i = end
            }
            if n == 0 { break }
        }
        var ranges: [TimeRange] = []
        var start: Seconds = 0
        while duration - start > targetChunk + searchWindow {
            let lo = Int((start + targetChunk - searchWindow) * 10)
            let hi = min(energy.count - 1, Int((start + targetChunk + searchWindow) * 10))
            var best = min(hi, max(lo, 0))
            if lo < hi {
                for k in lo...hi where energy[k] < energy[best] { best = k }
            }
            let cut = Double(best) / 10
            ranges.append(TimeRange(start: start, end: cut))
            start = cut
        }
        ranges.append(TimeRange(start: start, end: duration))
        return ranges
    }
}

/// whisper.cpp via its CLI. Release builds of PULSE.app carry their own `whisper-cli` (static, Metal) and
/// the English base model; otherwise `brew install whisper-cpp`. Fully local, word-level timestamps.
public struct WhisperCppTranscriber: TranscriptionProvider {
    public let id = "whisper.cpp"
    public let displayName = "Whisper (whisper.cpp)"
    public let location = ProcessingLocation.local
    public let capabilities: Set<AICapability> = [.transcription]

    public var executable: URL
    public var model: URL
    public var threads: Int

    public init(executable: URL, model: URL, threads: Int = max(2, ProcessInfo.processInfo.activeProcessorCount - 2)) {
        self.executable = executable
        self.model = model
        self.threads = threads
    }

    public static func locateExecutable(preferred: String = "") -> URL? {
        var candidates: [String] = []
        if !preferred.isEmpty { candidates.append(preferred) }
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "whisper-cli") { candidates.append(bundled.path) }
        for dir in ["/opt/homebrew/bin", "/usr/local/bin"] {
            for name in ["whisper-cli", "whisper-cpp", "whisper"] { candidates.append("\(dir)/\(name)") }
        }
        return candidates.map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public static func locateModel(preferred: String = "") -> URL? {
        if !preferred.isEmpty, FileManager.default.fileExists(atPath: preferred) { return URL(fileURLWithPath: preferred) }
        // Models you downloaded come first; the app bundle's base model is the out-of-the-box default.
        var dirs = [PulseDirectories.applicationSupport.appendingPathComponent("Models"),
                    URL(fileURLWithPath: "/opt/homebrew/share/whisper-cpp"),
                    URL(fileURLWithPath: "/usr/local/share/whisper-cpp")]
        if let resources = Bundle.main.resourceURL { dirs.append(resources) }
        let preferredOrder = ["ggml-large-v3-turbo", "ggml-medium", "ggml-small", "ggml-base", "ggml-tiny"]
        var found: [URL] = []
        for dir in dirs {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            found += files.filter { $0.pathExtension == "bin" && $0.lastPathComponent.hasPrefix("ggml") }
        }
        for name in preferredOrder {
            if let match = found.first(where: { $0.lastPathComponent.hasPrefix(name) }) { return match }
        }
        return found.first
    }

    public func transcribe(audioURL: URL, language: String?, progress: @escaping @Sendable (Double) -> Void) async throws -> Transcript {
        let outBase = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-whisper-\(UUID().uuidString)")
        let lang = (language ?? "en").split(separator: "-").first.map(String.init) ?? "auto"
        let args = ["-m", model.path, "-f", audioURL.path, "-oj", "-of", outBase.path, "-ml", "1", "-sow", "-l", lang,
                    "-t", String(threads), "-pp"]
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = args
            let errPipe = Pipe()
            process.standardError = errPipe
            process.standardOutput = FileHandle.nullDevice
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                // "whisper_print_progress_callback: progress =  42%"
                for line in text.split(separator: "\n") where line.contains("progress =") {
                    let digits = line.split(separator: "=").last?.trimmingCharacters(in: CharacterSet(charactersIn: " %")) ?? ""
                    if let pct = Double(digits) { progress(pct / 100) }
                }
            }
            process.terminationHandler = { p in
                errPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: p.terminationStatus)
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        let jsonURL = outBase.appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: jsonURL) }
        guard status == 0, let data = try? Data(contentsOf: jsonURL) else {
            throw EngineError.transcriptionFailed("whisper.cpp exited with status \(status). Check the model file in Settings → AI.")
        }
        var transcript = try TranscriptParser.parseJSON(data)
        transcript.source = .whisper
        return transcript
    }
}

/// Picks the transcription engine according to settings and availability.
public enum TranscriptionEngineFactory {
    public static func make(settings: AISettings) -> TranscriptionProvider? {
        candidates(settings: settings).first
    }

    /// Engines to try in order. Automatic prefers whisper.cpp when its model covers the language (no
    /// permission prompt, and release builds ship it), otherwise Apple Speech, and falls back to the other.
    public static func candidates(settings: AISettings) -> [TranscriptionProvider] {
        let whisper: WhisperCppTranscriber? = {
            guard let exe = WhisperCppTranscriber.locateExecutable(preferred: settings.whisperExecutablePath),
                  let model = WhisperCppTranscriber.locateModel(preferred: settings.whisperModelPath) else { return nil }
            return WhisperCppTranscriber(executable: exe, model: model)
        }()
        switch settings.transcriptionEngine {
        case .whisperCpp:
            return whisper.map { [$0] } ?? []
        case .appleOnDevice:
            return [AppleSpeechTranscriber()]
        case .automatic:
            var list: [TranscriptionProvider] = []
            if AppleSpeechTranscriber.hasUsageDescription { list.append(AppleSpeechTranscriber()) }
            if let whisper {
                if whisperCovers(language: settings.transcriptionLanguage, model: whisper.model) { list.insert(whisper, at: 0) } else { list.append(whisper) }
            }
            return list
        }
    }

    /// English-only models (`*.en.bin`) only cover English; multilingual ones cover everything.
    static func whisperCovers(language: String, model: URL) -> Bool {
        !model.lastPathComponent.contains(".en.") || language.lowercased().hasPrefix("en")
    }

    /// Plain-language status for the Analyze card: what will transcribe, or what to do about it.
    public static func friendlyStatus(settings: AISettings) -> (ready: Bool, text: String) {
        guard let first = candidates(settings: settings).first else {
            return (false, "No speech-to-text yet — clips will be found from sound alone. Settings → Transcription to set it up.")
        }
        if let whisper = first as? WhisperCppTranscriber {
            let bundled = whisper.executable.path.hasPrefix(Bundle.main.bundlePath + "/")
            let model = whisper.model.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "ggml-", with: "")
            return (true, "Speech-to-text: Whisper \(model)\(bundled ? ", built in" : "") — on this Mac")
        }
        return (true, "Speech-to-text: Apple, on this Mac (asks for permission the first time)")
    }

    public static func availabilitySummary(settings: AISettings) -> String {
        var parts: [String] = []
        parts.append(AppleSpeechTranscriber.hasUsageDescription ? "Apple Speech: available" : "Apple Speech: needs app bundle")
        if let exe = WhisperCppTranscriber.locateExecutable(preferred: settings.whisperExecutablePath) {
            let bundled = exe.path.hasPrefix(Bundle.main.bundlePath + "/")
            parts.append("whisper.cpp: \(bundled ? "built in" : exe.lastPathComponent)" + (WhisperCppTranscriber.locateModel(preferred: settings.whisperModelPath) == nil ? " (no model found)" : ""))
        } else {
            parts.append("whisper.cpp: not installed")
        }
        return parts.joined(separator: " · ")
    }
}
