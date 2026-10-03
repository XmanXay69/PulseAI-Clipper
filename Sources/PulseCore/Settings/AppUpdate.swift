import Foundation

/// "1.1.0" + build 80, comparable — what the in-app updater uses to decide if a release is newer.
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public var parts: [Int]
    public var build: Int

    public init(_ version: String, build: Int = 0) {
        let cleaned = version.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let core = cleaned.split(separator: "-").first.map(String.init) ?? cleaned
        parts = core.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        while parts.count < 3 { parts.append(0) }
        self.build = build
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        for (x, y) in zip(a.parts, b.parts) where x != y { return x < y }
        if a.parts.count != b.parts.count { return a.parts.count < b.parts.count }
        return a.build < b.build
    }
}

/// The parts of a GitHub release the updater needs.
public struct ReleaseInfo: Hashable, Sendable {
    public var tag: String
    public var name: String
    public var notes: String
    public var version: AppVersion
    public var dmgURL: URL
    public var checksumURL: URL?
    public var pageURL: URL?
    public var sizeBytes: Int64

    /// Parses `GET /repos/{owner}/{repo}/releases/latest`. The build number comes from a `-build.N`
    /// tag suffix or the "Build N from" line PULSE's release notes carry.
    public static func parse(_ data: Data) -> ReleaseInfo? {
        struct Asset: Decodable { let name: String; let browser_download_url: URL; let size: Int64? }
        struct Release: Decodable {
            let tag_name: String
            let name: String?
            let body: String?
            let html_url: URL?
            let draft: Bool?
            let prerelease: Bool?
            let assets: [Asset]
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: data), release.draft != true, release.prerelease != true else { return nil }
        let dmg = release.assets.first { $0.name == "PULSE.dmg" } ?? release.assets.first { $0.name.hasSuffix(".dmg") }
        guard let dmg else { return nil }
        let body = release.body ?? ""
        var build = 0
        if let range = release.tag_name.range(of: "build.") { build = Int(release.tag_name[range.upperBound...].filter(\.isNumber)) ?? 0 }
        if build == 0, let match = body.range(of: #"Build (\d+)"#, options: .regularExpression) {
            build = Int(body[match].filter(\.isNumber)) ?? 0
        }
        return ReleaseInfo(tag: release.tag_name, name: release.name ?? release.tag_name, notes: body,
                           version: AppVersion(release.tag_name, build: build), dmgURL: dmg.browser_download_url,
                           checksumURL: release.assets.first { $0.name == "\(dmg.name).sha256" }?.browser_download_url,
                           pageURL: release.html_url, sizeBytes: dmg.size ?? 0)
    }

    /// Just the "what's new" part of the notes (drops the install instructions and build line).
    public var whatsNew: String {
        var text = notes
        if let install = text.range(of: "\n## Install") { text = String(text[..<install.lowerBound]) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
