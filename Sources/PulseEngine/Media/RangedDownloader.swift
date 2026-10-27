import Foundation
import PulseCore

/// Downloads a file as parallel 1 MiB ranged requests (one YouTube connection is throttled to ~1 MB/s), each
/// piece written straight into the file at its offset, so a multi-gigabyte VOD costs a few megabytes of memory.
/// Pieces are retried three times; the task's cancellation stops every request and removes the partial file.
public enum RangedDownloader {
    public static let pieceSize: Int64 = 1 << 20
    public static let parallelism = 4

    /// `maxBytes` guards against a stream that isn't what was asked for; `progress` is bytes done of total.
    public static func download(_ url: URL, to destination: URL, session: URLSession, userAgent: String, maxBytes: Int64,
                                progress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws {
        var probe = URLRequest(url: url)
        probe.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        probe.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let (_, probeResponse) = try await session.data(for: probe)
        guard let http = probeResponse as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw EngineError.readerFailed("Download refused")
        }
        var total: Int64 = 0
        if let range = http.value(forHTTPHeaderField: "Content-Range"), let last = range.split(separator: "/").last { total = Int64(last) ?? 0 }
        guard total > 0 else { throw EngineError.readerFailed("Unexpected file size") }
        guard total <= maxBytes else {
            throw EngineError.readerFailed("The file is \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)), more than the \(ByteCountFormatter.string(fromByteCount: maxBytes, countStyle: .file)) limit")
        }
        try DiskSpace.ensure(total + Int64(64 << 20), at: destination.deletingLastPathComponent())

        let temp = destination.appendingPathExtension("part")
        try? FileManager.default.removeItem(at: temp)
        guard FileManager.default.createFile(atPath: temp.path, contents: nil) else { throw EngineError.readerFailed("Couldn't create \(temp.lastPathComponent)") }
        let handle = try FileHandle(forWritingTo: temp)
        let sink = FileSink(handle)
        do {
            try sink.reserve(total)
            let ranges = stride(from: Int64(0), to: total, by: Int(pieceSize)).map { ($0, min($0 + pieceSize, total) - 1) }
            try await withThrowingTaskGroup(of: Int64.self) { group in
                var done: Int64 = 0
                func collect() async throws {
                    if let bytes = try await group.next() {
                        done += bytes
                        progress?(done, total)
                    }
                }
                for (i, r) in ranges.enumerated() {
                    if i >= parallelism { try await collect() }
                    group.addTask {
                        var request = URLRequest(url: url)
                        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                        request.setValue("bytes=\(r.0)-\(r.1)", forHTTPHeaderField: "Range")
                        let wanted = r.1 - r.0 + 1
                        for attempt in 0..<3 {
                            try Task.checkCancellation()
                            if let reply = try? await session.data(for: request),
                               (reply.1 as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) == true,
                               Int64(reply.0.count) == wanted {
                                try sink.write(reply.0, at: r.0)
                                return wanted
                            }
                            try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 500_000_000)
                        }
                        throw EngineError.readerFailed("Download interrupted")
                    }
                }
                while !group.isEmpty { try await collect() }
            }
            try sink.close()
        } catch {
            try? sink.close()
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
    }

    /// Serializes writes to one file handle from the download's parallel pieces.
    private final class FileSink: @unchecked Sendable {
        private let handle: FileHandle
        private let lock = NSLock()
        init(_ handle: FileHandle) { self.handle = handle }

        func reserve(_ bytes: Int64) throws {
            lock.lock(); defer { lock.unlock() }
            try handle.truncate(atOffset: UInt64(bytes))
        }

        func write(_ data: Data, at offset: Int64) throws {
            lock.lock(); defer { lock.unlock() }
            try handle.seek(toOffset: UInt64(offset))
            try handle.write(contentsOf: data)
        }

        func close() throws {
            lock.lock(); defer { lock.unlock() }
            try handle.close()
        }
    }
}
