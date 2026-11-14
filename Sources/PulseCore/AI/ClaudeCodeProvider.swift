#if PULSE_DEV
import Foundation

/// DEV BUILD ONLY. Compiled when `PULSE_DEV` is defined (scripts/build-dev-app.sh); the public app has none
/// of this, and scripts/build-app.sh refuses to ship a binary that contains it.
///
/// Reaches Claude through the Claude Code command that is already installed and signed in on this Mac, so
/// PULSE's model features run on the owner's own Claude account instead of an API key. PULSE starts
/// `claude -p` with no tools, hands it the text on standard input and reads back one JSON object. PULSE
/// never sees or stores the login: that stays inside Claude Code.
///
/// It is for the person who built the app, on their own Mac. Anthropic does not let other products offer
/// a Claude login to their users, which is why this cannot be in the download.
public enum ClaudeCodeCLI {
    /// A string only this file contains. The public build script looks for it in the binary.
    public static let marker = "pulse.dev.claude-code"

    /// One question: instructions, the text, the shape of the answer (a JSON schema as text), how hard to
    /// think, and how long to wait.
    public struct Request: Sendable, Equatable {
        public var system: String
        public var user: String
        public var schema: String
        public var effort: String
        public var timeout: TimeInterval

        public init(system: String, user: String, schema: String, effort: String = "low", timeout: TimeInterval = 300) {
            self.system = system
            self.user = user
            self.schema = schema
            self.effort = effort
            self.timeout = timeout
        }
    }

    /// What the command left behind when it exited.
    public struct Output: Sendable, Equatable {
        public var status: Int32
        public var stdout: Data
        public var stderr: Data

        public init(status: Int32, stdout: Data, stderr: Data = Data()) {
            self.status = status
            self.stdout = stdout
            self.stderr = stderr
        }
    }

    public struct Answer {
        public var json: [String: Any]
        /// The model that wrote it, as Claude Code reports it.
        public var servedBy: String
        public var label: String { "Claude (\(servedBy)) through Claude Code" }
    }

    /// A schema as the one-line JSON text the command takes.
    public static func text(_ schema: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// The command line for one question. The text itself goes in on standard input.
    public static func arguments(for request: Request, model: String) -> [String] {
        var arguments = [
            "-p", "--output-format", "json", "--json-schema", request.schema,
            "--system-prompt", request.system,
            // A question and an answer, not an agent: no tools, no MCP servers, no skills.
            "--tools", "", "--strict-mcp-config", "--disable-slash-commands",
            // None of the owner's own Claude Code instructions or hooks, and nothing kept afterwards.
            "--setting-sources", "project", "--no-session-persistence",
            "--permission-mode", "dontAsk",
            "--effort", request.effort,
            // The answer itself takes two turns; the rest are for a reply that failed the schema.
            "--max-turns", "8",
        ]
        if !model.isEmpty { arguments += ["--model", model] }
        return arguments
    }

    /// The answer in what the command printed, or the reason there is none, in words the owner can act on.
    public static func answer(from output: Output, model: String) throws -> Answer {
        let printed = String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let complaint = String(decoding: output.stderr.suffix(600), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let object = lastObject(in: printed) else {
            let detail = complaint.isEmpty ? String(printed.suffix(300)) : complaint
            throw AIProviderError.unavailable(failure(detail.isEmpty ? "it exited with code \(output.status) and printed nothing" : detail))
        }
        let message = (object["result"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if object["is_error"] as? Bool == true {
            throw AIProviderError.unavailable(failure(message.isEmpty ? (complaint.isEmpty ? "it reported an error without saying which" : complaint) : message))
        }
        let usage = object["modelUsage"] as? [String: Any] ?? [:]
        let served = usage.max { tokens($0.value) < tokens($1.value) }?.key ?? (model.isEmpty ? "Claude" : model)
        if let json = object["structured_output"] as? [String: Any] { return Answer(json: json, servedBy: served) }
        if object["stop_reason"] as? String == "refusal" { throw AIProviderError.refused("policy") }
        if let subtype = object["subtype"] as? String, subtype != "success" {
            throw AIProviderError.unavailable(failure(subtype == "error_max_turns" ? "it used all its turns without settling on an answer" : subtype.replacingOccurrences(of: "_", with: " ")))
        }
        // No structured answer: an older Claude Code puts the JSON in the reply's text.
        if let json = lastObject(in: fenced(message)) { return Answer(json: json, servedBy: served) }
        if output.status != 0 { throw AIProviderError.unavailable(failure(complaint.isEmpty ? "it exited with code \(output.status)" : complaint)) }
        throw AIProviderError.badResponse("no JSON in Claude Code's reply")
    }

    private static func tokens(_ usage: Any) -> Double {
        ((usage as? [String: Any])?["outputTokens"] as? NSNumber)?.doubleValue ?? 0
    }

    /// The JSON object that is the whole text, or the one on its last line.
    static func lastObject(in text: String) -> [String: Any]? {
        if let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] { return object }
        for line in text.split(separator: "\n").reversed() {
            if let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] { return object }
        }
        return nil
    }

    /// Text without the code fence or sentence a model may wrap its JSON in.
    static func fenced(_ text: String) -> String {
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close else { return text }
        return String(text[open...close])
    }

    static func failure(_ detail: String) -> String {
        var text = "Claude Code couldn't answer: \(detail)"
        if !text.hasSuffix(".") { text += "." }
        let lower = detail.lowercased()
        if ["/login", "log in", "logged in", "authenticat", "api key", "oauth", "credential"].contains(where: lower.contains) {
            text += " Open Terminal, run “claude”, sign in with your Claude account, then try again."
        }
        return text
    }

    public static let notInstalled = "PULSE couldn't find Claude Code on this Mac. Install it (claude.com/claude-code), run “claude” once in Terminal and sign in with your Claude account. If it is installed somewhere unusual, give its path in Settings → AI Processing."

    // MARK: Finding the command

    /// Where the `claude` command usually is, most likely first: its own installer's folder, Homebrew, npm,
    /// then whatever the app's own PATH holds. A Mac app doesn't get the Terminal's PATH.
    public static func candidates(home: String, path: String) -> [String] {
        var folders = ["\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin",
                       "\(home)/.npm-global/bin", "\(home)/.bun/bin", "\(home)/.volta/bin"]
        for folder in path.split(separator: ":").map(String.init) where !folder.isEmpty && !folders.contains(folder) { folders.append(folder) }
        return folders.map { "\($0)/claude" }
    }

    /// The command to run: the path from Settings when it is a program, else the first usual place that has
    /// one, else the newest copy a Node version manager or the Claude desktop app keeps in a versioned folder.
    public static func locate(custom: String, home: String = NSHomeDirectory(),
                              path: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
                              isProgram: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
                              list: (String) -> [String] = { (try? FileManager.default.contentsOfDirectory(atPath: $0)) ?? [] }) -> URL? {
        var own = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        if own.hasPrefix("~/") { own = home + own.dropFirst(1) }
        if !own.isEmpty, isProgram(own) { return URL(fileURLWithPath: own) }
        if let usual = candidates(home: home, path: path).first(where: isProgram) { return URL(fileURLWithPath: usual) }
        let versioned = [("\(home)/.nvm/versions/node", "bin/claude"), ("\(home)/Library/Application Support/Claude/claude-code", "claude")]
        for (folder, program) in versioned {
            // Newest first: version folders sort numerically ("v9" before "v22" would be wrong as plain text).
            let versions = list(folder).sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            if let found = versions.map({ "\(folder)/\($0)/\(program)" }).first(where: isProgram) { return URL(fileURLWithPath: found) }
        }
        return nil
    }

    /// The command's environment: the app's own, with the usual program folders on the PATH (an npm install
    /// of Claude Code needs to find `node`), and without an API key, which Claude Code would bill instead
    /// of using the login this build exists for.
    public static func environment(_ base: [String: String], home: String, executable: String) -> [String: String] {
        var environment = base
        environment["ANTHROPIC_API_KEY"] = nil
        environment["ANTHROPIC_AUTH_TOKEN"] = nil
        var folders = [(executable as NSString).deletingLastPathComponent, "\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        for folder in (base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init) where !folders.contains(folder) {
            folders.append(folder)
        }
        environment["PATH"] = folders.filter { !$0.isEmpty }.joined(separator: ":")
        if environment["HOME"] == nil { environment["HOME"] = home }
        return environment
    }

    // MARK: Running it

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    /// Asks the command to stop, and two seconds later makes it: a child started from a background thread
    /// can inherit that thread's blocked signals, and then never hears the polite request.
    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    /// Runs the command in an empty folder, with the text as its input, and waits for it to exit. Input and
    /// output go through files, so a long transcript can't stall on a full pipe. Stops it when the task is
    /// cancelled or the time is up.
    public static func run(executable: URL, arguments: [String], input: String, environment: [String: String],
                           timeout: TimeInterval) async throws -> Output {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("pulse-claude-\(UUID().uuidString)")
        let work = root.appendingPathComponent("work")
        try files.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let inputURL = root.appendingPathComponent("in.txt")
        let outputURL = root.appendingPathComponent("out.json")
        let errorURL = root.appendingPathComponent("err.txt")
        try Data(input.utf8).write(to: inputURL)
        files.createFile(atPath: outputURL.path, contents: nil)
        files.createFile(atPath: errorURL.path, contents: nil)

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = work
        process.standardInput = try FileHandle(forReadingFrom: inputURL)
        process.standardOutput = try FileHandle(forWritingTo: outputURL)
        process.standardError = try FileHandle(forWritingTo: errorURL)
        let timedOut = Flag()
        let started = Flag()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in continuation.resume() }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: AIProviderError.unavailable("Claude Code couldn't be started (\(error.localizedDescription)). Check its path in Settings → AI Processing."))
                    return
                }
                started.set()
                // Cancelled before it started: the handler below had nothing to stop yet.
                if Task.isCancelled { stop(process) }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning {
                        timedOut.set()
                        stop(process)
                    }
                }
            }
        } onCancel: {
            if started.isSet { stop(process) }
        }
        try Task.checkCancellation()
        if timedOut.isSet {
            let minutes = max(1, Int((timeout / 60).rounded()))
            throw AIProviderError.unavailable("Claude Code hadn't answered after \(minutes) minute\(minutes == 1 ? "" : "s"), so PULSE stopped it. Try again, or with a shorter recording.")
        }
        return Output(status: process.terminationStatus,
                      stdout: (try? Data(contentsOf: outputURL)) ?? Data(),
                      stderr: (try? Data(contentsOf: errorURL)) ?? Data())
    }
}

/// DEV BUILD ONLY. PULSE's model features, answered by Claude Code under the owner's own login: titles and
/// captions, caption translation, edit plans and what a studied video teaches. Only text is sent.
public struct ClaudeCodeProvider: InsightProvider, TranslationProvider, EditPlanProvider, StyleStudyProvider {
    public typealias Runner = @Sendable (_ request: ClaudeCodeCLI.Request, _ model: String) async throws -> ClaudeCodeCLI.Output

    public let id = ClaudeCodeCLI.marker
    public let displayName = "Claude Code (your Claude account)"
    public let location = ProcessingLocation.cloud
    public let capabilities: Set<AICapability> = [.titleGeneration, .hookAnalysis]

    public var model: String
    let run: Runner

    public init(model: String = "claude-opus-5-5", executable: URL) {
        self.model = model
        self.run = { request, model in
            try await ClaudeCodeCLI.run(executable: executable, arguments: ClaudeCodeCLI.arguments(for: request, model: model), input: request.user,
                                        environment: ClaudeCodeCLI.environment(ProcessInfo.processInfo.environment, home: NSHomeDirectory(), executable: executable.path),
                                        timeout: request.timeout)
        }
    }

    /// With the command replaced, for tests.
    public init(model: String, run: @escaping Runner) {
        self.model = model
        self.run = run
    }

    func ask(_ request: ClaudeCodeCLI.Request) async throws -> ClaudeCodeCLI.Answer {
        try ClaudeCodeCLI.answer(from: try await run(request, model), model: model)
    }

    public func copy(for context: ClipContext) async throws -> ClipCopy {
        let answer = try await ask(.init(system: ClipCopyPrompt.system, user: ClipCopyPrompt.user(context),
                                         schema: ClaudeCodeCLI.text(ClipCopyPrompt.schema)))
        return try ClipCopyPrompt.parse(answer.json, generatedBy: answer.label)
    }

    public func translate(sentences: [String], from source: String?, to language: String) async throws -> [String] {
        guard !sentences.isEmpty else { return [] }
        let answer = try await ask(.init(system: TranslationPrompt.system, user: TranslationPrompt.user(sentences: sentences, from: source, to: language),
                                         schema: ClaudeCodeCLI.text(TranslationPrompt.schema), timeout: 600))
        return try TranslationPrompt.parse(answer.json, expected: sentences.count)
    }

    /// A long transcript in and a reasoned plan out can run for many minutes.
    public func planEdit(brief: EditBrief) async throws -> EditPlanDraft {
        let answer = try await ask(.init(system: EditPlanner.system, user: brief.text, schema: ClaudeCodeCLI.text(EditPlanner.schema),
                                         effort: "high", timeout: 1800))
        return try EditPlanner.parse(answer.json, writtenBy: answer.label)
    }

    public func studyStyle(brief: StyleStudyBrief) async throws -> StyleLessons {
        let answer = try await ask(.init(system: StyleStudy.system, user: brief.text, schema: ClaudeCodeCLI.text(StyleStudy.schema),
                                         effort: "high", timeout: 900))
        return try StyleStudy.parse(answer.json, writtenBy: answer.label)
    }

    public func mergeLessons(brief: GenreStudyBrief) async throws -> GenreKnowledge {
        let answer = try await ask(.init(system: GenreStudy.system, user: brief.text, schema: ClaudeCodeCLI.text(GenreStudy.schema),
                                         effort: "high", timeout: 1500))
        return try GenreStudy.parse(answer.json, brief: brief, writtenBy: answer.label)
    }

    /// Asks for one word back: proof that the command runs and is signed in. Returns the model that answered.
    public func check() async throws -> String {
        let schema: [String: Any] = ["type": "object", "properties": ["ready": ["type": "boolean"]], "required": ["ready"], "additionalProperties": false]
        let answer = try await ask(.init(system: "You are a connection test. Return JSON only.", user: "Reply that you are ready.",
                                         schema: ClaudeCodeCLI.text(schema), timeout: 120))
        return answer.servedBy
    }
}
#endif
