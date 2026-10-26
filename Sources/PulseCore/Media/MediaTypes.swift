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
    /// Chat replays found next to the recordings (#13): `<name>.json`, `<name>-chat.json`, `<name>_chat.json`.
    public var chatLogs: [URL] = []
    /// An import preset's say on syncing (#25): true = treat the batch as one session whatever the roles,
    /// nil = decide from the roles.
    public var forcedSession: Bool?

    /// True when the batch looks like a multi-source recording (e.g. gameplay + webcam + mic).
    public var isMultiSourceSession: Bool {
        if let forcedSession { return forcedSession && items.count >= 2 }
        let roles = Set(items.map(\.role))
        let visual = roles.intersection([.gameplay, .webcam, .camera])
        return visual.count >= 2 || (visual.count >= 1 && roles.contains(.microphone))
    }

    /// Folders in a drop or an open panel become their media and transcript files (one level, by name);
    /// everything else passes through in order. Hidden files and folders that can't be read are skipped.
    public static func expandingFolders(_ urls: [URL]) -> [URL] {
        var out: [URL] = []
        let wanted = Set(MediaTypes.allImportableExtensions).union(MediaTypes.transcriptExtensions)
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey],
                                                                              options: [.skipsHiddenFiles])) ?? []
                out += children
                    .filter { child in
                        let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                        return !isDir && wanted.contains(child.pathExtension.lowercased())
                    }
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            } else {
                out.append(url)
            }
        }
        return out
    }

    /// `siblings` lists the files in a recording's folder (the default reads the disk); a transcript or chat
    /// replay with the recording's name beside it comes along without being dropped (#13, #14).
    public static func make(urls: [URL], existingPaths: Set<String>, siblings: (URL) -> [URL] = ImportPlan.diskSiblings) -> ImportPlan {
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
        // Sidecars beside each recording (#13, #14).
        var chatLogs: [URL] = []
        for item in items where item.kind == .video || item.kind == .audio {
            for (transcript, chat) in sidecars(for: item.url, siblings: siblings) {
                if let transcript, !seen.contains(transcript.standardizedFileURL.path) {
                    seen.insert(transcript.standardizedFileURL.path)
                    transcripts.append(transcript)
                }
                if let chat, !seen.contains(chat.standardizedFileURL.path) {
                    seen.insert(chat.standardizedFileURL.path)
                    chatLogs.append(chat)
                }
            }
        }
        return ImportPlan(items: items, transcripts: transcripts, rejected: rejected, duplicates: duplicates, chatLogs: chatLogs)
    }

    /// The files next to a recording that belong to it: `<name>.srt` / `.vtt` are transcripts; `<name>.json`,
    /// `<name>-chat.json`, `<name>_chat.json`, `<name>.chat.json` are chat replays.
    static func sidecars(for url: URL, siblings: (URL) -> [URL]) -> [(transcript: URL?, chat: URL?)] {
        let base = url.deletingPathExtension().lastPathComponent.lowercased()
        var out: [(URL?, URL?)] = []
        for file in siblings(url) where file.standardizedFileURL != url.standardizedFileURL {
            let ext = file.pathExtension.lowercased()
            let stem = file.deletingPathExtension().lastPathComponent.lowercased()
            if ["srt", "vtt"].contains(ext), stem == base { out.append((file, nil)); continue }
            if ["json", "csv"].contains(ext) {
                let chatStems = [base, base + "-chat", base + "_chat", base + ".chat", base + " chat"]
                if chatStems.contains(stem) { out.append((nil, file)) }
            }
        }
        return out
    }

    public static func diskSiblings(_ url: URL) -> [URL] {
        let folder = url.deletingLastPathComponent()
        return (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    }
}
