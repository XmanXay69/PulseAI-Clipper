import Foundation

public enum ProjectStoreError: Error, LocalizedError {
    case notAProject(URL)
    case corrupted(URL, underlying: String)
    case recoveredFromBackup(URL)
    case writeFailed(URL, underlying: String)
    case versionNotFound

    public var errorDescription: String? {
        switch self {
        case .notAProject(let url):
            return "“\(url.lastPathComponent)” isn't a PULSE project. PULSE projects end in .pulse."
        case .corrupted(let url, let underlying):
            return "“\(url.deletingPathExtension().lastPathComponent)” is damaged and no backup could be opened (\(underlying))."
        case .recoveredFromBackup(let url):
            return "“\(url.deletingPathExtension().lastPathComponent)” was damaged, so PULSE opened the most recent backup."
        case .writeFailed(let url, let underlying):
            return "PULSE couldn't save “\(url.deletingPathExtension().lastPathComponent)”: \(underlying). Check that the disk isn't full and the folder is writable."
        case .versionNotFound:
            return "That project version no longer exists."
        }
    }
}

/// On-disk layout of a `.pulse` project package.
public struct ProjectPackage: Hashable, Sendable {
    public static let fileExtension = "pulse"

    public var url: URL

    public init(url: URL) {
        self.url = url
    }

    public var name: String { url.deletingPathExtension().lastPathComponent }
    public var documentURL: URL { url.appendingPathComponent("project.json") }
    public var analysisDirectory: URL { url.appendingPathComponent("analysis", isDirectory: true) }
    public var versionsDirectory: URL { url.appendingPathComponent("versions", isDirectory: true) }
    public var backupsDirectory: URL { url.appendingPathComponent("backups", isDirectory: true) }
    public var thumbnailsDirectory: URL { url.appendingPathComponent("thumbnails", isDirectory: true) }

    public func analysisURL(assetID: UUID) -> URL {
        analysisDirectory.appendingPathComponent("\(assetID.uuidString).json")
    }
}

public struct ProjectVersion: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var number: Int
    public var label: String
    public var createdAt: Date
    public var fileName: String
}

/// Reads and writes project packages. Writes are atomic (temp file + replace) and every save
/// rotates a backup so a damaged file can always be recovered.
public final class ProjectStore: @unchecked Sendable {
    public let fileManager: FileManager
    public var backupsToKeep: Int

    public init(fileManager: FileManager = .default, backupsToKeep: Int = 10) {
        self.fileManager = fileManager
        self.backupsToKeep = backupsToKeep
    }

    /// Dates are stored as reference-date seconds (lossless round trip, unlike ISO-8601 strings).
    public static func makeEncoder(pretty: Bool = false) -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .deferredToDate
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return e
    }

    public static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .deferredToDate
        return d
    }

    // MARK: Create / open / save

    /// Creates a new, empty project package inside `directory`.
    public func create(name: String, in directory: URL) throws -> (ProjectPackage, ProjectDocument) {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let safe = ExportSettings.sanitize(name).isEmpty ? "Untitled Project" : ExportSettings.sanitize(name)
        var url = directory.appendingPathComponent("\(safe).\(ProjectPackage.fileExtension)", isDirectory: true)
        var n = 2
        while fileManager.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(safe) \(n).\(ProjectPackage.fileExtension)", isDirectory: true)
            n += 1
        }
        let package = ProjectPackage(url: url)
        try makeDirectories(package)
        let document = ProjectDocument(name: name)
        try save(document, to: package, makeBackup: false)
        return (package, document)
    }

    func makeDirectories(_ package: ProjectPackage) throws {
        for dir in [package.url, package.analysisDirectory, package.versionsDirectory, package.backupsDirectory, package.thumbnailsDirectory] {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Loads a project. If `project.json` is damaged, falls back to the newest readable backup and
    /// reports it through `recoveredFromBackup` (the document is still returned).
    public func load(_ package: ProjectPackage) throws -> (document: ProjectDocument, recoveredFromBackup: Bool) {
        guard package.url.pathExtension == ProjectPackage.fileExtension else { throw ProjectStoreError.notAProject(package.url) }
        do {
            let data = try Data(contentsOf: package.documentURL)
            return (try ProjectStore.makeDecoder().decode(ProjectDocument.self, from: data), false)
        } catch {
            for backup in backups(of: package) {
                if let data = try? Data(contentsOf: backup),
                   let doc = try? ProjectStore.makeDecoder().decode(ProjectDocument.self, from: data) {
                    return (doc, true)
                }
            }
            throw ProjectStoreError.corrupted(package.url, underlying: error.localizedDescription)
        }
    }

    /// Atomically writes the document, rotating the previous file into `backups/`.
    public func save(_ document: ProjectDocument, to package: ProjectPackage, makeBackup: Bool = true) throws {
        do {
            try makeDirectories(package)
            if makeBackup, fileManager.fileExists(atPath: package.documentURL.path) {
                try rotateBackup(package)
            }
            let data = try ProjectStore.makeEncoder().encode(document)
            try data.write(to: package.documentURL, options: .atomic)
        } catch let error as ProjectStoreError {
            throw error
        } catch {
            throw ProjectStoreError.writeFailed(package.url, underlying: error.localizedDescription)
        }
    }

    func rotateBackup(_ package: ProjectPackage) throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let target = package.backupsDirectory.appendingPathComponent("project-\(formatter.string(from: Date())).json")
        if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
        try fileManager.copyItem(at: package.documentURL, to: target)
        let all = backups(of: package)
        if all.count > backupsToKeep {
            for old in all.suffix(from: backupsToKeep) { try? fileManager.removeItem(at: old) }
        }
    }

    /// Backups newest first.
    public func backups(of package: ProjectPackage) -> [URL] {
        let files = (try? fileManager.contentsOfDirectory(at: package.backupsDirectory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    // MARK: Analysis

    public func saveAnalysis(_ analysis: MediaAnalysis, in package: ProjectPackage) throws {
        try fileManager.createDirectory(at: package.analysisDirectory, withIntermediateDirectories: true)
        let data = try ProjectStore.makeEncoder().encode(analysis)
        try data.write(to: package.analysisURL(assetID: analysis.assetID), options: .atomic)
    }

    public func loadAnalysis(assetID: UUID, in package: ProjectPackage) -> MediaAnalysis? {
        guard let data = try? Data(contentsOf: package.analysisURL(assetID: assetID)) else { return nil }
        return try? ProjectStore.makeDecoder().decode(MediaAnalysis.self, from: data)
    }

    // MARK: Versions

    public func versions(of package: ProjectPackage) -> [ProjectVersion] {
        let index = package.versionsDirectory.appendingPathComponent("index.json")
        guard let data = try? Data(contentsOf: index),
              let list = try? ProjectStore.makeDecoder().decode([ProjectVersion].self, from: data) else { return [] }
        return list.sorted { $0.number > $1.number }
    }

    /// Saves a named snapshot ("Project Version 3").
    @discardableResult
    public func createVersion(of document: ProjectDocument, in package: ProjectPackage, label: String? = nil) throws -> ProjectVersion {
        try fileManager.createDirectory(at: package.versionsDirectory, withIntermediateDirectories: true)
        var list = versions(of: package)
        let number = (list.map(\.number).max() ?? 0) + 1
        let version = ProjectVersion(id: UUID(), number: number, label: label ?? "Version \(number)", createdAt: Date(), fileName: "v\(String(format: "%04d", number)).json")
        let data = try ProjectStore.makeEncoder().encode(document)
        try data.write(to: package.versionsDirectory.appendingPathComponent(version.fileName), options: .atomic)
        list.append(version)
        let indexData = try ProjectStore.makeEncoder(pretty: true).encode(list.sorted { $0.number < $1.number })
        try indexData.write(to: package.versionsDirectory.appendingPathComponent("index.json"), options: .atomic)
        return version
    }

    public func loadVersion(_ version: ProjectVersion, in package: ProjectPackage) throws -> ProjectDocument {
        let url = package.versionsDirectory.appendingPathComponent(version.fileName)
        guard let data = try? Data(contentsOf: url) else { throw ProjectStoreError.versionNotFound }
        return try ProjectStore.makeDecoder().decode(ProjectDocument.self, from: data)
    }

    /// Copies a project package (for "Duplicate before experimenting").
    public func duplicate(_ package: ProjectPackage, newName: String) throws -> ProjectPackage {
        let directory = package.url.deletingLastPathComponent()
        var target = directory.appendingPathComponent("\(ExportSettings.sanitize(newName)).\(ProjectPackage.fileExtension)", isDirectory: true)
        var n = 2
        while fileManager.fileExists(atPath: target.path) {
            target = directory.appendingPathComponent("\(ExportSettings.sanitize(newName)) \(n).\(ProjectPackage.fileExtension)", isDirectory: true)
            n += 1
        }
        try fileManager.copyItem(at: package.url, to: target)
        let copy = ProjectPackage(url: target)
        var (document, _) = try load(copy)
        document.id = UUID()
        document.name = newName
        document.createdAt = Date()
        document.touch()
        try save(document, to: copy, makeBackup: false)
        return copy
    }

    /// Finds `.pulse` packages in a folder (non-recursive) and summarises them.
    public func listProjects(in directory: URL) -> [ProjectSummary] {
        let urls = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.filter { $0.pathExtension == ProjectPackage.fileExtension }.compactMap { url in
            let package = ProjectPackage(url: url)
            guard let loaded = try? load(package) else { return nil }
            let doc = loaded.document
            var summary = doc.summary
            summary.path = url.path
            if let thumb = doc.thumbnailPath { summary.thumbnailPath = url.appendingPathComponent(thumb).path }
            return summary
        }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// Bytes used by a directory tree.
    public func diskUsage(of url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }
}

// MARK: - Crash recovery

public struct RecoverySnapshot: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID { document.id }
    public var projectPath: String
    public var savedAt: Date
    public var document: ProjectDocument
}

/// Keeps unsaved changes safe between autosaves. A snapshot exists only while a project has
/// unsaved edits; a clean save deletes it. Any snapshot found at launch therefore means PULSE
/// quit unexpectedly and offers "Recovered Project — Open / Discard".
public final class RecoveryManager: @unchecked Sendable {
    public let directory: URL
    let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    var lockURL: URL { directory.appendingPathComponent("session.lock") }

    /// Marks the session as running. Returns true if the previous session didn't end cleanly.
    @discardableResult
    public func beginSession() -> Bool {
        let crashed = fileManager.fileExists(atPath: lockURL.path)
        let info = "pid=\(ProcessInfo.processInfo.processIdentifier) started=\(ISO8601DateFormatter().string(from: Date()))"
        try? Data(info.utf8).write(to: lockURL, options: .atomic)
        return crashed
    }

    public func endSession() {
        try? fileManager.removeItem(at: lockURL)
    }

    func snapshotURL(_ projectID: UUID) -> URL {
        directory.appendingPathComponent("\(projectID.uuidString).recovery.json")
    }

    public func writeSnapshot(_ document: ProjectDocument, projectPath: String) throws {
        let snapshot = RecoverySnapshot(projectPath: projectPath, savedAt: Date(), document: document)
        let data = try ProjectStore.makeEncoder().encode(snapshot)
        try data.write(to: snapshotURL(document.id), options: .atomic)
    }

    public func clearSnapshot(projectID: UUID) {
        try? fileManager.removeItem(at: snapshotURL(projectID))
    }

    public func pendingRecoveries() -> [RecoverySnapshot] {
        let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasSuffix(".recovery.json") }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? ProjectStore.makeDecoder().decode(RecoverySnapshot.self, from: data)
        }.sorted { $0.savedAt > $1.savedAt }
    }

    public func discard(_ snapshot: RecoverySnapshot) {
        clearSnapshot(projectID: snapshot.document.id)
    }
}
