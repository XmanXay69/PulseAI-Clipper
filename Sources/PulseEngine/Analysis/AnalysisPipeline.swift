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

        public init(transcribe: Bool = true, detectFaces: Bool = true, ai: AISettings = AISettings(), importedTranscript: Transcript? = nil) {
            self.transcribe = transcribe
            self.detectFaces = detectFaces
            self.ai = ai
            self.importedTranscript = importedTranscript
        }
    }

    public struct Output: Sendable {
        public var analysis: MediaAnalysis
        public var warnings: [String]
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
        let needsTranscription = options.transcribe && options.importedTranscript == nil && meta.hasAudio
        // Stage weights for overall progress.
        let audioWeight = meta.hasAudio ? 0.2 : 0
        let speechWeight = needsTranscription ? 0.55 : 0
        let videoWeight = meta.hasVideo ? 0.25 : 0
        let totalWeight = max(audioWeight + speechWeight + videoWeight, 0.001)
        var completed = 0.0
        let report: @Sendable (String, Double, Double, Double) -> Void = { stage, fraction, base, weight in
            progress(EngineProgress(stage: stage, fraction: min(1, (base + fraction * weight) / totalWeight)))
        }

        // 1. Audio.
        var audioFeatures: AudioFeatureSeries?
        var wavURL: URL?
        if meta.hasAudio {
            let wavTarget = needsTranscription ? cacheDirectory.appendingPathComponent("\(asset.id.uuidString)-16k.wav") : nil
            let base = completed
            do {
                let result = try await AudioAnalyzer().analyze(url: url, writeWAVTo: wavTarget, progress: { p in
                    report("Analyzing audio", p.fraction, base, audioWeight)
                }, isCancelled: isCancelled)
                audioFeatures = result.features
                wavURL = result.wavURL
                processing["audio"] = .local
            } catch EngineError.cancelled {
                throw EngineError.cancelled
            } catch {
                warnings.append("Audio analysis failed: \(error.localizedDescription)")
            }
            completed += audioWeight
        } else {
            warnings.append(EngineError.noAudioTrack(url).localizedDescription)
        }

        // 2. Transcript.
        var transcript = options.importedTranscript
        if transcript != nil { processing["transcript"] = .local }
        if needsTranscription, let wavURL {
            let engines = TranscriptionEngineFactory.candidates(settings: options.ai)
            if !engines.isEmpty {
                let base = completed
                var failures: [String] = []
                for engine in engines where transcript == nil {
                    let label = "Transcribing (\(engine.displayName))"
                    report(label, 0, base, speechWeight)
                    do {
                        let language = options.ai.transcriptionLanguage
                        transcript = try await engine.transcribe(audioURL: wavURL, language: language) { p in
                            report(label, p, base, speechWeight)
                        }
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
            completed += speechWeight
            try? FileManager.default.removeItem(at: wavURL)
        }
        if isCancelled() { throw EngineError.cancelled }

        // 3. Video.
        var visual: VisualFeatureSeries?
        if meta.hasVideo && asset.kind == .video {
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
            completed += videoWeight
        }

        let webcam = visual.flatMap { WebcamEstimator.estimate(faces: $0.faces, frameSize: meta.size) }
        let profile = MediaAnalysis.inferProfile(webcam: webcam, visual: visual, transcript: transcript, hasVideo: meta.hasVideo)
        let analysis = MediaAnalysis(assetID: asset.id, duration: meta.duration, audio: audioFeatures, visual: visual,
                                     transcript: transcript, webcam: webcam, profile: profile, processing: processing)
        progress(EngineProgress(stage: "Done", fraction: 1))
        return Output(analysis: analysis, warnings: warnings)
    }
}
