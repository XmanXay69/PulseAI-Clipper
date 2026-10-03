import Foundation

/// A background track found on YouTube (Creative Commons search) and saved in PULSE's music library.
public struct OnlineTrack: Codable, Hashable, Identifiable, Sendable {
    public var videoID: String
    public var title: String
    public var channel: String
    public var duration: Seconds
    /// The mood it was found for ("lofi", "chill gaming"…).
    public var mood: String
    /// File name inside the music library folder, once downloaded.
    public var fileName: String?
    public var addedAt: Date

    public var id: String { videoID }
    public var url: URL { URL(string: "https://www.youtube.com/watch?v=\(videoID)")! }

    /// The credit line for a video description.
    public var credit: String { "\(title) — \(channel) · \(url.absoluteString) (Creative Commons)" }

    public init(videoID: String, title: String, channel: String, duration: Seconds, mood: String, fileName: String? = nil, addedAt: Date = Date()) {
        self.videoID = videoID
        self.title = title
        self.channel = channel
        self.duration = duration
        self.mood = mood
        self.fileName = fileName
        self.addedAt = addedAt
    }
}

/// One result off a YouTube search page.
public struct VideoSearchResult: Hashable, Sendable {
    public var videoID: String
    public var title: String
    public var channel: String
    public var duration: Seconds?
}

public enum YouTubeSearchParser {
    /// YouTube's own "Creative Commons" search filter.
    public static let creativeCommonsFilter = "EgIwAQ%3D%3D"

    public static func searchURL(query: String, creativeCommons: Bool = true) -> URL {
        var components = URLComponents(string: "https://www.youtube.com/results")!
        components.queryItems = [URLQueryItem(name: "search_query", value: query)]
        var string = components.url!.absoluteString
        if creativeCommons { string += "&sp=\(creativeCommonsFilter)" }
        return URL(string: string)!
    }

    /// The first balanced `{…}` after `marker` (string-aware), e.g. `ytInitialData`.
    public static func extractJSONObject(from html: String, afterMarker marker: String) -> String? {
        guard let markerRange = html.range(of: marker) else { return nil }
        let tail = html[markerRange.upperBound...]
        guard let start = tail.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < tail.endIndex {
            let c = tail[index]
            if escaped {
                escaped = false
            } else if c == "\\", inString {
                escaped = true
            } else if c == "\"" {
                inString.toggle()
            } else if !inString {
                if c == "{" { depth += 1 } else if c == "}" {
                    depth -= 1
                    if depth == 0 { return String(tail[start...index]) }
                }
            }
            index = tail.index(after: index)
        }
        return nil
    }

    /// Videos from a search page's `ytInitialData` (the `videoRenderer` shape).
    public static func results(fromHTML html: String) -> [VideoSearchResult] {
        guard let json = extractJSONObject(from: html, afterMarker: "ytInitialData"),
              let data = json.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var renderers: [[String: Any]] = []
        collect(object, key: "videoRenderer", into: &renderers)
        var seen = Set<String>()
        return renderers.compactMap { r in
            guard let id = r["videoId"] as? String, seen.insert(id).inserted else { return nil }
            let duration = text(r["lengthText"]).flatMap(parseDuration)
            return VideoSearchResult(videoID: id, title: text(r["title"]) ?? "Untitled", channel: text(r["ownerText"]) ?? text(r["longBylineText"]) ?? "",
                                     duration: duration)
        }
    }

    /// "3:24" / "1:02:03" → seconds.
    public static func parseDuration(_ text: String) -> Seconds? {
        let parts = text.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
    }

    static func collect(_ any: Any, key: String, into out: inout [[String: Any]]) {
        if let dictionary = any as? [String: Any] {
            if let found = dictionary[key] as? [String: Any] { out.append(found) }
            for value in dictionary.values { collect(value, key: key, into: &out) }
        } else if let array = any as? [Any] {
            for value in array { collect(value, key: key, into: &out) }
        }
    }

    static func text(_ any: Any?) -> String? {
        guard let d = any as? [String: Any] else { return nil }
        if let s = d["simpleText"] as? String, !s.isEmpty { return s }
        if let runs = d["runs"] as? [[String: Any]] {
            let joined = runs.compactMap { $0["text"] as? String }.joined()
            return joined.isEmpty ? nil : joined
        }
        return nil
    }
}

/// Chooses calm, unobtrusive background music: a bed under the talking, never the main event.
public enum MusicPicker {
    /// Search phrases per mood, all aimed at low-key instrumentals.
    public static func queries(for tags: [ClipTag]) -> (mood: String, queries: [String]) {
        let set = Set(tags)
        if set.contains(.gaming) || !set.isDisjoint(with: [.hype, .highEnergy]) {
            return ("chill gaming", ["chill lofi gaming background music no copyright", "calm chillhop instrumental creative commons",
                                     "soft electronic background music no copyright"])
        }
        if !set.isDisjoint(with: [.story, .emotional, .conversation]) {
            return ("ambient", ["calm ambient background music no copyright", "soft piano background music creative commons"])
        }
        return ("lofi", ["lofi background music no copyright", "chill lofi instrumental creative commons",
                         "light acoustic background music no copyright"])
    }

    static let goodWords = ["no copyright", "copyright free", "royalty free", "free to use", "creative commons", "background",
                            "lofi", "lo-fi", "chill", "calm", "ambient", "instrumental", "relax", "soft", "acoustic", "piano"]
    /// Loud, vocal or unclear-rights material — not a quiet bed.
    static let badWords = ["official music video", "official video", "lyrics", "lyric", "vevo", "remix", "cover", "nightcore", "bass boosted",
                           "phonk", "dubstep", "metal", "trap", "epic", "intense", "hardstyle", "drill", " rap ", "edm", "bass drop",
                           "hour", "hours", "mix 20", "compilation", "live stream", "podcast", "reaction", "tutorial", "gameplay"]

    /// Higher is better; nil = don't use.
    public static func score(_ r: VideoSearchResult) -> Double? {
        let t = (r.title + " " + r.channel).lowercased()
        if badWords.contains(where: { t.contains($0) }) { return nil }
        // A 1.5–8 minute track: long enough for a chapter, small to download.
        guard let d = r.duration, d >= 90, d <= 480 else { return nil }
        var s = Double(goodWords.filter { t.contains($0) }.count)
        if t.contains("no copyright") || t.contains("copyright free") || t.contains("royalty free") { s += 1 }
        s -= abs(d - 180) / 240
        return s
    }

    /// The best `count` results, in order.
    public static func rank(_ results: [VideoSearchResult], count: Int) -> [VideoSearchResult] {
        results.compactMap { r in score(r).map { (r, $0) } }.sorted { $0.1 > $1.1 }.prefix(count).map(\.0)
    }

    /// Credits for the description: one line per distinct track.
    public static func creditBlock(_ tracks: [OnlineTrack]) -> String {
        var seen = Set<String>()
        let lines = tracks.filter { seen.insert($0.videoID).inserted }.map { "♪ " + $0.credit }
        return lines.isEmpty ? "" : (["Music"] + lines).joined(separator: "\n")
    }
}
