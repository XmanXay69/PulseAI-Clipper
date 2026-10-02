import Foundation
import PulseCore

/// Runs the full "Analyze Video" pass for one asset:
/// audio features → transcription → frame sampling (motion, scene cuts, faces) → webcam estimate.
/// Each stage degrades gracefully: missing audio, failed transcription or missing video still
/// produce a usable analysis plus user-facing warnings.
public struct AnalysisPipeline: Sendable {
    public struct Options: Sendable {
        public var transcribe: Bool
        public var detectFaces: Bool
        public var ai: AISettings
        /// A transcript the user imported (SRT/VTT) — skips speech-to-text.
        public var importedTranscript: Transcript?
        /// Where the voice is when it was recorded separately (screen recording + mic/webcam file).
        public var voiceSource: VoiceSource?
        /// This Mac's measured speed — weights progress so it tracks time.
        public var speed: AnalysisSpeedProfile

        public init(transcribe: Bool = true, detectFaces: Bool = true, ai: AISettings = AISettings(), importedTranscript: Transcript? = nil,
                    voiceSource: VoiceSource? = nil, speed: AnalysisSpeedProfile = AnalysisSpeedProfile()) {
            self.transcribe = transcribe
            self.detectFaces = detectFaces
            self.ai = ai
            self.importedTranscript = importedTranscript
            self.voiceSource = voiceSource
            self.speed = speed
        }

        /// Expected time for this asset before starting (shown on the Analyze button).
        public func estimate(for asset: MediaAsset) -> AnalysisEstimate {
            let hasAudio = voiceSource != nil || asset.metadata.hasAudio
            return speed.estimate(duration: asset.metadata.duration, hasAudio: hasAudio,
                                  transcribe: transcribe && importedTranscript == nil, hasVideo: asset.metadata.hasVideo && asset.kind == .video)
        }
    }

    /// A companion recording carrying the speech. `delta` maps times: voiceTime = mainTime + delta.
    public struct VoiceSource: Sendable {
        public var url: URL
        public var delta: Seconds

        public init(url: URL, delta: Seconds) {
            self.url = url
            self.delta = delta
        }

        public init(main: MediaAsset, voice: MediaAsset) {
            self.init(url: MediaAccess.resolve(voice), delta: main.syncOffset - voice.syncOffset)
        }
    }

    /// Shifts a per-hop series from voice time into main time (pads with silence).
    static func shift(_ values: [Float], hops: Int, count: Int, fill: Float) -> [Float] {
        (0..<count).map { i in
            let j = i + hops
            return j >= 0 && j < values.count ? values[j] : fill
        }
    }

    static func shift(_ features: AudioFeatureSeries, delta: Seconds, duration: Seconds) -> AudioFeatureSeries {
        let hops = Int((delta / features.hop).rounded())
        let count = max(1, Int((duration / features.hop).rounded()))
        return AudioFeatureSeries(hop: features.hop,
                                  rmsDB: shift(features.rmsDB.values, hops: hops, count: count, fill: -100),
                                  peakDB: shift(features.peakDB.values, hops: hops, count: count, fill: -100),
                                  zeroCrossingRate: shift(features.zeroCrossingRate.values, hops: hops, count: count, fill: 0),
                                  spectralFlux: shift(features.spectralFlux.values, hops: hops, count: count, fill: 0))
    }

    static func shift(_ transcript: Transcript, delta: Seconds, duration: Seconds) -> Transcript {
        var t = transcript
        t.words = transcript.words.compactMap { w in
            var word = w
            word.start -= delta
            word.end -= delta
            return word.end > 0 && word.start < duration ? word : nil
        }
        return t
    }

    public struct Output: Sendable {
        public var analysis: MediaAnalysis
        public var warnings: [String]
        /// Wall-clock time each stage took (to learn this Mac's speed).
        public var stageSeconds: [AnalysisStage: Seconds] = [:]
        /// Stages restored from an earlier, interrupted run instead of being redone.
        public var resumedStages: [AnalysisStage] = []
    }

    public var cacheDirectory: URL

    public init(cacheDirectory: URL = PulseDirectories.cache("Analysis")) {
        self.cacheDirectory = cacheDirectory
    }

    public func run(asset: MediaAsset, options: Options, progress: @escaping ProgressHandler,
                    isCancelled: @escaping @Sendable () -> Bool = { false }) async throws -> Output {
        let url = MediaAccess.resolve(asset)
        guard FileManager.default.fileExists(atPath: url.path) else { throw EngineError.fileMissing(url) }
        var warnings: [String] = []
        var processing: [String: ProcessingLocation] = [:]
        let meta = asset.metadata
        // Speech and loudness come from the separate voice recording when there is one.
        let audioURL = options.voiceSource?.url ?? url
        let hasAudio = options.voiceSource != nil || meta.hasAudio
        let needsTranscription = options.transcribe && options.importedTranscript == nil && hasAudio
        // Stage weights for overall progress: each stage's expected share of the time.
        let estimate = options.speed.estimate(duration: meta.duration, hasAudio: hasAudio, transcribe: needsTranscription,
                                              hasVideo: meta.hasVideo && asset.kind == .video)
        let audioWeight = estimate.weight(.audio)
        let speechWeight = estimate.weight(.transcription)
        let videoWeight = estimate.weight(.video)
        let totalWeight = max(audioWeight + speechWeight + videoWeight, 0.001)
        var stageSeconds: [AnalysisStage: Seconds] = [:]
        var stageStart = Date()
        var completed = 0.0
        let report: @Sendable (String, Double, Double, Double) -> Void = { stage, fraction, base, weight in
            progress(EngineProgress(stage: stage, fraction: min(1, (base + fraction * weight) / totalWeight)))
        }

        // Finished stages of an interrupted run are picked up instead of redone.
        let checkpoint = AnalysisCheckpoint(directory: cacheDirectory, asset: asset, mediaURL: url, voiceURL: options.voiceSource?.url,
                                            settings: "\(options.detectFaces)|\(options.ai.transcriptionLanguage)|\(options.ai.detectSpeakers)|\(options.voiceSource?.delta ?? 0)")
        let savedAudio: AudioFeatureSeries? = hasAudio ? checkpoint.load(.audio) : nil
        let savedTranscript: Transcript? = needsTranscription ? checkpoint.load(.transcription) : nil
        let savedVisual: VisualFeatureSeries? = checkpoint.load(.video)
        var resumed: [AnalysisStage] = []
        let wavTarget = needsTranscription ? cacheDirectory.appendingPathComponent("\(asset.id.uuidString)-16k.wav") : nil
        let wavReady = wavTarget.map { FileManager.default.fileExists(atPath: $0.path) } ?? true

        // 1. Audio.
        var audioFeatures: AudioFeatureSeries?
        var wavURL: URL?
        if let savedAudio, savedTranscript != nil || wavReady {
            audioFeatures = savedAudio
            wavURL = savedTranscript == nil ? wavTarget : nil
            processing["audio"] = .local
            resumed.append(.audio)
            completed += audioWeight
        } else if hasAudio {
            let base = completed
            do {
                let result = try await AudioAnalyzer().analyze(url: audioURL, writeWAVTo: wavTarget, progress: { p in
                    report("Analyzing audio", p.fraction, base, audioWeight)
                }, isCancelled: isCancelled)
                audioFeatures = result.features
                if let voice = options.voiceSource {
                    audioFeatures = Self.shift(result.features, delta: voice.delta, duration: meta.duration)
                }
                wavURL = result.wavURL
                processing["audio"] = .local
            } catch EngineError.cancelled {
                throw EngineError.cancelled
            } catch {
                warnings.append("Audio analysis failed: \(error.localizedDescription)")
            }
            if let audioFeatures {
                stageSeconds[.audio] = Date().timeIntervalSince(stageStart)
                checkpoint.save(audioFeatures, .audio)
            }
            completed += audioWeight
        } else {
            warnings.append(EngineError.noAudioTrack(url).localizedDescription)
        }

        // 2. Transcript.
        var transcript = options.importedTranscript
        if transcript != nil { processing["transcript"] = .local }
        if let savedTranscript {
            transcript = savedTranscript
            processing["transcript"] = .local
            resumed.append(.transcription)
            completed += speechWeight
            if let wavTarget { try? FileManager.default.removeItem(at: wavTarget) }
        } else if needsTranscription, let wavURL {
            stageStart = Date()
            let engines = TranscriptionEngineFactory.candidates(settings: options.ai)
            if !engines.isEmpty {
                let base = completed
                var failures: [String] = []
                for engine in engines where transcript == nil {
                    let label = "Transcribing (\(engine.displayName))"
                    report(label, 0, base, speechWeight)
                    do {
                        let language = options.ai.transcriptionLanguage
                        let heard = try await engine.transcribe(audioURL: wavURL, language: language) { p in
                            report(label, p, base, speechWeight)
                        }
                        transcript = options.voiceSource.map { Self.shift(heard, delta: $0.delta, duration: meta.duration) } ?? heard
                        processing["transcript"] = engine.location
                    } catch {
                        if isCancelled() { throw EngineError.cancelled }
                        failures.append("\(engine.displayName): \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
                    }
                }
                if transcript == nil {
                    warnings.append(contentsOf: failures)
                } else if !failures.isEmpty {
                    warnings.append("Used a fallback transcription engine. " + failures.joined(separator: " "))
                }
            } else {
                warnings.append("No speech-to-text engine is available. Run the PULSE app bundle for Apple Speech, or install whisper.cpp (`brew install whisper-cpp`) and a model. Clips will be found from audio energy only.")
            }
            // Who's talking — reuses the 16 kHz audio written for transcription (voice-file time).
            if options.ai.detectSpeakers, let heard = transcript, heard.words.count >= 30, heard.speakerIDs.count < 2 {
                report("Detecting speakers", 0, completed + speechWeight * 0.95, 0)
                do {
                    transcript = try await SpeakerDiarization.diarize(heard, audioURL: wavURL, delta: options.voiceSource?.delta ?? 0,
                                                                      speakerCount: options.ai.speakerCount > 0 ? options.ai.speakerCount : nil,
                                                                      isCancelled: isCancelled)
                    processing["speakers"] = .local
                } catch EngineError.cancelled {
                    throw EngineError.cancelled
                } catch {
                    warnings.append("Speaker detection failed: \(error.localizedDescription)")
                }
            }
            if let transcript {
                stageSeconds[.transcription] = Date().timeIntervalSince(stageStart)
                checkpoint.save(transcript, .transcription)
            }
            completed += speechWeight
            try? FileManager.default.removeItem(at: wavURL)
        }
        if isCancelled() { throw EngineError.cancelled }

        // 3. Video.
        var visual: VisualFeatureSeries?
        if let savedVisual {
            visual = savedVisual
            processing["video"] = .local
            resumed.append(.video)
            completed += videoWeight
        } else if meta.hasVideo && asset.kind == .video {
            stageStart = Date()
            let base = completed
            do {
                visual = try await VisualAnalyzer().analyze(url: url, duration: meta.duration,
                                                            options: .init(detectFaces: options.detectFaces),
                                                            progress: { p in report("Analyzing video", p.fraction, base, videoWeight) },
                                                            isCancelled: isCancelled)
                processing["video"] = .local
            } catch EngineError.cancelled {
                throw EngineError.cancelled
            } catch {
                warnings.append("Video analysis failed: \(error.localizedDescription)")
            }
            if let visual {
                stageSeconds[.video] = Date().timeIntervalSince(stageStart)
                checkpoint.save(visual, .video)
            }
            completed += videoWeight
        }

        let webcam = visual.flatMap { WebcamEstimator.estimate(faces: $0.faces, frameSize: meta.size) }
        let profile = MediaAnalysis.inferProfile(webcam: webcam, visual: visual, transcript: transcript, hasVideo: meta.hasVideo)
        let analysis = MediaAnalysis(assetID: asset.id, duration: meta.duration, audio: audioFeatures, visual: visual,
                                     transcript: transcript, webcam: webcam, profile: profile, processing: processing)
        progress(EngineProgress(stage: "Done", fraction: 1))
        checkpoint.clear()
        return Output(analysis: analysis, warnings: warnings, stageSeconds: stageSeconds, resumedStages: resumed)
    }
}

/// Per-stage results of an analysis in progress, so quitting PULSE (or a crash) doesn't throw away
/// finished work. Keyed by the asset, the file's size + modification date, and the settings that
/// affect the result; cleared once the analysis completes.
struct AnalysisCheckpoint {
    let directory: URL
    let key: String

    init(directory: URL, asset: MediaAsset, mediaURL: URL, voiceURL: URL?, settings: String) {
        self.directory = directory
        func fingerprint(_ url: URL?) -> String {
            guard let url, let a = try? FileManager.default.attributesOfItem(atPath: url.path) else { return "-" }
            let size = (a[.size] as? NSNumber)?.int64Value ?? 0
            let date = (a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            return "\(size)-\(Int(date))"
        }
        // FNV-1a: stable across launches (Swift's Hasher isn't).
        let stable = settings.utf8.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        key = "\(asset.id.uuidString)-\(fingerprint(mediaURL))-\(fingerprint(voiceURL))-\(String(stable, radix: 36))"
    }

    func url(_ stage: AnalysisStage) -> URL { directory.appendingPathComponent("checkpoint-\(key)-\(stage.rawValue).plist") }

    func load<T: Decodable>(_ stage: AnalysisStage) -> T? {
        guard let data = try? Data(contentsOf: url(stage)) else { return nil }
        return try? PropertyListDecoder().decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, _ stage: AnalysisStage) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        if let data = try? encoder.encode(value) { try? data.write(to: url(stage), options: .atomic) }
    }

    func clear() {
        for stage in AnalysisStage.allCases { try? FileManager.default.removeItem(at: url(stage)) }
    }
}
