import Foundation

/// A small on-disk log (~/Library/Logs/PULSE/pulse.log) of what the app did: launches, jobs, failures,
/// exports, warnings. It never contains media, transcripts or API keys. "Report a Problem" bundles it.
public enum PulseLog {
    public enum Level: String, Sendable { case info = "INFO", warning = "WARN", error = "ERROR" }

    public static var directory: URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return PulseDirectories.ensure(base.appendingPathComponent("Logs/PULSE", isDirectory: true))
    }

    public static var fileURL: URL { directory.appendingPathComponent("pulse.log") }
    /// The previous log, kept after rotation.
    public static var previousFileURL: URL { directory.appendingPathComponent("pulse.1.log") }
    static let maximumBytes = 2_000_000

    private static let queue = DispatchQueue(label: "app.pulse.log")
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public static func info(_ message: String) { write(.info, message) }
    public static func warning(_ message: String) { write(.warning, message) }
    public static func error(_ message: String) { write(.error, message) }

    public static func write(_ level: Level, _ message: String) {
        let line = "\(formatter.string(from: Date())) [\(level.rawValue)] \(message.replacingOccurrences(of: "\n", with: " ⏎ "))\n"
        queue.async {
            let url = fileURL
            let fm = FileManager.default
            if let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue, size > maximumBytes {
                try? fm.removeItem(at: previousFileURL)
                try? fm.moveItem(at: url, to: previousFileURL)
            }
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }

    /// Waits for pending writes (before bundling a report).
    public static func flush() { queue.sync {} }

    /// The last `count` lines (for showing in the report sheet).
    public static func tail(_ count: Int = 200) -> [String] {
        flush()
        let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        return Array(text.split(separator: "\n", omittingEmptySubsequences: true).suffix(count).map(String.init))
    }
}
