import Foundation

/// Where a piece of AI processing happens. Shown to the user as a LOCAL / CLOUD badge.
public enum ProcessingLocation: String, Codable, Sendable {
    case local
    case cloud

    public var displayName: String { self == .local ? "LOCAL" : "CLOUD" }
}

/// Settings → AI Processing.
public enum AIProcessingPolicy: String, Codable, CaseIterable, Sendable {
    /// Use local models; fall back to cloud only when a feature has no local implementation AND the user allows it.
    case preferLocal
    /// Never send anything off this Mac.
    case alwaysLocal
    /// Cloud providers may be used without asking each time.
    case allowCloud
    /// Ask before every upload.
    case askBeforeUploading

    public var displayName: String {
        switch self {
        case .preferLocal: return "Prefer Local"
        case .alwaysLocal: return "Always Local"
        case .allowCloud: return "Allow Cloud AI"
        case .askBeforeUploading: return "Ask Before Uploading"
        }
    }

    public var summary: String {
        switch self {
        case .preferLocal: return "Everything runs on this Mac. Cloud AI is used only for optional extras you turn on."
        case .alwaysLocal: return "Nothing ever leaves this Mac. Cloud features are disabled."
        case .allowCloud: return "Cloud AI may process transcript text for titles and captions. Video never leaves your Mac."
        case .askBeforeUploading: return "PULSE asks each time before sending any text to a cloud AI provider."
        }
    }
}

public enum AICapability: String, Codable, CaseIterable, Sendable {
    case transcription
    case titleGeneration
    case hookAnalysis
    case clipRanking
    case captionEmphasis
    case speakerDiarization
    case faceDetection
    case sceneDetection
}

public enum AIProviderError: Error, LocalizedError, Equatable {
    case cloudNotPermitted
    case consentRequired(provider: String)
    case missingAPIKey(provider: String)
    case badResponse(String)
    case refused(String)
    case http(status: Int, message: String)
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .cloudNotPermitted:
            return "Cloud AI is turned off (Settings → AI Processing → Always Local). PULSE used its local AI instead."
        case .consentRequired(let provider):
            return "\(provider) needs your permission before PULSE sends it any transcript text."
        case .missingAPIKey(let provider):
            return "Add your \(provider) API key in Settings → AI Processing to use cloud titles."
        case .badResponse(let detail):
            return "The AI provider returned something PULSE couldn't read (\(detail)). Your clip is unchanged; try again."
        case .refused(let detail):
            return "The AI provider declined this request (\(detail)). PULSE's local suggestions are still available."
        case .http(let status, let message):
            return "The AI provider returned an error (HTTP \(status)): \(message)"
        case .unavailable(let detail):
            return detail
        }
    }
}

/// Context sent to insight providers. Only TEXT is ever included — never video or audio.
public struct ClipContext: Codable, Hashable, Sendable {
    public var transcript: String
    public var tags: [String]
    public var duration: Seconds
    public var platformHint: String

    public init(transcript: String, tags: [String], duration: Seconds, platformHint: String = "TikTok / YouTube Shorts / Instagram Reels") {
        self.transcript = transcript
        self.tags = tags
        self.duration = duration
        self.platformHint = platformHint
    }
}

public protocol AIProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var location: ProcessingLocation { get }
    var capabilities: Set<AICapability> { get }
}

/// Speech-to-text. Implemented in PulseEngine (Apple Speech, whisper.cpp).
public protocol TranscriptionProvider: AIProvider {
    func transcribe(audioURL: URL, language: String?, progress: @escaping @Sendable (Double) -> Void) async throws -> Transcript
}

/// Text-level insights: titles, platform captions, hook advice.
public protocol InsightProvider: AIProvider {
    func copy(for context: ClipContext) async throws -> ClipCopy
}

/// Local, deterministic insights using PULSE's heuristics.
public struct LocalInsightProvider: InsightProvider {
    public let id = "pulse.local"
    public let displayName = "PULSE Local AI"
    public let location = ProcessingLocation.local
    public let capabilities: Set<AICapability> = [.titleGeneration, .hookAnalysis, .clipRanking, .captionEmphasis]

    public init() {}

    public func copy(for context: ClipContext) async throws -> ClipCopy {
        let words = TranscriptParser.distribute(text: context.transcript, over: TimeRange(start: 0, end: max(context.duration, 1)))
        let tags = context.tags.compactMap { ClipTag(rawValue: $0) }
        return TitleGenerator.generate(words: words, payoff: context.duration * 0.6, tags: tags, seed: Int(Date().timeIntervalSince1970))
    }
}

/// Registry that picks providers while enforcing the privacy policy.
public final class AIProviderRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var insightProviders: [String: InsightProvider] = [:]
    private var transcriptionProviders: [String: TranscriptionProvider] = [:]

    public init() {
        register(LocalInsightProvider())
    }

    public func register(_ provider: InsightProvider) {
        lock.lock(); defer { lock.unlock() }
        insightProviders[provider.id] = provider
    }

    public func register(_ provider: TranscriptionProvider) {
        lock.lock(); defer { lock.unlock() }
        transcriptionProviders[provider.id] = provider
    }

    public var allInsightProviders: [InsightProvider] {
        lock.lock(); defer { lock.unlock() }
        return insightProviders.values.sorted { $0.id < $1.id }
    }

    public var allTranscriptionProviders: [TranscriptionProvider] {
        lock.lock(); defer { lock.unlock() }
        return transcriptionProviders.values.sorted { $0.id < $1.id }
    }

    /// Resolves the insight provider to use. Cloud providers are only returned when the policy
    /// allows it; with `.askBeforeUploading` the caller must pass `consentGranted: true`.
    public func insightProvider(preferred id: String?, policy: AIProcessingPolicy, consentGranted: Bool) throws -> InsightProvider {
        lock.lock()
        let chosen = id.flatMap { insightProviders[$0] }
        let local = insightProviders["pulse.local"] ?? LocalInsightProvider()
        lock.unlock()
        guard let preferred = chosen, preferred.location == .cloud else { return chosen ?? local }
        switch policy {
        case .alwaysLocal:
            throw AIProviderError.cloudNotPermitted
        case .askBeforeUploading:
            guard consentGranted else { throw AIProviderError.consentRequired(provider: preferred.displayName) }
            return preferred
        case .allowCloud, .preferLocal:
            // preferLocal still honours an explicit choice of a cloud provider for optional extras.
            return preferred
        }
    }

    public func transcriptionProvider(preferred id: String?, policy: AIProcessingPolicy) -> TranscriptionProvider? {
        lock.lock(); defer { lock.unlock() }
        let candidates = transcriptionProviders.values.filter { policy != .alwaysLocal || $0.location == .local }
        if let id, let match = candidates.first(where: { $0.id == id }) { return match }
        return candidates.first { $0.location == .local } ?? candidates.first
    }
}
