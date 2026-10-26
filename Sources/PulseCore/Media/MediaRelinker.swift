import Foundation

/// Finds moved files for missing media (#6, #7): the same file name wins; when several files share it, the
/// one with the recorded size does. Pure matching — the app lists the folders.
public enum MediaRelinker {
    public struct Candidate: Hashable, Sendable {
        public var path: String
        public var size: Int64
        public init(path: String, size: Int64) { self.path = path; self.size = size }
    }

    /// Asset id → the path to relink to, for every missing asset that has a match.
    public static func matches(missing: [MediaAsset], files: [Candidate]) -> [UUID: String] {
        var byName: [String: [Candidate]] = [:]
        for file in files { byName[(file.path as NSString).lastPathComponent.lowercased(), default: []].append(file) }
        var out: [UUID: String] = [:]
        for asset in missing {
            let name = (asset.path as NSString).lastPathComponent.lowercased()
            guard let options = byName[name], !options.isEmpty else { continue }
            let size = asset.metadata.fileSize
            let pick = (size > 0 ? options.first { $0.size == size } : nil) ?? options.first { $0.path != asset.path } ?? options[0]
            out[asset.id] = pick.path
        }
        return out
    }

    /// Where to look before asking (#6): the file's old folder and its parent, the project's own folder and
    /// its parent, and the folder you last imported from — nearest first, no repeats.
    public static func searchRoots(for asset: MediaAsset, projectFolder: String?, lastImportFolder: String?) -> [String] {
        var roots: [String] = []
        func add(_ path: String?) {
            guard let path, !path.isEmpty, path != "/" else { return }
            let standard = (path as NSString).standardizingPath
            if !roots.contains(standard) { roots.append(standard) }
        }
        let old = (asset.path as NSString).deletingLastPathComponent
        add(old)
        add((old as NSString).deletingLastPathComponent)
        add(projectFolder)
        add(projectFolder.map { ($0 as NSString).deletingLastPathComponent })
        add(lastImportFolder)
        return roots
    }
}
