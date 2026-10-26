import Foundation

/// Share-ready text per platform (#84): title, caption and hashtags shaped to each platform's limits, ready to
/// paste into the upload form. PULSE never posts anything.
public enum SharePlatform: String, CaseIterable, Sendable {
    case tiktok, shorts, reels, x

    public var displayName: String {
        switch self {
        case .tiktok: return "TikTok"
        case .shorts: return "YouTube Shorts"
        case .reels: return "Instagram Reels"
        case .x: return "X"
        }
    }

    /// The platform's character limit for the pasted text.
    var limit: Int {
        switch self {
        case .tiktok: return 2200
        case .shorts: return 100
        case .reels: return 2200
        case .x: return 280
        }
    }
}

public enum ShareCopy {
    public static func text(for platform: SharePlatform, candidate: ClipCandidate) -> String {
        text(for: platform, title: candidate.title, copy: candidate.copy, tags: candidate.tags)
    }

    public static func text(for platform: SharePlatform, title: String, copy: ClipCopy, tags: [ClipTag]) -> String {
        let sentence = sentenceCase(title)
        var hashtags = copy.hashtags.isEmpty ? tags.map(\.hashtag) : copy.hashtags
        hashtags = hashtags.map { $0.hasPrefix("#") ? $0 : "#" + $0 }
        var seen = Set<String>()
        hashtags = hashtags.filter { seen.insert($0.lowercased()).inserted }
        let text: String
        switch platform {
        case .tiktok:
            let tagLine = hashtags.filter { $0 != "#shorts" }.prefix(5).joined(separator: " ")
            text = sentence + (tagLine.isEmpty ? "" : " " + tagLine)
        case .shorts:
            // The title field: 100 characters, "#shorts" at the end so it's never cut off.
            let room = platform.limit - " #shorts".count
            text = String(sentence.prefix(room)) + " #shorts"
        case .reels:
            let tagLine = (hashtags.filter { $0 != "#shorts" } + ["#reels"]).prefix(8).joined(separator: " ")
            text = sentence + "\n\n" + tagLine
        case .x:
            let tagLine = hashtags.filter { $0 != "#shorts" }.prefix(2).joined(separator: " ")
            let room = platform.limit - (tagLine.isEmpty ? 0 : tagLine.count + 1)
            text = String(sentence.prefix(room)) + (tagLine.isEmpty ? "" : " " + tagLine)
        }
        return String(text.prefix(platform.limit))
    }

    static func sentenceCase(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        // Shouting titles come down to a sentence; anything else is left as written.
        let letters = trimmed.filter(\.isLetter)
        let shouting = !letters.isEmpty && letters.allSatisfy(\.isUppercase)
        return shouting ? String(first).uppercased() + trimmed.dropFirst().lowercased() : trimmed
    }
}
