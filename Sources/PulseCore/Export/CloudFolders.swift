import Foundation

/// Synced folders on this Mac to export straight into (#356): iCloud Drive, Dropbox, Google Drive, OneDrive.
public enum CloudFolders {
    public struct Folder: Hashable, Sendable {
        public var name: String
        public var path: String
        public init(name: String, path: String) { self.name = name; self.path = path }
    }

    /// The ones that exist, in a fixed order. `list` returns the names inside a directory (for the
    /// `Library/CloudStorage` providers, whose folders carry the account name).
    public static func detect(home: String = NSHomeDirectory(),
                              exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                              list: (String) -> [String] = { (try? FileManager.default.contentsOfDirectory(atPath: $0)) ?? [] }) -> [Folder] {
        var out: [Folder] = []
        let icloud = home + "/Library/Mobile Documents/com~apple~CloudDocs"
        if exists(icloud) { out.append(Folder(name: "iCloud Drive", path: icloud)) }
        let storage = home + "/Library/CloudStorage"
        let providers = exists(storage) ? list(storage).sorted() : []
        for entry in providers {
            let path = storage + "/" + entry
            if entry.hasPrefix("Dropbox") { out.append(Folder(name: "Dropbox", path: path)) }
            else if entry.hasPrefix("GoogleDrive") { out.append(Folder(name: "Google Drive" + account(entry, prefix: "GoogleDrive"), path: path)) }
            else if entry.hasPrefix("OneDrive") { out.append(Folder(name: "OneDrive" + account(entry, prefix: "OneDrive"), path: path)) }
            else if entry.hasPrefix("Box") { out.append(Folder(name: "Box", path: path)) }
        }
        if !out.contains(where: { $0.name == "Dropbox" }), exists(home + "/Dropbox") { out.append(Folder(name: "Dropbox", path: home + "/Dropbox")) }
        if !out.contains(where: { $0.name.hasPrefix("OneDrive") }), exists(home + "/OneDrive") { out.append(Folder(name: "OneDrive", path: home + "/OneDrive")) }
        return out
    }

    /// "GoogleDrive-me@gmail.com" → " (me@gmail.com)"; "" when there's no account part.
    static func account(_ entry: String, prefix: String) -> String {
        let rest = entry.dropFirst(prefix.count).trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))
        return rest.isEmpty ? "" : " (\(rest))"
    }
}
