import Foundation
import PulseCore

/// A YouTube VOD by link (#1, #467), the way the B-roll and music libraries fetch clips: YouTube's own
/// progressive MP4 with sound, saved under ~/Movies/PULSE Downloads and imported like any recording.
public enum VODDownloader {
    public static var downloadsFolder: URL {
        (FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("PULSE Downloads", isDirectory: true)
    }

    public static func download(videoID: String, into folder: URL = downloadsFolder, progress: (@Sendable (String) -> Void)? = nil) async throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent("\(videoID).mp4")
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        progress?("Finding the video stream")
        let youtube = YouTube(videoID: videoID, methods: [.local])
        let streams = try await youtube.streams
        guard let stream = streams.filterVideoAndAudio().filter({ $0.fileExtension == .mp4 }).highestResolutionStream() else {
            throw EngineError.readerFailed("No MP4 stream with sound for \(videoID) — PULSE can only fetch what YouTube serves as one file (usually 720p)")
        }
        progress?("Downloading \(videoID)")
        try await OnlineMusicLibrary.shared.rangedDownload(stream.url, to: destination)
        PulseLog.info("VOD download: \(videoID) → \(destination.lastPathComponent)")
        return destination
    }
}
