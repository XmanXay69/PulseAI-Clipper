import AppKit
import CryptoKit
import Foundation
import PulseCore

/// The bridge to Thumbnail Studio (github.com/XmanXay69/ThumbnailStudio), a separate local app.
///
/// No plug-in or import step is needed on the studio's side: its gallery is a folder of design
/// JSON files that it re-reads whenever it comes to the front, and its images live in a
/// content-addressed folder next to it. PULSE writes frames and designs into those folders in
/// the studio's own format, then launches it with `--open <design name>`.
public enum ThumbnailStudioLink {
    public static let bundleIdentifier = "com.xavier.thumbstudio"
    public static let projectURL = URL(string: "https://github.com/XmanXay69/ThumbnailStudio#thumbnail-studio")!

    /// Where the studio keeps its files (shared with its VOD editor, hence the folder name).
    public static var supportRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VODEditor", isDirectory: true)
    }

    /// The studio's design gallery ("Thumb Lab").
    public static var designsFolder: URL { supportRoot.appendingPathComponent("ThumbLab", isDirectory: true) }
    /// Images the studio owns, named by content hash.
    public static var imagesFolder: URL { supportRoot.appendingPathComponent("ThumbAssets", isDirectory: true) }

    /// The installed app, found by bundle id (any location) or by name in the Applications folders.
    public static func appURL() -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) { return url }
        let home = FileManager.default.homeDirectoryForCurrentUser
        for candidate in ["/Applications/ThumbStudio.app", "/Applications/Thumbnail Studio.app",
                          home.appendingPathComponent("Applications/ThumbStudio.app").path] where FileManager.default.fileExists(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }
        return nil
    }

    public static var isInstalled: Bool { appURL() != nil }

    public enum LinkError: LocalizedError {
        case encodeFailed
        public var errorDescription: String? { "Couldn't save the frame as an image." }
    }

    /// Saves a frame where the studio keeps images, named the way it names them (first 10 bytes of
    /// the SHA-256, hex), so saving the same frame twice costs one file.
    public static func storeFrame(_ image: CGImage) throws -> URL {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) else { throw LinkError.encodeFailed }
        try FileManager.default.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: data).prefix(10).map { String(format: "%02x", $0) }.joined()
        let url = imagesFolder.appendingPathComponent(digest + ".jpg")
        if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
        return url
    }

    /// Writes a design into the gallery without overwriting one already there ("Name 2.json", …).
    @discardableResult
    public static func writeDesign(_ document: ThumbStudioDocument, named name: String) throws -> URL {
        try FileManager.default.createDirectory(at: designsFolder, withIntermediateDirectories: true)
        let stem = name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        var url = designsFolder.appendingPathComponent("\(stem.isEmpty ? "PULSE Thumbnail" : stem).json")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = designsFolder.appendingPathComponent("\(stem) \(suffix).json")
            suffix += 1
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: url, options: .atomic)
        return url
    }

    /// Opens the studio. A fresh launch goes straight into `design`; if it's already running it comes to
    /// the front and its gallery (newest first) shows the new designs at the top.
    @MainActor
    @discardableResult
    public static func open(design: URL?) async -> Bool {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            return running.activate()
        }
        guard let app = appURL() else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if let design { configuration.arguments = ["--open", design.deletingPathExtension().lastPathComponent] }
        do {
            _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
            return true
        } catch {
            PulseLog.warning("Couldn't open Thumbnail Studio: \(error.localizedDescription)")
            return false
        }
    }
}
