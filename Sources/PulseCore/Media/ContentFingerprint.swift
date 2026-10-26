import Foundation

/// A cheap fingerprint of a media file's content (#5): FNV-1a over the first and last megabyte plus the size.
/// The same recording under two names hashes the same; a re-encode doesn't. Reads 2 MB of a 50 GB VOD.
public enum ContentFingerprint {
    public static func compute(url: URL, window: Int = 1 << 20) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        var hasher = Hasher64()
        try handle.seek(toOffset: 0)
        hasher.mix(try handle.read(upToCount: window) ?? Data())
        if size > UInt64(window) {
            try handle.seek(toOffset: size - UInt64(window))
            hasher.mix(try handle.read(upToCount: window) ?? Data())
        }
        hasher.mix(size)
        return hasher.hex
    }

    /// The same fingerprint for data already in memory (tests, small files).
    public static func compute(data: Data, window: Int = 1 << 20) -> String {
        var hasher = Hasher64()
        hasher.mix(data.prefix(window))
        if data.count > window { hasher.mix(data.suffix(window)) }
        hasher.mix(UInt64(data.count))
        return hasher.hex
    }

    struct Hasher64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325

        mutating func mix<D: Sequence>(_ bytes: D) where D.Element == UInt8 {
            for b in bytes {
                hash ^= UInt64(b)
                hash = hash &* 0x0000_0100_0000_01b3
            }
        }

        mutating func mix(_ value: UInt64) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { mix($0) }
        }

        var hex: String { String(format: "%016llx", hash) }
    }
}
