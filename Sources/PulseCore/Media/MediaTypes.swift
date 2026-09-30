import Foundation

/// File-type knowledge used by the importer. The engine performs the authoritative probe;
/// this gives fast classification, role hints from filenames and user-facing errors.
public enum MediaTypes {
    public static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "webm", "avi", "mts", "m2ts", "ts", "flv"]
    public static let audioExtensions: Set<String> = ["wav", "mp3", "m4a", "aac", "aif", "aiff", "caf", "flac", "ogg", "opus"]
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "tiff", "tif", "webp", "bmp"]
    public static let transcriptExtensions: Set<String> = ["srt", "vtt", "json"]

    /// Containers AVFoundation cannot open natively. These are remuxed/transcoded via FFmpeg
    /// when it is installed (see `MediaConverter` in PulseEngine).
    public static let needsConversionExtensions: Set<String> = ["mkv", "webm", "avi", "flv", "ogg", "opus", "ts", "mts", "m2ts"]

    public static func kind(forExtension ext: String) -> MediaKind? {
        let e = ext.lowercased()
        if videoExtensions.contains(e) { return .video }
        if audioExtensions.contains(e) { return .audio }
        if imageExtensions.contains(e) { return .image }
        return nil
    }

    public static func kind(for url: URL) -> MediaKind? {
        kind(forExtension: url.pathExtension)
    }

    public static var allImportableExtensions: [String] {
        Array(videoExtensions.union(audioExtensions).union(imageExtensions)).sorted()
    }

    /// Guesses a role from the filename so "Gameplay.mp4", "Webcam.mp4", "Microphone.wav"
    /// land on the right tracks automatically. Users can always change it.
    public static func suggestedRole(forFilename filename: String, kind: MediaKind) -> MediaRole {
        let name = (filename as NSString).deletingPathExtension.lowercased()
        let tokens = name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        func has(_ words: [String]) -> Bool {
            words.contains { word in tokens.contains(word) || name.contains(word) }
        }
        switch kind {
        case .image:
            return .graphic
        case .audio:
            if has(["sfx", "fx", "whoosh", "impact", "swoosh", "boom"]) { return .soundEffect }
            if has(["music", "song", "beat", "track", "bgm", "instrumental"]) { return .music }
            if has(["mic", "microphone", "voice", "vo", "narration", "podcast"]) { return .microphone }
            return .microphone
        case .video:
            if has(["webcam", "facecam", "face", "cam", "camera", "selfie"]) && !has(["gameplay", "screen"]) {
                return has(["camera"]) && !has(["webcam", "facecam"]) ? .camera : .webcam
            }
            if has(["gameplay", "game", "screen", "capture", "desktop", "display"]) { return .gameplay }
            return .main
        }
    }
}

/// Result of classifying a batch of dropped files before import.
public struct ImportPlan: Sendable {
    public struct Item: Sendable, Hashable {
        public var url: URL
        public var kind: MediaKind
        public var role: MediaRole
        public var needsConversion: Bool

        public init(url: URL, kind: MediaKind, role: MediaRole, needsConversion: Bool = false) {
            self.url = url
            self.kind = kind
            self.role = role
            self.needsConversion = needsConversion
        }
    }

    public struct Rejection: Sendable, Hashable {
        public var url: URL
        public var reason: String
    }

    public var items: [Item]
    public var transcripts: [URL]
    public var rejected: [Rejection]
    public var duplicates: [URL]

    /// True when the batch looks like a multi-source recording (e.g. gameplay + webcam + mic).
    public var isMultiSourceSession: Bool {
        let roles = Set(items.map(\.role))
        let visual = roles.intersection([.gameplay, .webcam, .camera])
        return visual.count >= 2 || (visual.count >= 1 && roles.contains(.microphone))
    }

    public static func make(urls: [URL], existingPaths: Set<String>) -> ImportPlan {
        var items: [Item] = []
        var transcripts: [URL] = []
        var rejected: [Rejection] = []
        var duplicates: [URL] = []
        var seen = Set<String>()
        for url in urls {
            let path = url.standardizedFileURL.path
            if existingPaths.contains(path) || seen.contains(path) {
                duplicates.append(url)
                continue
            }
            seen.insert(path)
            let ext = url.pathExtension.lowercased()
            if MediaTypes.transcriptExtensions.contains(ext) {
                transcripts.append(url)
                continue
            }
            guard let kind = MediaTypes.kind(forExtension: ext) else {
                let reason = ext.isEmpty
                    ? "The file has no extension, so PULSE can't tell what kind of media it is."
                    : "“.\(ext)” files aren't supported. Supported formats: MP4, MOV, MKV, WebM, WAV, MP3, M4A, AAC and common image formats."
                rejected.append(Rejection(url: url, reason: reason))
                continue
            }
            let role = MediaTypes.suggestedRole(forFilename: url.lastPathComponent, kind: kind)
            items.append(Item(url: url, kind: kind, role: role, needsConversion: MediaTypes.needsConversionExtensions.contains(ext)))
        }
        return ImportPlan(items: items, transcripts: transcripts, rejected: rejected, duplicates: duplicates)
    }
}
