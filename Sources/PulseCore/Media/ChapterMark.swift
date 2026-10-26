import Foundation

/// A chapter embedded in a media file (#12).
public struct ChapterMark: Codable, Hashable, Sendable {
    public var time: Seconds
    public var title: String

    public init(time: Seconds, title: String) {
        self.time = time
        self.title = title
    }
}

/// YouTube links people paste (#1, #467): watch, youtu.be, shorts, live and embed forms.
public enum YouTubeURL {
    public static func videoID(from text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.lowercased().contains("youtu") else { return nil }
        let patterns = [#"[?&]v=([A-Za-z0-9_-]{11})"#, #"youtu\.be/([A-Za-z0-9_-]{11})"#, #"/(?:shorts|live|embed|v)/([A-Za-z0-9_-]{11})"#]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern), let m = regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
               let r = Range(m.range(at: 1), in: t) {
                return String(t[r])
            }
        }
        return nil
    }
}
