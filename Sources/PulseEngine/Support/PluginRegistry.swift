import Foundation
import PulseCore

/// The plugins on this Mac (#495): every folder under Application Support/PULSE/Plugins with a plugin.json.
/// Effects are read by the renderer on its own thread, so lookups take a lock instead of an actor hop.
public final class PluginRegistry: @unchecked Sendable {
    public static let shared = PluginRegistry()

    public struct Loaded: Identifiable, Hashable, Sendable {
        public var manifest: PluginManifest
        public var folder: URL
        public var problems: [String]
        public var id: String { manifest.id }
        public var isUsable: Bool { problems.isEmpty }
    }

    public static var folder: URL {
        PulseDirectories.ensure(PulseDirectories.applicationSupport.appendingPathComponent("Plugins", isDirectory: true))
    }

    private let lock = NSLock()
    private var loaded: [Loaded] = []
    private var byID: [String: Loaded] = [:]

    public init() { reload() }

    /// Scans the plugins folder again.
    public func reload() {
        var found: [Loaded] = []
        let fm = FileManager.default
        if let items = try? fm.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: [.isDirectoryKey]) {
            for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let manifestURL = item.appendingPathComponent(PluginLoader.manifestName)
                guard let data = try? Data(contentsOf: manifestURL) else { continue }
                guard let manifest = PluginLoader.parse(data) else {
                    found.append(Loaded(manifest: PluginManifest(id: item.lastPathComponent, name: item.lastPathComponent, kind: .effect), folder: item,
                                        problems: ["plugin.json isn't valid"]))
                    continue
                }
                var problems = PluginLoader.problems(in: manifest)
                if manifest.kind == .signal, let command = manifest.command?.first, !fm.isExecutableFile(atPath: Self.resolve(command, in: item).path) {
                    problems.append("the command “\(command)” isn't an executable file in the plugin's folder")
                }
                found.append(Loaded(manifest: manifest, folder: item, problems: problems))
            }
        }
        lock.lock()
        loaded = found
        byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        lock.unlock()
        PulseLog.info("Plugins: \(found.count) found, \(found.filter(\.isUsable).count) usable")
    }

    public var all: [Loaded] {
        lock.lock(); defer { lock.unlock() }
        return loaded
    }

    public var effects: [PluginManifest] { all.filter { $0.isUsable && $0.manifest.kind == .effect }.map(\.manifest) }
    public var signals: [Loaded] { all.filter { $0.isUsable && $0.manifest.kind == .signal } }

    public func manifest(id: String) -> PluginManifest? {
        lock.lock(); defer { lock.unlock() }
        return byID[id].flatMap { $0.isUsable ? $0.manifest : nil }
    }

    static func resolve(_ command: String, in folder: URL) -> URL {
        command.hasPrefix("/") ? URL(fileURLWithPath: command) : folder.appendingPathComponent(command)
    }

    /// Writes the two example plugins when the folder is empty, so the format is there to copy.
    public func writeExamples() throws {
        let fm = FileManager.default
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let effectFolder = Self.folder.appendingPathComponent("Warm Glow", isDirectory: true)
        try fm.createDirectory(at: effectFolder, withIntermediateDirectories: true)
        try encoder.encode(PluginLoader.exampleEffect).write(to: effectFolder.appendingPathComponent(PluginLoader.manifestName))
        let signalFolder = Self.folder.appendingPathComponent("Every Five Minutes", isDirectory: true)
        try fm.createDirectory(at: signalFolder, withIntermediateDirectories: true)
        try encoder.encode(PluginLoader.exampleSignal).write(to: signalFolder.appendingPathComponent(PluginLoader.manifestName))
        let script = signalFolder.appendingPathComponent("run.sh")
        try PluginLoader.exampleSignalScript.write(to: script, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        reload()
    }

    /// What a signal plugin gets on stdin.
    public struct SignalInput: Codable, Sendable {
        public struct Word: Codable, Sendable { public var text: String; public var start: Seconds; public var end: Seconds }
        public var mediaPath: String
        public var assetName: String
        public var duration: Seconds
        public var transcript: [Word]
    }

    /// Runs a signal plugin and reads its events (any format `GameEventLog` understands). Two minutes at most.
    public func runSignal(_ plugin: Loaded, input: SignalInput) async throws -> [HUDEvent] {
        guard let argv = plugin.manifest.command, let first = argv.first else { throw EngineError.exportFailed("the plugin has no command") }
        let process = Process()
        process.executableURL = Self.resolve(first, in: plugin.folder)
        process.arguments = Array(argv.dropFirst())
        process.currentDirectoryURL = plugin.folder
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        let payload = try JSONEncoder().encode(input)
        try process.run()
        stdin.fileHandleForWriting.write(payload)
        try? stdin.fileHandleForWriting.close()
        let output: Data = try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return data
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 120_000_000_000)
                if process.isRunning { process.terminate() }
                throw EngineError.exportFailed("the plugin took longer than two minutes")
            }
            let first = try await group.next() ?? Data()
            group.cancelAll()
            return first
        }
        guard process.terminationStatus == 0 else {
            let message = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw EngineError.exportFailed(message.isEmpty ? "the plugin exited with status \(process.terminationStatus)" : message)
        }
        return GameEventLog.parse(data: output)?.events ?? []
    }
}
