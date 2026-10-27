import Foundation
import PulseCore
import YouTubeKit

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
        // Hours of video, so the pieces go straight to disk, with the size and percentage as they land.
        let reported = ProgressGate()
        try await OnlineMusicLibrary.shared.downloadLarge(stream.url, to: destination) { done, total in
            guard let progress, reported.shouldReport(done, of: total) else { return }
            let percent = Int(Double(done) / Double(max(total, 1)) * 100)
            progress("Downloading \(videoID) — \(percent)% of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
        }
        PulseLog.info("VOD download: \(videoID) → \(destination.lastPathComponent)")
        return destination
    }

    /// Reports once per whole percent, not once per megabyte.
    private final class ProgressGate: @unchecked Sendable {
        private let lock = NSLock()
        private var last = -1
        func shouldReport(_ done: Int64, of total: Int64) -> Bool {
            let percent = Int(Double(done) / Double(max(total, 1)) * 100)
            lock.lock(); defer { lock.unlock() }
            guard percent != last else { return false }
            last = percent
            return true
        }
    }
}
