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

    /// `count` tracks for the mood: new downloads first (variety), topped up from the library. Throws only
    /// when nothing at all could be found or downloaded.
    public func tracks(for tags: [ClipTag], count: Int, progress: (@Sendable (String) -> Void)? = nil) async throws -> [OnlineTrack] {
        let (mood, queries) = MusicPicker.queries(for: tags)
        var chosen: [OnlineTrack] = []
        var candidates: [VideoSearchResult] = []
        for query in queries where candidates.count < count * 3 {
            progress?("Searching Creative Commons music (\(mood))")
            do {
                let found = try await search(query)
                PulseLog.info("Music search “\(query)”: \(found.count) results")
                candidates += found.filter { r in !candidates.contains { $0.videoID == r.videoID } }
            } catch {
                PulseLog.warning("Music search failed: \(error.localizedDescription)")
            }
        }
        let known = Set(downloaded.map(\.videoID))
        for result in MusicPicker.rank(candidates, count: count * 4 + 2) where chosen.count < count {
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
            let spare = downloaded.filter { t in !chosen.contains { $0.videoID == t.videoID } }
                .sorted { ($0.mood == mood ? 0 : 1, $0.addedAt) < ($1.mood == mood ? 0 : 1, $1.addedAt) }
            chosen += spare.prefix(count - chosen.count)
        }
        guard !chosen.isEmpty else { throw EngineError.readerFailed("Couldn't find or download any Creative Commons music") }
        return chosen
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
        let track = OnlineTrack(videoID: result.videoID, title: result.title, channel: result.channel, duration: result.duration ?? 0,
                                mood: mood, fileName: fileName)
        tracks.removeAll { $0.videoID == track.videoID }
        tracks.append(track)
        save()
        PulseLog.info("Music library: downloaded “\(track.title)” by \(track.channel) (\(result.videoID))")
        return track
    }

    /// Parallel 1 MiB ranged requests (a single connection is throttled to ~1 MB/s).
    func rangedDownload(_ url: URL, to destination: URL) async throws {
        var probe = URLRequest(url: url)
        probe.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        probe.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let (_, probeResponse) = try await session.data(for: probe)
        guard let http = probeResponse as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw EngineError.readerFailed("Music download refused")
        }
        var total: Int64 = 0
        if let range = http.value(forHTTPHeaderField: "Content-Range"), let last = range.split(separator: "/").last { total = Int64(last) ?? 0 }
        guard total > 0, total < 60 << 20 else { throw EngineError.readerFailed("Unexpected music file size") }
        let chunk: Int64 = 1 << 20
        let ranges = stride(from: Int64(0), to: total, by: Int(chunk)).map { ($0, min($0 + chunk, total) - 1) }
        let session = self.session
        let parts = try await withThrowingTaskGroup(of: (Int64, Data).self) { group -> [(Int64, Data)] in
            var collected: [(Int64, Data)] = []
            for (i, r) in ranges.enumerated() {
                if i >= 4, let done = try await group.next() { collected.append(done) }
                group.addTask {
                    var request = URLRequest(url: url)
                    request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
                    request.setValue("bytes=\(r.0)-\(r.1)", forHTTPHeaderField: "Range")
                    for attempt in 0..<3 {
                        if let reply = try? await session.data(for: request),
                           (reply.1 as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) == true,
                           Int64(reply.0.count) == r.1 - r.0 + 1 {
                            return (r.0, reply.0)
                        }
                        try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 500_000_000)
                    }
                    throw EngineError.readerFailed("Music download interrupted")
                }
            }
            for try await done in group { collected.append(done) }
            return collected
        }
        var file = Data(capacity: Int(total))
        for (_, data) in parts.sorted(by: { $0.0 < $1.0 }) { file.append(data) }
        let temp = destination.appendingPathExtension("part")
        try file.write(to: temp, options: .atomic)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tracks) { try? data.write(to: Self.indexURL, options: .atomic) }
    }
}
