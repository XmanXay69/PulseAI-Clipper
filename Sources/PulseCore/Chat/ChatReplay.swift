import Foundation

/// One chat message, timed from the start of the recording.
public struct ChatMessage: Codable, Hashable, Sendable {
    public var time: Seconds
    public var author: String
    public var text: String

    public init(time: Seconds, author: String = "", text: String) {
        self.time = time
        self.author = author
        self.text = text
    }
}

/// A stream's chat replay. Imported from a file; used as a strong "this moment hit" signal.
public struct ChatLog: Codable, Hashable, Sendable {
    public var messages: [ChatMessage]
    /// Where it came from ("TwitchDownloader JSON", "YouTube live chat", …).
    public var format: String
    /// Added to every message time when the chat and video don't start together.
    public var offset: Seconds

    public init(messages: [ChatMessage], format: String, offset: Seconds = 0) {
        self.messages = messages.sorted { $0.time < $1.time }
        self.format = format
        self.offset = offset
    }

    public var isEmpty: Bool { messages.isEmpty }
}

public enum ChatParseError: Error, LocalizedError {
    case unrecognized

    public var errorDescription: String? {
        "PULSE couldn't read this chat file. Supported: TwitchDownloader JSON, chat-downloader JSON/CSV, YouTube live chat (.live_chat.json) and text logs with [h:mm:ss] timestamps."
    }
}

/// Reads the common chat-replay formats.
public enum ChatReplayParser {
    public static func parse(_ data: Data, fileName: String = "") throws -> ChatLog {
        if let log = parseTwitchDownloader(data) { return log }
        if let log = parseChatDownloaderJSON(data) { return log }
        if let log = parseYouTubeLiveChat(data) { return log }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw ChatParseError.unrecognized }
        if fileName.lowercased().hasSuffix(".csv") || text.prefix(200).lowercased().contains("time_in_seconds"), let log = parseCSV(text) { return log }
        if let log = parseTextLog(text) { return log }
        throw ChatParseError.unrecognized
    }

    /// TwitchDownloader: {"comments":[{"content_offset_seconds":12.3,"commenter":{"display_name":"x"},"message":{"body":"KEKW"}}]}
    static func parseTwitchDownloader(_ data: Data) -> ChatLog? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let comments = root["comments"] as? [[String: Any]] else { return nil }
        let messages: [ChatMessage] = comments.compactMap { c in
            guard let t = number(c["content_offset_seconds"]) else { return nil }
            let body = ((c["message"] as? [String: Any])?["body"] as? String) ?? (c["message"] as? String) ?? ""
            let author = ((c["commenter"] as? [String: Any])?["display_name"] as? String) ?? ""
            return ChatMessage(time: t, author: author, text: body)
        }
        return messages.isEmpty ? nil : ChatLog(messages: messages, format: "TwitchDownloader JSON")
    }

    /// chat-downloader (xenova): [{"time_in_seconds":12.3,"message":"…","author":{"name":"x"}}]
    static func parseChatDownloaderJSON(_ data: Data) -> ChatLog? {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !list.isEmpty else { return nil }
        let messages: [ChatMessage] = list.compactMap { m in
            guard let t = number(m["time_in_seconds"]) ?? number(m["timestamp_seconds"]) else { return nil }
            let author = ((m["author"] as? [String: Any])?["name"] as? String) ?? (m["author"] as? String) ?? ""
            return ChatMessage(time: t, author: author, text: m["message"] as? String ?? "")
        }
        return messages.isEmpty ? nil : ChatLog(messages: messages, format: "chat-downloader JSON")
    }

    /// yt-dlp's YouTube live chat replay: one JSON object per line with videoOffsetTimeMsec.
    static func parseYouTubeLiveChat(_ data: Data) -> ChatLog? {
        guard let text = String(data: data, encoding: .utf8), text.contains("replayChatItemAction") else { return nil }
        var messages: [ChatMessage] = []
        for line in text.split(separator: "\n") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let replay = obj["replayChatItemAction"] as? [String: Any],
                  let ms = number(replay["videoOffsetTimeMsec"]) else { continue }
            for action in replay["actions"] as? [[String: Any]] ?? [] {
                guard let item = (action["addChatItemAction"] as? [String: Any])?["item"] as? [String: Any],
                      let renderer = item["liveChatTextMessageRenderer"] as? [String: Any] else { continue }
                let runs = ((renderer["message"] as? [String: Any])?["runs"] as? [[String: Any]]) ?? []
                let body = runs.map { run -> String in
                    if let t = run["text"] as? String { return t }
                    if let emoji = run["emoji"] as? [String: Any] { return (emoji["shortcuts"] as? [String])?.first ?? "" }
                    return ""
                }.joined()
                let author = ((renderer["authorName"] as? [String: Any])?["simpleText"] as? String) ?? ""
                messages.append(ChatMessage(time: ms / 1000, author: author, text: body))
            }
        }
        return messages.isEmpty ? nil : ChatLog(messages: messages, format: "YouTube live chat")
    }

    /// CSV with a time_in_seconds (or time) column and a message column.
    static func parseCSV(_ text: String) -> ChatLog? {
        var lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else { return nil }
        let header = splitCSV(lines.removeFirst()).map { $0.lowercased() }
        guard let ti = header.firstIndex(where: { $0 == "time_in_seconds" || $0 == "time" || $0 == "offset" }),
              let mi = header.firstIndex(where: { $0 == "message" || $0 == "text" || $0 == "body" }) else { return nil }
        let ai = header.firstIndex(where: { $0.contains("author") || $0 == "user" || $0 == "name" })
        let messages: [ChatMessage] = lines.compactMap { line in
            let cols = splitCSV(line)
            guard cols.count > max(ti, mi), let t = Double(cols[ti]) ?? Timecode.parse(cols[ti]) else { return nil }
            return ChatMessage(time: t, author: ai.flatMap { $0 < cols.count ? cols[$0] : nil } ?? "", text: cols[mi])
        }
        return messages.isEmpty ? nil : ChatLog(messages: messages, format: "CSV")
    }

    /// "[0:12:34] name: message", "[12:34] name: message", "00:12:34 name: message".
    static func parseTextLog(_ text: String) -> ChatLog? {
        let pattern = try! NSRegularExpression(pattern: #"^\s*\[?(\d{1,2}:\d{2}(?::\d{2})?(?:\.\d+)?)\]?\s+([^:]{1,40}):\s?(.*)$"#)
        var messages: [ChatMessage] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line)
            guard let m = pattern.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges == 4,
                  let tr = Range(m.range(at: 1), in: s), let ar = Range(m.range(at: 2), in: s), let br = Range(m.range(at: 3), in: s),
                  let t = Timecode.parse(String(s[tr])) else { continue }
            messages.append(ChatMessage(time: t, author: String(s[ar]).trimmingCharacters(in: .whitespaces), text: String(s[br])))
        }
        return messages.count >= 3 ? ChatLog(messages: messages, format: "Text log") : nil
    }

    static func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    static func splitCSV(_ line: String) -> [String] {
        var cols: [String] = []
        var current = ""
        var quoted = false
        var chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted && i + 1 < chars.count && chars[i + 1] == "\"" { current.append("\""); i += 1 } else { quoted.toggle() }
            } else if c == "," && !quoted {
                cols.append(current)
                current = ""
            } else {
                current.append(c)
            }
            i += 1
        }
        cols.append(current)
        chars.removeAll()
        return cols.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

/// What a chat message says about the moment.
public enum ChatLexicon {
    public static let laugh: Set<String> = ["kekw", "lul", "lulw", "omegalul", "kekl", "icant", "lmao", "lmfao", "lol", "lool", "loool",
                                            "haha", "hahaha", "xd", "xdd", "😂", "🤣", "💀", "dead", "im dead", "pepelaugh", "kek", "lulw"]
    public static let hype: Set<String> = ["pog", "pogchamp", "poggers", "pogu", "w", "ww", "www", "gg", "lets go", "let's go", "letsgo",
                                           "clip it", "clip that", "clipped", "+2", "goated", "insane", "holy", "🔥", "omg", "no way", "wtf"]
    public static let shock: Set<String> = ["monkas", "d:", "wtf", "no shot", "nah", "😳", "😱", "omg", "what"]

    /// (laugh, hype) weights for one message.
    public static func score(_ text: String) -> (laugh: Float, hype: Float) {
        let lower = text.lowercased()
        let tokens = lower.split(whereSeparator: { $0 == " " || $0 == "!" || $0 == "?" || $0 == "." || $0 == "," }).map(String.init)
        var laughScore: Float = 0, hypeScore: Float = 0
        for t in tokens {
            if laugh.contains(t) || t.hasPrefix("lmao") || t.hasPrefix("hahah") || t.hasPrefix("kekw") || t.hasPrefix("omegalul") { laughScore += 1 }
            if hype.contains(t) || t.hasPrefix("pog") { hypeScore += 1 }
            if shock.contains(t) { hypeScore += 0.6 }
        }
        for phrase in ["clip it", "clip that", "no way", "lets go", "let's go", "im dead", "no shot"] where lower.contains(phrase) { hypeScore += 1.5 }
        for emoji in ["😂", "🤣", "💀"] where lower.contains(emoji) { laughScore += 1 }
        return (min(laughScore, 3), min(hypeScore, 3))
    }
}

/// Chat activity turned into per-step signals, shifted back for reaction delay (chat types a few
/// seconds after the moment happens).
public struct ChatSignals: Sendable {
    /// 0…1: how unusual the chat burst is here.
    public var activity: [Float]
    /// Laugh-emote density (feeds the laughter signal).
    public var laughter: [Float]

    public static let defaultLag: Seconds = 5

    public static func compute(_ log: ChatLog, duration: Seconds, step: Seconds, lag: Seconds = defaultLag) -> ChatSignals {
        let n = max(1, Int((duration / step).rounded(.up)))
        var rate = [Float](repeating: 0, count: n)
        var laughs = [Float](repeating: 0, count: n)
        var hype = [Float](repeating: 0, count: n)
        for m in log.messages {
            let t = m.time + log.offset - lag
            guard t >= 0, t < duration else { continue }
            let i = min(n - 1, Int(t / step))
            rate[i] += 1
            let s = ChatLexicon.score(m.text)
            laughs[i] += s.laugh
            hype[i] += s.hype
        }
        // Messages per step smoothed over ~4 s, compared with the local (±2 min) normal for this chat.
        let window = 4 / step
        let smoothRate = SeriesMath.smooth(rate, sigma: window / 2)
        let smoothLaugh = SeriesMath.smooth(laughs, sigma: window / 2)
        let smoothHype = SeriesMath.smooth(hype, sigma: window / 2)
        let baseline = SeriesMath.rollingMedian(smoothRate, radius: Int(120 / step))
        let spread = max(SeriesMath.mad(smoothRate), 0.05)
        var activity = [Float](repeating: 0, count: n)
        var laughter = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let burst = max(0, (smoothRate[i] - baseline[i]) / spread)
            let flavour = (smoothLaugh[i] + smoothHype[i]) / max(smoothRate[i], 0.2)
            activity[i] = min(1, burst / 6) * 0.7 + min(1, flavour) * 0.3 * min(1, burst / 2)
            laughter[i] = min(1, smoothLaugh[i] / max(1, baseline[i] * 0.5 + 0.5)) * min(1, burst / 2)
        }
        return ChatSignals(activity: activity, laughter: laughter)
    }
}
