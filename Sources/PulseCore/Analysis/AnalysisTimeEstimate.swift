import Foundation

/// The stages of "Analyze Video" that take noticeable time.
public enum AnalysisStage: String, Codable, CaseIterable, Sendable {
    case audio
    case transcription
    case video
}

/// How fast this Mac analyzes, in wall-clock seconds per minute of media for each stage. Starts from
/// conservative Apple Silicon defaults and learns from every finished analysis.
public struct AnalysisSpeedProfile: Codable, Hashable, Sendable {
    public var audio: Double
    public var transcription: Double
    public var video: Double
    /// Finished analyses this profile has learned from.
    public var samples: Int

    public init(audio: Double = 0.6, transcription: Double = 4, video: Double = 1.6, samples: Int = 0) {
        self.audio = audio
        self.transcription = transcription
        self.video = video
        self.samples = samples
    }

    public func rate(_ stage: AnalysisStage) -> Double {
        switch stage {
        case .audio: return audio
        case .transcription: return transcription
        case .video: return video
        }
    }

    /// Expected wall-clock seconds for each stage that will run.
    public func estimate(duration: Seconds, hasAudio: Bool, transcribe: Bool, hasVideo: Bool) -> AnalysisEstimate {
        let minutes = max(duration, 1) / 60
        var stages: [AnalysisStage: Seconds] = [:]
        if hasAudio { stages[.audio] = audio * minutes + 0.5 }
        if hasAudio && transcribe { stages[.transcription] = transcription * minutes + 2 }
        if hasVideo { stages[.video] = video * minutes + 0.5 }
        return AnalysisEstimate(stages: stages)
    }

    /// Folds a measured stage time into the profile (first measurement counts more; outliers are clamped).
    public mutating func learn(_ stage: AnalysisStage, mediaDuration: Seconds, wallSeconds: Seconds) {
        guard mediaDuration >= 20, wallSeconds > 0 else { return }
        let measured = (wallSeconds / (mediaDuration / 60)).clamped(0.02, 120)
        let weight = samples == 0 ? 0.7 : 0.35
        switch stage {
        case .audio: audio += (measured - audio) * weight
        case .transcription: transcription += (measured - transcription) * weight
        case .video: video += (measured - video) * weight
        }
    }

    /// Learns all measured stages of one run at once.
    public mutating func learn(stageSeconds: [AnalysisStage: Seconds], mediaDuration: Seconds) {
        guard !stageSeconds.isEmpty else { return }
        for (stage, seconds) in stageSeconds { learn(stage, mediaDuration: mediaDuration, wallSeconds: seconds) }
        samples += 1
    }
}

public struct AnalysisEstimate: Hashable, Sendable {
    public var stages: [AnalysisStage: Seconds]

    public init(stages: [AnalysisStage: Seconds]) {
        self.stages = stages
    }

    public var total: Seconds { stages.values.reduce(0, +) }

    /// Each stage's share of the total — used to weight overall progress so it tracks time.
    public func weight(_ stage: AnalysisStage) -> Double {
        let t = total
        return t > 0 ? (stages[stage] ?? 0) / t : 0
    }
}

/// Remaining-time estimate for a running job: starts from the up-front estimate and shifts toward
/// the observed rate as progress accumulates, smoothed so the number doesn't jump around.
public struct ProgressClock: Sendable {
    public var expectedTotal: Seconds?
    private var smoothed: Seconds?
    private var lastElapsed: Seconds = 0

    public init(expectedTotal: Seconds?) {
        self.expectedTotal = expectedTotal
    }

    public mutating func remaining(elapsed: Seconds, fraction: Double) -> Seconds? {
        let f = fraction.clamped(0, 1)
        if f >= 0.999 { return 0 }
        var estimate: Seconds?
        if let expectedTotal { estimate = max(expectedTotal - elapsed, expectedTotal * (1 - f) * 0.5) }
        if f > 0.02 && elapsed > 1.5 {
            let observed = elapsed * (1 - f) / f
            // Trust the observed rate more as the job goes on.
            let trust = min(1, f * 2.5)
            estimate = estimate.map { $0 * (1 - trust) + observed * trust } ?? observed
        }
        guard var value = estimate else { return nil }
        value = max(0, value)
        if let previous = smoothed {
            // Count down with the clock; only jump up when the new estimate is clearly worse.
            let expectedNow = max(0, previous - max(0, elapsed - lastElapsed))
            value = value > previous * 1.25 ? value : expectedNow * 0.5 + value * 0.5
        }
        smoothed = value
        lastElapsed = elapsed
        return value
    }
}

public enum DurationText {
    /// "less than a minute", "about 4 min", "about 1 h 20 min".
    public static func approximate(_ seconds: Seconds) -> String {
        if seconds < 50 { return seconds < 15 ? "a few seconds" : "less than a minute" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "about \(max(1, minutes)) min" }
        let h = minutes / 60, m = (minutes % 60 + 4) / 5 * 5
        return m == 0 || m == 60 ? "about \(m == 60 ? h + 1 : h) h" : "about \(h) h \(m) min"
    }

    /// "4 min left", "less than a minute left".
    public static func remaining(_ seconds: Seconds) -> String {
        seconds < 50 ? (seconds < 15 ? "almost done" : "less than a minute left") : approximate(seconds).replacingOccurrences(of: "about ", with: "~") + " left"
    }
}

public extension String {
    /// "less than a minute left" → "Less than a minute left".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
