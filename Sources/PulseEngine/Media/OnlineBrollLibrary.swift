import Foundation
import PulseCore
import YouTubeKit

/// Short Creative Commons meme / reaction clips for the "B-roll cutaways" extra — found and downloaded the
/// same way as the music (YouTube's Creative Commons filter, streams resolved locally, ranged downloads).
/// Kept in ~/Library/Application Support/PULSE/B-roll Library and reused.
extension OnlineMusicLibrary {
    public static var brollFolder: URL { PulseDirectories.ensure(PulseDirectories.applicationSupport.appendingPathComponent("B-roll Library", isDirectory: true)) }
    static var brollIndexURL: URL { brollFolder.appendingPathComponent("broll.json") }

    public static var brollClips: [OnlineTrack] {
        let all = (try? JSONDecoder().decode([OnlineTrack].self, from: Data(contentsOf: brollIndexURL))) ?? []
        return all.filter { t in t.fileName.map { FileManager.default.fileExists(atPath: brollFolder.appendingPathComponent($0).path) } ?? false }
    }

    /// One downloaded clip for `query`, not one of `used` (video IDs). Falls back to a clip already in the
    /// library for the same search when YouTube can't be reached. Returns nil when there's nothing.
    public func brollClip(query: String, avoiding used: Set<String>, progress: (@Sendable (String) -> Void)? = nil) async -> (clip: OnlineTrack, url: URL)? {
        var library = Self.brollClips
        progress?("Searching Creative Commons clips (“\(query)”)")
        var candidates: [VideoSearchResult] = []
        do {
            candidates = try await search(query)
            PulseLog.info("B-roll search “\(query)”: \(candidates.count) results")
        } catch {
            PulseLog.warning("B-roll search failed: \(error.localizedDescription)")
        }
        let ranked = candidates.compactMap { r in BrollPlacer.score(r).map { (r, $0) } }.sorted { $0.1 > $1.1 }.map(\.0)
            .filter { !used.contains($0.videoID) }
        for result in ranked.prefix(4) {
            if let existing = library.first(where: { $0.videoID == result.videoID }), let name = existing.fileName {
                return (existing, Self.brollFolder.appendingPathComponent(name))
            }
            progress?("Downloading clip “\(result.title)”")
            do {
                let youtube = YouTube(videoID: result.videoID, methods: [.local])
                let streams = try await youtube.streams
                guard let stream = streams.filterVideoAndAudio().filter({ $0.fileExtension == .mp4 })
                    .filter(byResolution: { ($0 ?? 0) <= 720 }).highestResolutionStream() else {
                    throw EngineError.readerFailed("No MP4 stream with sound for \(result.videoID)")
                }
                let fileName = "\(result.videoID).mp4"
                let destination = Self.brollFolder.appendingPathComponent(fileName)
                try await rangedDownload(stream.url, to: destination)
                let clip = OnlineTrack(videoID: result.videoID, title: result.title, channel: result.channel, duration: result.duration ?? 0,
                                       mood: query, fileName: fileName)
                library.removeAll { $0.videoID == clip.videoID }
                library.append(clip)
                if let data = try? JSONEncoder().encode(library) { try? data.write(to: Self.brollIndexURL, options: .atomic) }
                PulseLog.info("B-roll library: downloaded “\(clip.title)” by \(clip.channel) (\(clip.videoID))")
                return (clip, destination)
            } catch {
                PulseLog.warning("B-roll download failed for \(result.videoID) (“\(result.title)”): \(error.localizedDescription)")
            }
        }
        // Offline or refused: something already downloaded for the same kind of moment.
        if let spare = library.first(where: { $0.mood == query && !used.contains($0.videoID) }) ?? library.first(where: { !used.contains($0.videoID) }),
           let name = spare.fileName {
            return (spare, Self.brollFolder.appendingPathComponent(name))
        }
        return nil
    }
}
