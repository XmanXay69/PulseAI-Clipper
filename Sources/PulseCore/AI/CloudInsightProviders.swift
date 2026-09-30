import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Shared prompt + schema for clip copy generation. Only transcript TEXT is sent.
enum ClipCopyPrompt {
    static let system = """
    You write short-form video titles and captions for creators. You receive the transcript of one \
    clip cut from a longer stream or video. Write copy that is punchy, honest to what happens in the clip, \
    and never clickbait that misrepresents it. Titles: at most 60 characters, uppercase is fine, at most one emoji. \
    Return JSON only.
    """

    static func user(_ context: ClipContext) -> String {
        """
        Clip length: \(Int(context.duration.rounded())) seconds
        Detected tags: \(context.tags.joined(separator: ", "))
        Platforms: \(context.platformHint)

        Transcript:
        \(context.transcript)

        Produce 4 alternative titles, a YouTube Shorts title, a TikTok caption and an Instagram caption \
        (each with 3–5 relevant hashtags), plus the list of hashtags you used.
        """
    }

    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "titles": ["type": "array", "items": ["type": "string"]],
            "shorts_title": ["type": "string"],
            "tiktok_caption": ["type": "string"],
            "instagram_caption": ["type": "string"],
            "hashtags": ["type": "array", "items": ["type": "string"]],
        ],
        "required": ["titles", "shorts_title", "tiktok_caption", "instagram_caption", "hashtags"],
        "additionalProperties": false,
    ]

    static func parse(_ json: [String: Any], generatedBy: String) throws -> ClipCopy {
        guard let titles = json["titles"] as? [String], !titles.isEmpty else {
            throw AIProviderError.badResponse("missing titles")
        }
        return ClipCopy(titles: titles,
                        shortsTitle: json["shorts_title"] as? String ?? titles[0],
                        tiktokCaption: json["tiktok_caption"] as? String ?? titles[0],
                        instagramCaption: json["instagram_caption"] as? String ?? titles[0],
                        hashtags: json["hashtags"] as? [String] ?? [],
                        generatedBy: generatedBy)
    }
}

/// Claude via the Anthropic Messages API (raw HTTP — there is no official Swift SDK).
/// Uses structured outputs (`output_config.format`) so the reply is always valid JSON, and opts
/// into server-side refusal fallbacks.
public struct AnthropicInsightProvider: InsightProvider {
    public let id = "anthropic"
    public let displayName = "Claude (Anthropic)"
    public let location = ProcessingLocation.cloud
    public let capabilities: Set<AICapability> = [.titleGeneration, .hookAnalysis]

    public var apiKey: String
    public var model: String
    /// Copywriting is a light task — low effort keeps it fast and cheap.
    public var effort: String
    public var endpoint: URL

    public init(apiKey: String, model: String = "claude-opus-5-5", effort: String = "low",
                endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!) {
        self.apiKey = apiKey
        self.model = model
        self.effort = effort
        self.endpoint = endpoint
    }

    func makeRequest(for context: ClipContext) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "fallbacks": "default",
            "system": ClipCopyPrompt.system,
            "output_config": [
                "effort": effort,
                "format": ["type": "json_schema", "schema": ClipCopyPrompt.schema],
            ],
            "messages": [["role": "user", "content": ClipCopyPrompt.user(context)]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public func copy(for context: ClipContext) async throws -> ClipCopy {
        guard !apiKey.isEmpty else { throw AIProviderError.missingAPIKey(provider: displayName) }
        let request = try makeRequest(for: context)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            let message = ((object["error"] as? [String: Any])?["message"] as? String) ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw AIProviderError.http(status: status, message: message)
        }
        return try Self.parseResponse(object, model: model)
    }

    static func parseResponse(_ object: [String: Any], model: String) throws -> ClipCopy {
        if object["stop_reason"] as? String == "refusal" {
            let category = ((object["stop_details"] as? [String: Any])?["category"] as? String) ?? "policy"
            throw AIProviderError.refused(category)
        }
        guard let content = object["content"] as? [[String: Any]] else { throw AIProviderError.badResponse("no content") }
        // Thinking blocks may precede the answer; the JSON lives in the text block.
        guard let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else {
            throw AIProviderError.badResponse("no JSON text block")
        }
        let servedBy = object["model"] as? String ?? model
        return try ClipCopyPrompt.parse(json, generatedBy: "Claude (\(servedBy))")
    }
}

/// Any OpenAI-compatible chat-completions endpoint: OpenAI, or LOCAL servers such as
/// LM Studio / Ollama / llama.cpp (set `isLocalServer` so the privacy badge says LOCAL).
public struct OpenAICompatibleInsightProvider: InsightProvider {
    public let id: String
    public let displayName: String
    public let location: ProcessingLocation
    public let capabilities: Set<AICapability> = [.titleGeneration]

    public var apiKey: String
    public var model: String
    public var baseURL: URL

    public init(id: String = "openai", displayName: String = "OpenAI-compatible", apiKey: String, model: String,
                baseURL: URL = URL(string: "https://api.openai.com/v1")!, isLocalServer: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.location = isLocalServer ? .local : .cloud
    }

    public func copy(for context: ClipContext) async throws -> ClipCopy {
        if location == .cloud && apiKey.isEmpty { throw AIProviderError.missingAPIKey(provider: displayName) }
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization") }
        let schemaDescription = "Reply with a JSON object with keys: titles (array of strings), shorts_title, tiktok_caption, instagram_caption (strings), hashtags (array of strings)."
        let body: [String: Any] = [
            "model": model,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": ClipCopyPrompt.system + " " + schemaDescription],
                ["role": "user", "content": ClipCopyPrompt.user(context)],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AIProviderError.http(status: status, message: String(decoding: data.prefix(300), as: UTF8.self))
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String,
              let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else {
            throw AIProviderError.badResponse("unexpected chat completion format")
        }
        return try ClipCopyPrompt.parse(json, generatedBy: displayName)
    }
}
