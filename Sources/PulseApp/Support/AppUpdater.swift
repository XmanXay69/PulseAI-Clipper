import AppKit
import CryptoKit
import Foundation
import PulseCore
import PulseEngine

/// Updates PULSE from inside the app: checks the latest GitHub release, downloads the DMG, verifies
/// its SHA-256, swaps the app in place and relaunches. Projects, settings and downloaded caption
/// models live in Application Support, outside the app, so they're kept.
@MainActor
final class AppUpdater: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case downloading(ReleaseInfo, Double)
        case installing(ReleaseInfo)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published var showSheet = false
    static let latestURL = URL(string: "https://api.github.com/repos/XmanXay69/PulseAI-Clipper/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/XmanXay69/PulseAI-Clipper/releases/latest")!
    private var downloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?

    var current: AppVersion {
        let info = Bundle.main.infoDictionary
        return AppVersion(info?["CFBundleShortVersionString"] as? String ?? "0", build: Int(info?["CFBundleVersion"] as? String ?? "") ?? 0)
    }

    var available: ReleaseInfo? {
        switch state {
        case .available(let r), .downloading(let r, _), .installing(let r): return r
        default: return nil
        }
    }

    /// Only a real app bundle can replace itself (not `swift run`).
    var canInstall: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    var autoCheck: Bool {
        get { UserDefaults.standard.object(forKey: "updates.autoCheck") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "updates.autoCheck"); objectWillChange.send() }
    }

    /// At launch: once a day, quietly.
    func checkOnLaunch() {
        guard autoCheck, canInstall else { return }
        let last = UserDefaults.standard.object(forKey: "updates.lastCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 20 * 3600 else { return }
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        if case .downloading = state { return }
        if case .installing = state { return }
        state = .checking
        UserDefaults.standard.set(Date(), forKey: "updates.lastCheck")
        var request = URLRequest(url: Self.latestURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PULSE/\(current)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let release = ReleaseInfo.parse(data) else {
                state = userInitiated ? .failed("Couldn't read the latest release from GitHub.") : .idle
                return
            }
            if current < release.version {
                state = .available(release)
                PulseLog.info("Update available: \(release.version) build \(release.version.build) (running \(current) build \(current.build))")
            } else {
                state = userInitiated ? .upToDate : .idle
            }
        } catch {
            state = userInitiated ? .failed("Couldn't reach GitHub: \(error.localizedDescription)") : .idle
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        if let r = available { state = .available(r) }
    }

    /// Download → verify → mount → copy beside the current app → swap after quitting → relaunch.
    func install() async {
        guard let release = available, canInstall else { return }
        let appURL = Bundle.main.bundleURL
        if appURL.path.contains("/AppTranslocation/") {
            state = .failed("Move PULSE into your Applications folder first (drag it there from the disk image), open it from there, then update.")
            return
        }
        let parent = appURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            state = .failed("PULSE can't write to \(parent.path). Download the new version from GitHub instead.")
            return
        }
        state = .downloading(release, 0)
        do {
            let dmg = try await download(release.dmgURL, release: release)
            if let checksumURL = release.checksumURL {
                let (data, _) = try await URLSession.shared.data(from: checksumURL)
                let expected = String(decoding: data, as: UTF8.self).split(whereSeparator: { $0.isWhitespace }).first.map(String.init)?.lowercased() ?? ""
                let actual = try Self.sha256(of: dmg)
                guard !expected.isEmpty, expected == actual else {
                    throw UpdateError("The download didn't match its checksum — nothing was changed. Try again.")
                }
            }
            state = .installing(release)
            let staged = parent.appendingPathComponent(".PULSE-update-\(release.version.build).app")
            try await Task.detached(priority: .userInitiated) { try Self.stage(dmg: dmg, to: staged) }.value
            try? FileManager.default.removeItem(at: dmg)
            PulseLog.info("Update \(release.version) staged at \(staged.path); relaunching")
            PulseLog.flush()
            try Self.swapAndRelaunch(staged: staged, target: appURL)
            NSApp.terminate(nil)
        } catch is CancellationError {
            state = .available(release)
        } catch let error as UpdateError {
            state = .failed(error.message)
        } catch {
            if (error as NSError).code == NSURLErrorCancelled { state = .available(release); return }
            PulseLog.error("Update failed: \(error.localizedDescription)")
            state = .failed("The update couldn't be installed: \(error.localizedDescription)")
        }
    }

    struct UpdateError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    private func download(_ url: URL, release: ReleaseInfo) async throws -> URL {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("PULSE-update-\(UUID().uuidString).dmg")
        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: url) { location, response, error in
                if let error { continuation.resume(throwing: error); return }
                guard let location, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    continuation.resume(throwing: UpdateError("GitHub didn't send the update file."))
                    return
                }
                do {
                    try FileManager.default.moveItem(at: location, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                let fraction = progress.fractionCompleted
                Task { @MainActor in
                    guard let self, case .downloading(let r, _) = self.state else { return }
                    self.state = .downloading(r, fraction)
                }
            }
            downloadTask = task
            task.resume()
        }
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Mounts the DMG, copies PULSE.app out next to the current app, unmounts.
    nonisolated static func stage(dmg: URL, to staged: URL) throws {
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("PULSE-update-mount-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path])
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        guard let app = try FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError("The disk image didn't contain PULSE.app.")
        }
        try? FileManager.default.removeItem(at: staged)
        try run("/usr/bin/ditto", [app.path, staged.path])
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
    }

    /// A tiny helper script waits for PULSE to quit, swaps the bundles, and opens the new one.
    static func swapAndRelaunch(staged: URL, target: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let backup = target.deletingLastPathComponent().appendingPathComponent(".PULSE-previous.app")
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf \(q(backup.path))
        mv \(q(target.path)) \(q(backup.path)) && mv \(q(staged.path)) \(q(target.path)) || { rm -rf \(q(target.path)); mv \(q(backup.path)) \(q(target.path)); }
        rm -rf \(q(backup.path))
        open \(q(target.path))
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    @discardableResult
    nonisolated static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError("\((tool as NSString).lastPathComponent) failed: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return output
    }
}
