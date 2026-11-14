import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Plans an edit from a recording's transcript (#1281). Implemented by the cloud providers and by any
/// OpenAI-compatible local server. Only the brief's text is sent: words, timecodes, energy marks and the
/// picker's scores. Video and audio never leave the Mac.
public protocol EditPlanProvider: AIProvider {
    func planEdit(brief: EditBrief) async throws -> EditPlanDraft
}

/// Collects a streamed Messages API reply as it arrives: the answer's text, why it stopped, and which model
/// wrote it. Fed one line of the event stream at a time.
public struct MessageStream: Sendable {
    public private(set) var text = ""
    public private(set) var stopReason: String?
    public private(set) var refusalCategory: String?
    public private(set) var model: String?
    public private(set) var error: String?
    public private(set) var isFinished = false

    public init() {}

    public mutating func feed(line: String) {
        guard line.hasPrefix("data:") else { return }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let object = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any],
              let type = object["type"] as? String else { return }
        switch type {
        case "message_start":
            model = (object["message"] as? [String: Any])?["model"] as? String
        case "content_block_start":
            // A fallback block marks where another model took over. What the first one wrote before declining
            // stays in the stream, so the answer is only what comes after the last such block.
            if let block = object["content_block"] as? [String: Any], block["type"] as? String == "fallback" {
                text = ""
                if let to = (block["to"] as? [String: Any])?["model"] as? String { model = to }
            }
        case "content_block_delta":
            if let delta = object["delta"] as? [String: Any], delta["type"] as? String == "text_delta", let piece = delta["text"] as? String {
                text += piece
            }
        case "message_delta":
            if let delta = object["delta"] as? [String: Any] {
                if let reason = delta["stop_reason"] as? String { stopReason = reason }
                if let details = delta["stop_details"] as? [String: Any] { refusalCategory = details["category"] as? String }
            }
        case "message_stop":
            isFinished = true
        case "error":
            error = ((object["error"] as? [String: Any])?["message"] as? String) ?? "the provider ended the reply with an error"
        default:
            break
        }
    }
}

extension AnthropicInsightProvider: EditPlanProvider {
    /// Planning an edit is a judgement task over a long text, so it runs at high effort, whatever the light
    /// effort titles and translations use.
    static let planEffort = "high"

    /// The request for an edit plan. Streamed in the app: a long transcript in and a reasoned plan out can run
    /// for minutes, and a streamed reply can't hit a response timeout while the model is still thinking.
    func makePlanRequest(brief: EditBrief, stream: Bool) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        var body: [String: Any] = [
            "model": model,
            "max_tokens": stream ? 64000 : 16000,
            "fallbacks": "default",
            "thinking": ["type": "adaptive"],
            "system": EditPlanner.system,
            "output_config": [
                "effort": Self.planEffort,
                "format": ["type": "json_schema", "schema": EditPlanner.schema] as [String: Any],
            ] as [String: Any],
            "messages": [["role": "user", "content": brief.text]],
        ]
        if stream { body["stream"] = true }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// The plan in a finished reply's text, or the reason there is none.
    static func draft(text: String, stopReason: String?, refusalCategory: String?, servedBy: String) throws -> EditPlanDraft {
        if stopReason == "refusal" { throw AIProviderError.refused(refusalCategory ?? "policy") }
        if stopReason == "max_tokens" { throw AIProviderError.badResponse("the plan was cut off before it finished") }
        guard let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else {
            throw AIProviderError.badResponse("no plan in the reply")
        }
        return try EditPlanner.parse(json, writtenBy: "Claude (\(servedBy))")
    }

    /// A whole (not streamed) reply.
    static func draft(response object: [String: Any], model: String) throws -> EditPlanDraft {
        let category = (object["stop_details"] as? [String: Any])?["category"] as? String
        let blocks = object["content"] as? [[String: Any]] ?? []
        // After a fallback, the answer is the text that follows the last fallback block.
        let last = blocks.lastIndex { $0["type"] as? String == "fallback" } ?? -1
        let text = blocks.suffix(from: last + 1).compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
        return try draft(text: text, stopReason: object["stop_reason"] as? String, refusalCategory: category,
                         servedBy: object["model"] as? String ?? model)
    }

    public func planEdit(brief: EditBrief) async throws -> EditPlanDraft {
        guard !apiKey.isEmpty else { throw AIProviderError.missingAPIKey(provider: displayName) }
        #if canImport(FoundationNetworking)
        // Linux has no streaming URLSession; PULSE itself only runs on macOS, where the branch below is used.
        let (data, response) = try await URLSession.shared.data(for: try makePlanRequest(brief: brief, stream: false))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            let message = ((object["error"] as? [String: Any])?["message"] as? String) ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw AIProviderError.http(status: status, message: message)
        }
        return try Self.draft(response: object, model: model)
        #else
        let (bytes, response) = try await URLSession.shared.bytes(for: try makePlanRequest(brief: brief, stream: true))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // An error arrives as one JSON object, not as a stream.
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count >= 8000 { break }
            }
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let message = ((object["error"] as? [String: Any])?["message"] as? String) ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw AIProviderError.http(status: status, message: message)
        }
        var reply = MessageStream()
        for try await line in bytes.lines {
            reply.feed(line: line)
            if reply.error != nil || reply.isFinished { break }
        }
        if let error = reply.error { throw AIProviderError.http(status: status, message: error) }
        guard reply.isFinished || reply.stopReason != nil else { throw AIProviderError.badResponse("the reply stopped before it was finished") }
        return try Self.draft(text: reply.text, stopReason: reply.stopReason, refusalCategory: reply.refusalCategory, servedBy: reply.model ?? model)
        #endif
    }
}

extension OpenAICompatibleInsightProvider: EditPlanProvider {
    func makePlanRequest(brief: EditBrief) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        // A local model reading a long transcript can take a long while before its first word.
        request.timeoutInterval = 900
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization") }
        let body: [String: Any] = [
            "model": model,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": EditPlanner.system + "\n\n" + EditPlanner.shapeInWords],
                ["role": "user", "content": brief.text],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// The plan in a chat completion. Models that wrap their JSON in a code fence or a sentence are read too.
    static func draft(completion object: [String: Any], servedBy: String) throws -> EditPlanDraft {
        guard let choices = object["choices"] as? [[String: Any]], let choice = choices.first,
              let message = choice["message"] as? [String: Any], let text = message["content"] as? String else {
            throw AIProviderError.badResponse("unexpected chat completion format")
        }
        if choice["finish_reason"] as? String == "length" { throw AIProviderError.badResponse("the plan was cut off before it finished: the model's reply limit is too small for this recording") }
        var body = text
        if let open = body.firstIndex(of: "{"), let close = body.lastIndex(of: "}"), open < close { body = String(body[open...close]) }
        guard let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] else {
            throw AIProviderError.badResponse("no plan in the reply")
        }
        return try EditPlanner.parse(json, writtenBy: servedBy)
    }

    public func planEdit(brief: EditBrief) async throws -> EditPlanDraft {
        if location == .cloud && apiKey.isEmpty { throw AIProviderError.missingAPIKey(provider: displayName) }
        let (data, response) = try await URLSession.shared.data(for: try makePlanRequest(brief: brief))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AIProviderError.http(status: status, message: String(decoding: data.prefix(300), as: UTF8.self))
        }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return try Self.draft(completion: object, servedBy: (object["model"] as? String).map { "\(displayName) (\($0))" } ?? displayName)
    }
}
