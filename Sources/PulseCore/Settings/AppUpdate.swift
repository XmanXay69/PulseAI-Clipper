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

/// Which releases the in-app updater offers (#454).
public enum UpdateChannel: String, Codable, CaseIterable, Sendable {
    case stable, beta

    public var displayName: String { self == .stable ? "Stable" : "Beta" }
    public var detail: String {
        switch self {
        case .stable: return "Only finished releases."
        case .beta: return "Pre-releases too — new features a week or two early, with the odd rough edge."
        }
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
    /// A GitHub pre-release (the beta channel, #454).
    public var prerelease: Bool = false

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

    /// Parses `GET /repos/{owner}/{repo}/releases/latest`. The build number comes from a `-build.N`
    /// tag suffix or the "Build N from" line PULSE's release notes carry.
    public static func parse(_ data: Data) -> ReleaseInfo? {
        guard let release = try? JSONDecoder().decode(Release.self, from: data), release.draft != true, release.prerelease != true else { return nil }
        return make(release)
    }

    /// Parses `GET /repos/{owner}/{repo}/releases` (newest version first); pre-releases only on request.
    public static func parseAll(_ data: Data, includePrereleases: Bool) -> [ReleaseInfo] {
        guard let releases = try? JSONDecoder().decode([Release].self, from: data) else { return [] }
        return releases.filter { $0.draft != true && (includePrereleases || $0.prerelease != true) }
            .compactMap(make).sorted { $0.version > $1.version }
    }

    /// The newest release the channel allows.
    public static func newest(in data: Data, channel: UpdateChannel) -> ReleaseInfo? {
        parseAll(data, includePrereleases: channel == .beta).first
    }

    /// Everything you've missed (#454): the notes of every release newer than `current`, newest first, each
    /// under its own heading when there's more than one.
    public static func missedNotes(_ releases: [ReleaseInfo], since current: AppVersion) -> String {
        let missed = releases.filter { $0.version > current }.sorted { $0.version > $1.version }
        if missed.count <= 1 { return missed.first?.whatsNew ?? "" }
        return missed.map { "**\($0.name)**\n\($0.whatsNew)" }.joined(separator: "\n\n")
    }

    static func make(_ release: Release) -> ReleaseInfo? {
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
                           pageURL: release.html_url, sizeBytes: dmg.size ?? 0, prerelease: release.prerelease == true)
    }

    /// Just the "what's new" part of the notes (drops the install instructions and build line).
    public var whatsNew: String {
        var text = notes
        if let install = text.range(of: "\n## Install") { text = String(text[..<install.lowerBound]) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
