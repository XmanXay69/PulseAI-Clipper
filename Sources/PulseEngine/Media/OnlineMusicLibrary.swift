import Foundation
import PulseCore
import YouTubeKit

/// Background music from YouTube, the TubeGrab way: YouTube's own Creative Commons search, audio-only
/// streams resolved locally with YouTubeKit (only youtube.com / googlevideo.com are contacted), and
/// parallel ranged downloads (YouTube throttles a single connection). Tracks are kept in
/// ~/Library/Application Support/PULSE/Music Library and reused instead of downloaded again.
public actor OnlineMusicLibrary {
    public static let shared = OnlineMusicLibrary()

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
    public static var folder: URL { PulseDirectories.ensure(PulseDirectories.applicationSupport.appendingPathComponent("Music Library", isDirectory: true)) }
    static var indexURL: URL { folder.appendingPathComponent("library.json") }

    private var tracks: [OnlineTrack]
    private let session: URLSession

    public init() {
        tracks = (try? JSONDecoder().decode([OnlineTrack].self, from: Data(contentsOf: Self.indexURL))) ?? []
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: config)
    }

    public var downloaded: [OnlineTrack] {
        tracks.filter { t in t.fileName.map { FileManager.default.fileExists(atPath: Self.folder.appendingPathComponent($0).path) } ?? false }
    }

    public func fileURL(for track: OnlineTrack) -> URL? {
        track.fileName.map { Self.folder.appendingPathComponent($0) }
    }

    /// The library track behind a media file (a Creative Commons bed in a project), if it came from here.
    public func track(forPath path: String) -> OnlineTrack? {
        let name = (path as NSString).lastPathComponent
        return tracks.first { $0.fileName == name }
    }

    /// `count` tracks for the mood: new downloads first (variety), topped up from the library. Throws only
    /// when nothing at all could be found or downloaded.
    public func tracks(for tags: [ClipTag], count: Int, pace: MusicPace = .medium, avoiding: Set<String> = [], favorites: Set<String> = [], blocked: Set<String> = [],
                       progress: (@Sendable (String) -> Void)? = nil) async throws -> [OnlineTrack] {
        let (mood, queries) = MusicPicker.queries(for: tags, pace: pace)
        var chosen: [OnlineTrack] = []
        // Favourites you already have in this mood come first (#292); "never again" tracks never come back.
        for track in downloaded where favorites.contains(track.videoID) && track.mood == mood && !avoiding.contains(track.videoID) && chosen.count < count {
            chosen.append(track)
        }
        let avoiding = avoiding.union(blocked)
        var candidates: [VideoSearchResult] = []
        for query in queries where candidates.count < count * 3 {
            progress?("Searching Creative Commons music (\(mood))")
            do {
                let found = try await search(query)
                PulseLog.info("Music search “\(query)”: \(found.count) results")
                // The same track under two names (#301): a re-upload with "(official)" or "[free]" added, the same length.
                candidates += found.filter { r in
                    !candidates.contains { $0.videoID == r.videoID || (Self.normalizedTitle($0.title) == Self.normalizedTitle(r.title) && abs(($0.duration ?? 0) - (r.duration ?? 0)) < 3) }
                }
            } catch {
                PulseLog.warning("Music search failed: \(error.localizedDescription)")
            }
        }
        let known = Set(downloaded.map(\.videoID))
        for result in MusicPicker.rank(candidates, count: count * 4 + 2) where chosen.count < count && !avoiding.contains(result.videoID) && !chosen.contains(where: { $0.videoID == result.videoID }) {
            if known.contains(result.videoID), let existing = downloaded.first(where: { $0.videoID == result.videoID }) {
                chosen.append(existing)
                continue
            }
            progress?("Downloading “\(result.title)”")
            do {
                chosen.append(try await download(result, mood: mood))
            } catch {
                PulseLog.warning("Music download failed for \(result.videoID) (“\(result.title)”): \(error.localizedDescription)")
            }
        }
        // Offline, or YouTube refused: reuse what's already in the library (same mood first).
        if chosen.count < count {
            let spare = downloaded.filter { t in !chosen.contains { $0.videoID == t.videoID } && !avoiding.contains(t.videoID) }
                .sorted { ($0.mood == mood ? 0 : 1, $0.addedAt) < ($1.mood == mood ? 0 : 1, $1.addedAt) }
            chosen += spare.prefix(count - chosen.count)
        }
        guard !chosen.isEmpty else { throw EngineError.readerFailed("Couldn't find or download any Creative Commons music") }
        // Tempo that fits the pace first (#291).
        return MusicPicker.preferring(chosen, pace: pace)
    }

    /// How many downloaded tracks sit on a mood's shelf.
    public func count(mood: String) -> Int { downloaded.filter { $0.mood == mood }.count }

    /// Fills each mood's shelf up to `perMood` tracks while the Mac is idle (#303), so an edit never waits on
    /// a download. Returns how many tracks were added.
    public func prefetch(perMood: Int = 5, pace: MusicPace = .medium, blocked: Set<String> = [], progress: (@Sendable (String) -> Void)? = nil) async -> Int {
        let shelves: [[ClipTag]] = [[.gaming], [.story], []]
        var added = 0
        for tags in shelves {
            let (mood, _) = MusicPicker.queries(for: tags, pace: pace)
            let have = count(mood: mood)
            guard have < perMood else { continue }
            let before = Set(downloaded.map(\.videoID))
            _ = try? await tracks(for: tags, count: perMood - have, pace: pace, avoiding: before, blocked: blocked, progress: progress)
            added += Set(downloaded.map(\.videoID)).subtracting(before).count
        }
        return added
    }

    /// Lower-cased, bracketed tags and punctuation dropped, spaces collapsed: "Sunny Day (Official) [Free]" → "sunny day".
    static func normalizedTitle(_ title: String) -> String {
        var t = title.lowercased()
        for pattern in ["\\([^)]*\\)", "\\[[^\\]]*\\]"] {
            if let regex = try? NSRegularExpression(pattern: pattern) { t = regex.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: " ") }
        }
        for word in ["official", "free", "no copyright", "copyright free", "royalty free", "creative commons", "music", "audio", "lyrics", "hd", "4k", "-", "|"] {
            t = t.replacingOccurrences(of: word, with: " ")
        }
        return t.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }

    func search(_ query: String) async throws -> [VideoSearchResult] {
        var request = URLRequest(url: YouTubeSearchParser.searchURL(query: query, creativeCommons: true))
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.httpShouldHandleCookies = false
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw EngineError.readerFailed("YouTube search returned \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        _ = http
        return YouTubeSearchParser.results(fromHTML: String(decoding: data, as: UTF8.self))
    }

    func download(_ result: VideoSearchResult, mood: String) async throws -> OnlineTrack {
        let youtube = YouTube(videoID: result.videoID, methods: [.local])
        let streams = try await youtube.streams
        guard let audio = streams.filterAudioOnly().filter({ $0.fileExtension == .m4a }).highestAudioBitrateStream() else {
            throw EngineError.readerFailed("No audio stream for \(result.videoID)")
        }
        let fileName = "\(result.videoID).m4a"
        let destination = Self.folder.appendingPathComponent(fileName)
        try await rangedDownload(audio.url, to: destination)
        var track = OnlineTrack(videoID: result.videoID, title: result.title, channel: result.channel, duration: result.duration ?? 0,
                                mood: mood, fileName: fileName, license: OnlineTrack.defaultLicense)
        // Tempo for the pace filter (#291); a bed with no steady beat just has none.
        if let grid = try? await BeatDetector.shared.beats(url: destination) { track.bpm = MusicPicker.bpm(fromBeats: grid) }
        tracks.removeAll { $0.videoID == track.videoID }
        tracks.append(track)
        save()
        PulseLog.info("Music library: downloaded “\(track.title)” by \(track.channel) (\(result.videoID))")
        return track
    }

    /// Music and B-roll clips: a few minutes of audio or a short clip, never more than 60 MiB.
    func rangedDownload(_ url: URL, to destination: URL) async throws {
        try await RangedDownloader.download(url, to: destination, session: session, userAgent: Self.userAgent, maxBytes: 60 << 20)
    }

    /// A whole VOD (#1, #467): hours of 720p, written straight to disk as it arrives.
    func downloadLarge(_ url: URL, to destination: URL, progress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws {
        try await RangedDownloader.download(url, to: destination, session: session, userAgent: Self.userAgent, maxBytes: 12 << 30, progress: progress)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tracks) { try? data.write(to: Self.indexURL, options: .atomic) }
    }
}
