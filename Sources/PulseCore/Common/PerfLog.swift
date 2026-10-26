import Foundation

/// How long things took on this Mac (#395): the last 200 jobs, kept in memory and written into a bug
/// report. Nothing leaves the Mac on its own.
public enum PerfLog {
    public struct Entry: Hashable, Sendable {
        public var label: String
        public var seconds: Double
        public var at: Date
        public init(label: String, seconds: Double, at: Date = Date()) { self.label = label; self.seconds = seconds; self.at = at }
    }

    public static let capacity = 200
    private static let lock = NSLock()
    nonisolated(unsafe) private static var storage: [Entry] = []

    public static func record(_ label: String, seconds: Double, at: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        storage.append(Entry(label: label, seconds: max(0, seconds), at: at))
        if storage.count > capacity { storage.removeFirst(storage.count - capacity) }
    }

    public static var entries: [Entry] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    public static func clear() {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll()
    }

    /// One line per entry, newest last: "21:04:12  Export 9:16 short  38.2 s".
    public static func text(limit: Int = capacity) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return entries.suffix(limit).map { String(format: "%@  %@  %.1f s", formatter.string(from: $0.at), $0.label, $0.seconds) }.joined(separator: "\n")
    }
}
