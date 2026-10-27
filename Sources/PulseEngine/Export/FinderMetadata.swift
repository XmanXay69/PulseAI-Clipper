import Foundation

/// Finder's own metadata on a file (#465): the comment shown in Get Info and indexed by Spotlight, and the
/// "where from" list. Both live in extended attributes as binary property lists.
public enum FinderMetadata {
    static let commentAttribute = "com.apple.metadata:kMDItemFinderComment"
    static let whereFromsAttribute = "com.apple.metadata:kMDItemWhereFroms"

    /// Stamps the Finder comment on `url` (replacing any existing one).
    public static func setComment(_ comment: String, for url: URL) throws {
        try write(plist: comment, attribute: commentAttribute, to: url)
    }

    /// The Finder comment on `url`, if any.
    public static func comment(for url: URL) -> String? {
        read(attribute: commentAttribute, from: url) as? String
    }

    /// Records where a file came from (Finder shows it under "Where from").
    public static func setWhereFroms(_ sources: [String], for url: URL) throws {
        try write(plist: sources, attribute: whereFromsAttribute, to: url)
    }

    static func write(plist object: Any, attribute: String, to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
        let result = data.withUnsafeBytes { bytes -> Int32 in
            url.withUnsafeFileSystemRepresentation { path in
                guard let path else { return -1 }
                return setxattr(path, attribute, bytes.baseAddress, data.count, 0, 0)
            }
        }
        if result != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    static func read(attribute: String, from url: URL) -> Any? {
        url.withUnsafeFileSystemRepresentation { path -> Any? in
            guard let path else { return nil }
            let length = getxattr(path, attribute, nil, 0, 0, 0)
            guard length > 0 else { return nil }
            var buffer = [UInt8](repeating: 0, count: length)
            let got = getxattr(path, attribute, &buffer, length, 0, 0)
            guard got > 0 else { return nil }
            return try? PropertyListSerialization.propertyList(from: Data(buffer[0..<got]), options: [], format: nil)
        }
    }
}
