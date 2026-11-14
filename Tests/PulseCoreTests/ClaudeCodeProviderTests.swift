#if PULSE_DEV
import XCTest
@testable import PulseCore

/// The dev build's bridge to Claude Code. Run with `swift test -Xswiftc -DPULSE_DEV`.
final class ClaudeCodeProviderTests: XCTestCase {
    private func output(_ json: [String: Any], status: Int32 = 0, stderr: String = "") -> ClaudeCodeCLI.Output {
        ClaudeCodeCLI.Output(status: status, stdout: try! JSONSerialization.data(withJSONObject: json), stderr: Data(stderr.utf8))
    }

    private func success(_ answer: [String: Any], model: String = "claude-opus-5-5") -> [String: Any] {
        ["type": "result", "subtype": "success", "is_error": false, "num_turns": 2, "result": "", "structured_output": answer,
         "modelUsage": [model: ["outputTokens": 59], "claude-haiku-5-5": ["outputTokens": 4]]]
    }

    func testTheCommandLineAsksForOneJSONAnswerWithNoTools() {
        let request = ClaudeCodeCLI.Request(system: "Be brief.", user: "the text", schema: "{\"type\":\"object\"}", effort: "high")
        let arguments = ClaudeCodeCLI.arguments(for: request, model: "claude-opus-5-5")
        XCTAssertEqual(arguments.first, "-p")
        func value(after flag: String) -> String? { arguments.firstIndex(of: flag).map { arguments[$0 + 1] } }
        XCTAssertEqual(value(after: "--output-format"), "json")
        XCTAssertEqual(value(after: "--json-schema"), "{\"type\":\"object\"}")
        XCTAssertEqual(value(after: "--system-prompt"), "Be brief.")
        XCTAssertEqual(value(after: "--tools"), "", "every built-in tool is off")
        XCTAssertEqual(value(after: "--model"), "claude-opus-5-5")
        XCTAssertEqual(value(after: "--effort"), "high")
        XCTAssertEqual(value(after: "--permission-mode"), "dontAsk")
        for flag in ["--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence"] { XCTAssertTrue(arguments.contains(flag), flag) }
        XCTAssertFalse(arguments.contains("the text"), "the text goes in on standard input, not on the command line")
        XCTAssertFalse(arguments.contains("--bare"), "bare mode needs an API key; this build uses the login")
        XCTAssertFalse(ClaudeCodeCLI.arguments(for: request, model: "").contains("--model"))
    }

    func testAnAnswerIsReadWithTheModelThatWroteIt() throws {
        let answer = try ClaudeCodeCLI.answer(from: output(success(["title": "One HP Away"])), model: "opus")
        XCTAssertEqual(answer.json["title"] as? String, "One HP Away")
        XCTAssertEqual(answer.servedBy, "claude-opus-5-5", "the model that wrote most of the reply, not a helper")
        XCTAssertEqual(answer.label, "Claude (claude-opus-5-5) through Claude Code")
    }

    func testAnswersFromAnOlderCommandAreReadFromTheText() throws {
        let old: [String: Any] = ["type": "result", "subtype": "success", "is_error": false, "result": "Here you go:\n```json\n{\"title\": \"Clutch\"}\n```"]
        let answer = try ClaudeCodeCLI.answer(from: output(old), model: "claude-opus-5-5")
        XCTAssertEqual(answer.json["title"] as? String, "Clutch")
        XCTAssertEqual(answer.servedBy, "claude-opus-5-5")
        // Something printed before the result line doesn't hide it.
        var noisy = ClaudeCodeCLI.Output(status: 0, stdout: Data("warning: something\n".utf8))
        noisy.stdout.append(output(success(["title": "A"])).stdout)
        XCTAssertEqual(try ClaudeCodeCLI.answer(from: noisy, model: "").json["title"] as? String, "A")
    }

    func testFailuresSayWhatWentWrong() {
        func message(_ output: ClaudeCodeCLI.Output) -> String {
            do { _ = try ClaudeCodeCLI.answer(from: output, model: "x"); return "no error" } catch { return (error as? LocalizedError)?.errorDescription ?? "\(error)" }
        }
        // What the command printed here for a model that doesn't exist.
        let unknown: [String: Any] = ["type": "result", "subtype": "success", "is_error": true, "api_error_status": 404,
                                      "result": "There's an issue with the selected model (nope). It may not exist or you may not have access to it."]
        XCTAssertTrue(message(output(unknown, status: 1)).contains("selected model (nope)"))
        // Not signed in: the owner is told how to sign in.
        let signedOut: [String: Any] = ["type": "result", "subtype": "success", "is_error": true, "result": "Invalid API key · Please run /login"]
        let hint = message(output(signedOut, status: 1))
        XCTAssertTrue(hint.contains("/login"))
        XCTAssertTrue(hint.contains("sign in with your Claude account"))
        // A usage limit is passed on as Claude Code worded it, without the sign-in advice.
        let limited: [String: Any] = ["type": "result", "subtype": "success", "is_error": true, "result": "You've hit your session limit · resets 3pm"]
        XCTAssertTrue(message(output(limited, status: 1)).contains("resets 3pm"))
        XCTAssertFalse(message(output(limited, status: 1)).contains("sign in"))
        // Nothing printed at all: the error stream is shown.
        XCTAssertTrue(message(ClaudeCodeCLI.Output(status: 127, stdout: Data(), stderr: Data("env: node: No such file or directory".utf8))).contains("node: No such file"))
        XCTAssertTrue(message(ClaudeCodeCLI.Output(status: 3, stdout: Data())).contains("exited with code 3"))
        // Out of turns, a refusal, and a reply with no JSON in it.
        XCTAssertTrue(message(output(["type": "result", "subtype": "error_max_turns", "is_error": false])).contains("used all its turns"))
        XCTAssertEqual(message(output(["type": "result", "subtype": "success", "is_error": false, "stop_reason": "refusal", "result": "I can't help with that."])),
                       AIProviderError.refused("policy").errorDescription)
        XCTAssertEqual(message(output(["type": "result", "subtype": "success", "is_error": false, "result": "Sure!"])),
                       AIProviderError.badResponse("no JSON in Claude Code's reply").errorDescription)
    }

    func testTheCommandIsFoundWhereInstallersPutIt() {
        let home = "/Users/me"
        func locate(_ custom: String = "", programs: Set<String>, folders: [String: [String]] = [:]) -> String? {
            ClaudeCodeCLI.locate(custom: custom, home: home, path: "/usr/bin:/custom/bin", isProgram: programs.contains, list: { folders[$0] ?? [] })?.path
        }
        XCTAssertNil(locate(programs: []))
        // Its own installer's folder wins over Homebrew, and both over the app's PATH.
        XCTAssertEqual(locate(programs: ["/Users/me/.local/bin/claude", "/opt/homebrew/bin/claude"]), "/Users/me/.local/bin/claude")
        XCTAssertEqual(locate(programs: ["/opt/homebrew/bin/claude", "/custom/bin/claude"]), "/opt/homebrew/bin/claude")
        XCTAssertEqual(locate(programs: ["/custom/bin/claude"]), "/custom/bin/claude")
        // The path from Settings wins when it is a program, and is ignored when it isn't.
        XCTAssertEqual(locate("~/tools/claude", programs: ["/Users/me/tools/claude", "/opt/homebrew/bin/claude"]), "/Users/me/tools/claude")
        XCTAssertEqual(locate("/nowhere/claude", programs: ["/opt/homebrew/bin/claude"]), "/opt/homebrew/bin/claude")
        // A Node version manager: the newest version that has it.
        let nvm = "/Users/me/.nvm/versions/node"
        XCTAssertEqual(locate(programs: ["\(nvm)/v9.1.0/bin/claude", "\(nvm)/v22.3.0/bin/claude"], folders: [nvm: ["v9.1.0", "v22.3.0", "v24.0.0"]]),
                       "\(nvm)/v22.3.0/bin/claude")
    }

    func testTheEnvironmentFindsNodeAndCarriesNoAPIKey() {
        let environment = ClaudeCodeCLI.environment(["PATH": "/usr/bin:/bin", "ANTHROPIC_API_KEY": "placeholder", "ANTHROPIC_AUTH_TOKEN": "placeholder", "LANG": "en_GB.UTF-8"],
                                                    home: "/Users/me", executable: "/Users/me/.nvm/versions/node/v22/bin/claude")
        XCTAssertNil(environment["ANTHROPIC_API_KEY"], "a key would be billed instead of the login")
        XCTAssertNil(environment["ANTHROPIC_AUTH_TOKEN"])
        XCTAssertEqual(environment["PATH"], "/Users/me/.nvm/versions/node/v22/bin:/Users/me/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")
        XCTAssertEqual(environment["HOME"], "/Users/me")
        XCTAssertEqual(environment["LANG"], "en_GB.UTF-8")
    }

    func testEachFeatureAsksItsOwnQuestion() async throws {
        final class Seen: @unchecked Sendable { var requests: [ClaudeCodeCLI.Request] = []; var models: [String] = [] }
        let seen = Seen()
        let answers: [[String: Any]] = [
            ["titles": ["ONE HP"], "shorts_title": "One HP", "tiktok_caption": "one hp #clutch", "instagram_caption": "one hp", "hashtags": ["#clutch"]],
            ["sentences": ["No puede ser.", "Lo hizo."]],
            ["ready": true],
        ]
        let provider = ClaudeCodeProvider(model: "claude-opus-5-5") { [self] request, model in
            seen.requests.append(request)
            seen.models.append(model)
            return self.output(self.success(answers[seen.requests.count - 1]))
        }
        XCTAssertEqual(provider.id, ClaudeCodeCLI.marker)
        XCTAssertEqual(provider.location, .cloud, "the words leave the Mac, so the privacy badge says so")

        let copy = try await provider.copy(for: ClipContext(transcript: "no way he did it", tags: ["hype"], duration: 12))
        XCTAssertEqual(copy.titles, ["ONE HP"])
        XCTAssertEqual(copy.generatedBy, "Claude (claude-opus-5-5) through Claude Code")
        let translated = try await provider.translate(sentences: ["No way.", "He did it."], from: "en", to: "es")
        XCTAssertEqual(translated, ["No puede ser.", "Lo hizo."])
        let served = try await provider.check()
        XCTAssertEqual(served, "claude-opus-5-5")
        let none = try await provider.translate(sentences: [], from: nil, to: "es")
        XCTAssertEqual(none, [], "nothing to translate is not a question")

        XCTAssertEqual(seen.requests.count, 3)
        XCTAssertEqual(seen.models, ["claude-opus-5-5", "claude-opus-5-5", "claude-opus-5-5"])
        XCTAssertTrue(seen.requests[0].user.contains("no way he did it"))
        XCTAssertEqual(seen.requests[0].effort, "low")
        XCTAssertTrue(seen.requests[0].schema.contains("\"shorts_title\""))
        XCTAssertTrue(seen.requests[1].user.contains("1. No way."))
    }

    func testAStudiedVideoIsAskedAboutAtHighEffort() async throws {
        final class Seen: @unchecked Sendable { var request: ClaudeCodeCLI.Request? }
        let seen = Seen()
        let provider = ClaudeCodeProvider(model: "claude-opus-5-5") { [self] request, _ in
            seen.request = request
            return self.output(self.success(["kind": "tutorial", "summary": "s", "opens_on_payoff": "yes",
                                             "lessons": [["topic": "hook", "rule": "Open on the best moment.", "evidence": "00:00"]]]))
        }
        let style = ReferenceStyle(name: "Tutorial", duration: 300, aspect: 16.0 / 9.0, cutsPerMinute: 10, averageShotLength: 6, zoomsPerMinute: 2, zoomScale: 1.15,
                                   captions: nil, popupsPerMinute: 0, wordsPerMinute: 170, pauseRatio: 0.06, musicBed: 0.5, effectsPerMinute: 1, fadesPerMinute: 0, opensFast: true)
        let material = StyleStudyMaterial(spoken: [.init(time: 0, text: "never open with a greeting, open on the best moment.")], onScreen: [])
        let brief = try XCTUnwrap(StyleStudy.brief(style: style, material: material))
        let lessons = try await provider.studyStyle(brief: brief)
        XCTAssertEqual(lessons.lessons.map(\.rule), ["Open on the best moment."])
        XCTAssertEqual(lessons.opensOnPayoff, true)
        XCTAssertEqual(lessons.writtenBy, "Claude (claude-opus-5-5) through Claude Code")
        XCTAssertEqual(seen.request?.effort, "high")
        XCTAssertEqual(seen.request?.system, StyleStudy.system)
        XCTAssertTrue(seen.request?.user.contains("never open with a greeting") ?? false)
        XCTAssertTrue(seen.request?.schema.contains("\"opens_on_payoff\"") ?? false)
    }

    /// The real thing, start to finish, through a stand-in program: the text arrives on standard input, the
    /// program runs in an empty folder, and what it prints comes back.
    func testTheCommandIsRunWithTheTextAsItsInput() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-claude-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("claude")
        try """
        #!/bin/sh
        words=$(wc -w | tr -d ' ')
        files=$(ls | wc -l | tr -d ' ')
        echo "noise on the error stream" >&2
        printf '{"type":"result","subtype":"success","is_error":false,"structured_output":{"words":%s,"files":%s,"first":"%s","key":"%s"}}' "$words" "$files" "$1" "$ANTHROPIC_API_KEY"
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let environment = ClaudeCodeCLI.environment(["PATH": "/usr/bin:/bin", "ANTHROPIC_API_KEY": "placeholder"], home: folder.path, executable: script.path)
        let output = try await ClaudeCodeCLI.run(executable: script, arguments: ["-p"], input: "one two three four", environment: environment, timeout: 30)
        XCTAssertEqual(output.status, 0)
        XCTAssertTrue(String(decoding: output.stderr, as: UTF8.self).contains("noise"))
        let answer = try ClaudeCodeCLI.answer(from: output, model: "m")
        XCTAssertEqual(answer.json["words"] as? Int, 4)
        XCTAssertEqual(answer.json["files"] as? Int, 0, "it runs in an empty folder")
        XCTAssertEqual(answer.json["first"] as? String, "-p")
        XCTAssertEqual(answer.json["key"] as? String, "")
    }

    func testACommandThatHangsIsStopped() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-claude-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("claude")
        try "#!/bin/sh\nexec sleep 60\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let started = Date()
        do {
            _ = try await ClaudeCodeCLI.run(executable: script, arguments: [], input: "", environment: ["PATH": "/usr/bin:/bin"], timeout: 1)
            XCTFail("a hung command should not come back with an answer")
        } catch {
            XCTAssertTrue(((error as? LocalizedError)?.errorDescription ?? "").contains("PULSE stopped it"), "\(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 20)

        // A cancelled task stops it too.
        let task = Task { try await ClaudeCodeCLI.run(executable: script, arguments: [], input: "", environment: ["PATH": "/usr/bin:/bin"], timeout: 50) }
        try await Task.sleep(nanoseconds: 400_000_000)
        task.cancel()
        let cancelledAt = Date()
        let result = await task.result
        XCTAssertLessThan(Date().timeIntervalSince(cancelledAt), 20)
        if case .success = result { XCTFail("a cancelled run should throw") }

        // A program that isn't there is an error in words, not a crash.
        do {
            _ = try await ClaudeCodeCLI.run(executable: folder.appendingPathComponent("missing"), arguments: [], input: "", environment: [:], timeout: 5)
            XCTFail("a missing program can't be run")
        } catch {
            XCTAssertTrue(((error as? LocalizedError)?.errorDescription ?? "").contains("couldn't be started"), "\(error)")
        }
    }

    /// Against the real command, when asked for (`PULSE_CLAUDE_LIVE=1`): spends a little of the signed-in account.
    func testLiveAgainstTheRealCommand() async throws {
        guard ProcessInfo.processInfo.environment["PULSE_CLAUDE_LIVE"] == "1" else { throw XCTSkip("set PULSE_CLAUDE_LIVE=1 to ask the real Claude Code") }
        guard let executable = ClaudeCodeCLI.locate(custom: "") else { throw XCTSkip("Claude Code isn't installed here") }
        let provider = ClaudeCodeProvider(model: "claude-opus-5-5", executable: executable)
        let served = try await provider.check()
        XCTAssertTrue(served.contains("opus"), served)
        let copy = try await provider.copy(for: ClipContext(transcript: "No way, that was the craziest clutch I've ever seen, let's go!", tags: ["hype"], duration: 12))
        XCTAssertFalse(copy.titles.isEmpty)
        let translated = try await provider.translate(sentences: ["No way.", "He actually did it."], from: "en", to: "es")
        XCTAssertEqual(translated.count, 2)
        print("LIVE served=\(served) title=\(copy.titles[0]) translated=\(translated)")

        // An edit plan: the largest answer shape PULSE asks for, at high effort.
        var words: [TranscriptWord] = []
        let said = ["today we try to beat the final boss without taking a single hit.", "first attempt, okay, here we go.", "oh no, I already got hit, that's embarrassing.",
                    "let me grab a drink, one second.", "right, attempt two, I know the pattern now.", "dodge, dodge, yes, phase two!", "he has one hit point left, do not choke.",
                    "no way, I did it, no damage, let's go!", "thanks for watching, that took four hours."]
        for (n, sentence) in said.enumerated() {
            for (i, text) in sentence.split(separator: " ").enumerated() {
                let start = Double(n) * 30 + Double(i) * 0.4
                words.append(TranscriptWord(text: String(text), start: start, end: start + 0.35))
            }
        }
        let analysis = MediaAnalysis(assetID: UUID(), duration: 270, transcript: Transcript(words: words, source: .demo), profile: .gameplayWithFacecam)
        var options = LongFormOptions()
        options.minimumLength = 60
        options.maximumLength = 150
        let brief = try XCTUnwrap(EditPlanner.brief(analysis: analysis, options: options, picks: [], excitement: [], step: 1, budget: 600_000))
        let draft = try await provider.planEdit(brief: brief)
        XCTAssertFalse(draft.sections.isEmpty)
        print("LIVE plan by=\(draft.writtenBy) sections=\(draft.sections.count) hookLine=\(draft.hookLine) summary=\(draft.summary)")

        // What a studied video teaches.
        let style = ReferenceStyle(name: "How to edit a gaming video", duration: 300, aspect: 16.0 / 9.0, cutsPerMinute: 16, averageShotLength: 3.7, zoomsPerMinute: 4, zoomScale: 1.2,
                                   captions: nil, popupsPerMinute: 1, wordsPerMinute: 185, pauseRatio: 0.04, musicBed: 0.7, effectsPerMinute: 3, fadesPerMinute: 0, opensFast: true)
        let spoken: [StyleStudyMaterial.Line] = [
            .init(time: 0, text: "This clip got four million views and I'm going to show you exactly how I edited it."),
            .init(time: 12, text: "Rule one: never open with a greeting. Put the best moment of the whole video in the first five seconds."),
            .init(time: 40, text: "Rule two: cut every breath and every um, but leave the laugh after a joke, that's the part people stay for."),
            .init(time: 95, text: "Zoom in about ten percent on the punchline, and snap it, don't ease it."),
            .init(time: 150, text: "Every two minutes or so, tell the viewer what's coming next, so they have a reason to keep watching."),
            .init(time: 210, text: "Sound effects sit under the voice. If you can't hear the words, it's too loud."),
        ]
        let studyBrief = try XCTUnwrap(StyleStudy.brief(style: style, material: StyleStudyMaterial(spoken: spoken, onScreen: [.init(time: 12, text: "RULE 1: OPEN ON THE BEST MOMENT")])))
        let lessons = try await provider.studyStyle(brief: studyBrief)
        XCTAssertGreaterThanOrEqual(lessons.lessons.count, 3)
        print("LIVE study kind=\(lessons.kind.rawValue) opens=\(String(describing: lessons.opensOnPayoff)) lessons=\(lessons.lessons.count) by=\(lessons.writtenBy)")
        for lesson in lessons.lessons.prefix(4) { print("LIVE lesson [\(lesson.topic.rawValue)] \(lesson.rule) <- \(lesson.evidence)") }
    }
}
#endif
