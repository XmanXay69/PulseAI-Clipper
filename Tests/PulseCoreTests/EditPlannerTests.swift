import XCTest
@testable import PulseCore

/// #1281: a language model plans the edit; everything it answers is checked before the editor builds from it.
final class EditPlannerTests: XCTestCase {
    /// A sentence every ten seconds: line n runs from (n-1)*10 to about (n-1)*10+6.
    private func analysis(sentences: Int, duration: Seconds? = nil) -> MediaAnalysis {
        var words: [TranscriptWord] = []
        for n in 0..<sentences {
            let said = "this is sentence number \(n + 1) of the stream and it ends here."
            for (i, text) in said.split(separator: " ").enumerated() {
                let start = Double(n) * 10 + Double(i) * 0.45
                words.append(TranscriptWord(text: String(text), start: start, end: start + 0.4))
            }
        }
        return MediaAnalysis(assetID: UUID(), duration: duration ?? Double(sentences) * 10, transcript: Transcript(words: words, source: .demo),
                             profile: .gameplayWithFacecam)
    }

    private func options(_ minimum: Seconds = 120, _ maximum: Seconds = 240) -> LongFormOptions {
        var options = LongFormOptions()
        options.minimumLength = minimum
        options.maximumLength = maximum
        return options
    }

    private func brief(sentences: Int = 60, budget: Int = 600_000, picks: [LongFormSegment] = [], excitement: [Float] = []) throws -> EditBrief {
        try XCTUnwrap(EditPlanner.brief(analysis: analysis(sentences: sentences), options: options(), picks: picks, excitement: excitement, step: 1,
                                        budget: budget))
    }

    func testTheBriefIsNumberedLinesWithTimesEnergyAndThePickersMoments() throws {
        // Energy climbs through the recording; the picker liked one stretch.
        let excitement = (0..<600).map { Float($0) / 600 }
        let pick = LongFormSegment(range: TimeRange(start: 300, end: 340), payoff: 330, potential: 88, title: "", tags: [.funny, .reaction])
        let brief = try brief(picks: [pick], excitement: excitement)
        XCTAssertEqual(brief.lines.count, 60, "a line a sentence")
        XCTAssertEqual(brief.lines.map(\.number), Array(1...60))
        XCTAssertEqual(brief.lines[0].range.start, 0, accuracy: 0.01)
        XCTAssertEqual(brief.lines[0].energy, 0)
        XCTAssertEqual(brief.lines[59].energy, 9)
        XCTAssertEqual(brief.leftOut, 0)
        XCTAssertEqual(brief.lineNumbers(in: pick.range), 31...34)
        let text = brief.text
        XCTAssertTrue(text.contains("Recording: 10 min long. Kind: Gameplay + Facecam."), text)
        XCTAssertTrue(text.contains("Wanted: a video of 2 min to 4 min"), text)
        XCTAssertTrue(text.contains("- lines 31-34 (05:00-05:40) score 88: funny, reaction"), text)
        XCTAssertTrue(text.contains("[31] 05:00-05:0"), text)
        XCTAssertTrue(text.contains("this is sentence number 31 of the stream"))
        XCTAssertFalse(text.contains("left out"))
        // No words, no brief.
        XCTAssertNil(EditPlanner.brief(analysis: MediaAnalysis(assetID: UUID(), duration: 100), options: options()))
    }

    func testATranscriptTooLongToSendSaysWhatItLeavesOut() throws {
        let excitement = (0..<600).map { second -> Float in (200..<260).contains(second) ? 1 : 0.1 }
        let pick = LongFormSegment(range: TimeRange(start: 400, end: 430), payoff: 420, potential: 80, title: "", tags: [])
        let whole = try brief(picks: [pick], excitement: excitement)
        let size = whole.lines.reduce(0) { $0 + $1.text.count + 28 }
        let short = try brief(budget: size / 3, picks: [pick], excitement: excitement)
        XCTAssertLessThan(short.lines.count, whole.lines.count)
        XCTAssertGreaterThan(short.leftOut, 100)
        // Lines are renumbered without holes, the picked moment and the liveliest stretch are still there, and each gap is marked.
        XCTAssertEqual(short.lines.map(\.number), Array(1...short.lines.count))
        XCTAssertTrue(short.lines.contains { $0.range.overlaps(pick.range) })
        XCTAssertTrue(short.lines.contains { $0.range.overlaps(TimeRange(start: 200, end: 260)) })
        XCTAssertEqual(short.lines.reduce(0) { $0 + $1.skippedBefore } + short.leftOutAtEnd, short.leftOut, accuracy: 0.01, "every second left out is in a marked gap")
        XCTAssertTrue(short.text.contains("of quiet talk left out"), short.text)
        XCTAssertTrue(short.text.contains("The whole transcript did not fit"))
    }

    func testAGoodAnswerBecomesSectionsInTheModelsOrderWithItsCutsAndItsOpening() throws {
        let brief = try brief()
        // The model tells the goal (lines 40-44) first, then the attempts (5-16, minus a tangent), then the ending.
        let draft = EditPlanDraft(summary: "A no-death run that finally works.", hookLine: 52, hookWhy: "The scream needs no context.", sections: [
            .init(title: "The goal", role: "setup", fromLine: 40, toLine: 44, payoffLine: 43, why: "Says what the run is."),
            .init(title: "First tries", role: "build", fromLine: 5, toLine: 16, payoffLine: 15, why: "Shows how hard it is.",
                  cuts: [.init(fromLine: 9, toLine: 11, why: "Reads chat about lunch.")]),
            .init(title: "The win", role: "payoff", fromLine: 50, toLine: 55, payoffLine: 52, why: "It lands."),
        ], writtenBy: "Claude (test)")
        let plan = EditPlanner.resolve(draft, brief: brief)
        XCTAssertEqual(plan.sections.map(\.title), ["The goal", "First tries", "The win"])
        XCTAssertTrue(plan.isReordered, "the goal was said late and is told first")
        XCTAssertTrue(plan.notes.isEmpty, "\(plan.notes)")
        // Lines 40-44: from just before 390 s to just after line 44 ends.
        XCTAssertEqual(plan.sections[0].ranges.count, 1)
        XCTAssertEqual(plan.sections[0].ranges[0].start, 389.7, accuracy: 0.05)
        XCTAssertEqual(plan.sections[0].ranges[0].end, brief.lines[43].range.end + 0.4, accuracy: 0.05)
        // The tangent is out: two stretches, the gap where lines 9-11 were.
        let tries = plan.sections[1]
        XCTAssertEqual(tries.ranges.count, 2)
        XCTAssertEqual(tries.ranges[0].end, brief.lines[8].range.start - 0.1, accuracy: 0.05)
        XCTAssertEqual(tries.ranges[1].start, brief.lines[10].range.end + 0.1, accuracy: 0.05)
        XCTAssertEqual(tries.cutNotes.count, 1)
        XCTAssertTrue(tries.cutNotes[0].contains("Reads chat about lunch."))
        // The opening is the model's line, and the section that holds it lands on it.
        let hook = try XCTUnwrap(plan.hookPayoff)
        XCTAssertEqual(hook, brief.lines[51].range.end - 0.2, accuracy: 0.01)
        XCTAssertEqual(plan.sections[2].payoff, hook)
        XCTAssertEqual(plan.hookWhy, "The scream needs no context.")
        XCTAssertEqual(plan.writtenBy, "Claude (test)")

        // As storyboard moments: four stretches in the model's order, named by section, scored from the picker.
        let picker = [EditBrief.Pick(range: TimeRange(start: 500, end: 530), score: 91, tags: [.hype], payoff: 515)]
        let moments = plan.segments(picks: picker)
        XCTAssertEqual(moments.map(\.title), ["The goal", "First tries (1)", "First tries (2)", "The win"])
        XCTAssertEqual(moments[3].potential, 91)
        XCTAssertEqual(moments[3].tags, [.hype])
        XCTAssertEqual(moments[3].payoff, hook)
        XCTAssertEqual(moments[0].potential, 60, "no picker score nearby")
        XCTAssertTrue(moments.allSatisfy { $0.range.contains($0.payoff) })
        // The editor keeps that order when asked to: nothing is re-sorted or re-joined across the cut.
        let joined = LongFormEditor.joinInOrder(moments)
        XCTAssertEqual(joined.map(\.range), moments.map(\.range))
    }

    func testABadAnswerIsRepairedAndEveryRepairIsSaid() throws {
        let brief = try brief()
        let draft = EditPlanDraft(summary: "  ", hookLine: 3, hookWhy: "It is loud.", sections: [
            .init(title: "", role: "climax", fromLine: 30, toLine: 20, payoffLine: 99, why: ""),                  // reversed, unknown role, payoff outside
            .init(title: "Again", role: "build", fromLine: 22, toLine: 27, payoffLine: 25, why: ""),              // wholly inside the first
            .init(title: "Overlap", role: "build", fromLine: 28, toLine: 36, payoffLine: 34, why: ""),            // half inside the first
            .init(title: "Blip", role: "build", fromLine: 45, toLine: 45, payoffLine: 45, why: "",
                  cuts: [.init(fromLine: 45, toLine: 45, why: "all of it")]),                                    // cut to nothing
            .init(title: "Beyond", role: "payoff", fromLine: 58, toLine: 400, payoffLine: 60, why: ""),          // past the last line
        ])
        let plan = EditPlanner.resolve(draft, brief: brief)
        XCTAssertEqual(plan.sections.map(\.title), ["Section 1", "Overlap", "Beyond"])
        XCTAssertEqual(plan.sections[0].role, "build")
        XCTAssertEqual(plan.sections[0].ranges[0].start, brief.lines[19].range.start - 0.3, accuracy: 0.05, "lines 20 to 30, the right way round")
        XCTAssertTrue(plan.sections[0].ranges[0].contains(plan.sections[0].payoff))
        // The half-repeated section keeps only what is new.
        XCTAssertGreaterThanOrEqual(plan.sections[1].ranges[0].start, plan.sections[0].ranges[0].end - 0.01)
        // Nothing is kept twice.
        let all = plan.sections.flatMap(\.ranges)
        XCTAssertEqual(all.merged().reduce(0) { $0 + $1.duration }, all.reduce(0) { $0 + $1.duration }, accuracy: 0.01)
        XCTAssertLessThanOrEqual(plan.sections[2].ranges[0].end, brief.duration)
        let notes = plan.notes.joined(separator: " | ")
        XCTAssertTrue(notes.contains("Left out “Again”: an earlier section already keeps those lines."), notes)
        XCTAssertTrue(notes.contains("Trimmed “Overlap”"), notes)
        XCTAssertTrue(notes.contains("Left out “Blip”"), notes)
        XCTAssertTrue(notes.contains("1 section named lines that aren't in the transcript"), notes)
        // Line 3 is not in the plan, so the video opens on the payoff section instead, and says so.
        XCTAssertEqual(plan.hookPayoff, plan.sections[2].payoff)
        XCTAssertTrue(notes.contains("opens on “Beyond” instead"), notes)
        XCTAssertEqual(plan.hookWhy, "")
    }

    func testAPlanFarOverTheLengthLosesItsAsidesAndSaysWhatRemains() throws {
        let brief = try brief()   // wanted: 2 to 4 minutes
        let long = EditPlanDraft(summary: "", hookLine: 2, sections: [
            .init(title: "Main", role: "build", fromLine: 1, toLine: 24, payoffLine: 20),
            .init(title: "Side story", role: "aside", fromLine: 30, toLine: 40, payoffLine: 35),
            .init(title: "Another side", role: "aside", fromLine: 45, toLine: 52, payoffLine: 50),
        ])
        let plan = EditPlanner.resolve(long, brief: brief)
        XCTAssertEqual(plan.sections.map(\.title), ["Main"], "about four minutes without the asides")
        XCTAssertEqual(plan.notes.filter { $0.contains("Left out the aside") }.count, 2)
        XCTAssertLessThanOrEqual(plan.keptLength, 240 * 1.15)
        // Still too long with no aside to drop: nothing more is taken away, it is said.
        let longer = EditPlanner.resolve(EditPlanDraft(summary: "", hookLine: 2, sections: [.init(title: "Everything", fromLine: 1, toLine: 60, payoffLine: 30)]), brief: brief)
        XCTAssertEqual(longer.sections.count, 1)
        XCTAssertTrue(longer.notes.contains { $0.contains("more than the 4 minutes asked for") }, "\(longer.notes)")
        // Much too short is said too.
        let short = EditPlanner.resolve(EditPlanDraft(summary: "", hookLine: 2, sections: [.init(title: "Tiny", fromLine: 1, toLine: 3, payoffLine: 2)]), brief: brief)
        XCTAssertTrue(short.notes.contains { $0.contains("less than the 2 minutes asked for") }, "\(short.notes)")
    }

    func testTheModelsJSONIsReadEvenWhenItIsSloppyAndRefusedWhenItIsEmpty() throws {
        let text = """
        {"summary": "A run.", "hook_line": "12", "hook_why": "Loud.", "sections": [
          {"title": "One", "role": "setup", "from_line": 3, "to_line": 9.0, "payoff_line": 8, "why": "Start.", "cuts": [{"from_line": 5, "to_line": 6, "why": "Chat."}, {"why": "no lines"}]},
          {"title": "No numbers", "role": "build", "why": "?"},
          {"title": "Two", "from_line": 20, "to_line": 25}
        ]}
        """
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let draft = try EditPlanner.parse(json, writtenBy: "test")
        XCTAssertEqual(draft.hookLine, 12)
        XCTAssertEqual(draft.sections.map(\.title), ["One", "Two"])
        XCTAssertEqual(draft.sections[0].toLine, 9)
        XCTAssertEqual(draft.sections[0].cuts, [.init(fromLine: 5, toLine: 6, why: "Chat.")])
        XCTAssertEqual(draft.sections[1].payoffLine, 25, "the last line when none is named")
        XCTAssertEqual(draft.sections[1].role, "build")
        XCTAssertThrowsError(try EditPlanner.parse(["summary": "nothing", "sections": [[String: Any]]()], writtenBy: "test"))
        XCTAssertThrowsError(try EditPlanner.parse(["summary": "nothing"], writtenBy: "test"))
        // The schema asks for exactly the keys the parser reads, and closes every object, as structured output requires.
        let schema = EditPlanner.schema
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertEqual(Set(properties.keys), Set(try XCTUnwrap(schema["required"] as? [String])))
        let section = try XCTUnwrap((properties["sections"] as? [String: Any])?["items"] as? [String: Any])
        XCTAssertEqual(section["additionalProperties"] as? Bool, false)
        XCTAssertEqual(Set(try XCTUnwrap(section["properties"] as? [String: Any]).keys), Set(try XCTUnwrap(section["required"] as? [String])))
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: schema))
    }

    func testTheRequestAsksClaudeForAStreamedSchemaBoundPlanAtHighEffort() throws {
        let brief = try brief(sentences: 12)
        let provider = AnthropicInsightProvider(apiKey: "sk-test", model: "claude-opus-5-5")
        let request = try provider.makePlanRequest(brief: brief, stream: true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["max_tokens"] as? Int, 64000)
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        XCTAssertEqual((body["thinking"] as? [String: Any])?["type"] as? String, "adaptive")
        let output = try XCTUnwrap(body["output_config"] as? [String: Any])
        XCTAssertEqual(output["effort"] as? String, "high", "not the low effort titles use")
        XCTAssertEqual((output["format"] as? [String: Any])?["type"] as? String, "json_schema")
        // Nothing the newest models reject: no sampling parameters, no thinking budget, no prefilled answer.
        XCTAssertNil(body["temperature"])
        XCTAssertNil((body["thinking"] as? [String: Any])?["budget_tokens"])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        XCTAssertEqual(messages[0]["content"] as? String, brief.text, "the whole brief, nothing cut")
        // Not streamed (Linux, tests): the smaller reply limit that stays under a response timeout.
        let whole = try XCTUnwrap(try JSONSerialization.jsonObject(with: try XCTUnwrap(provider.makePlanRequest(brief: brief, stream: false).httpBody)) as? [String: Any])
        XCTAssertNil(whole["stream"])
        XCTAssertEqual(whole["max_tokens"] as? Int, 16000)

        // A local server gets the same instructions with the shape in words.
        let local = OpenAICompatibleInsightProvider(apiKey: "", model: "local-model", baseURL: URL(string: "http://localhost:1234/v1")!, isLocalServer: true)
        let chat = try local.makePlanRequest(brief: brief)
        XCTAssertEqual(chat.url?.absoluteString, "http://localhost:1234/v1/chat/completions")
        XCTAssertNil(chat.value(forHTTPHeaderField: "authorization"))
        let chatBody = try XCTUnwrap(try JSONSerialization.jsonObject(with: try XCTUnwrap(chat.httpBody)) as? [String: Any])
        let system = try XCTUnwrap((chatBody["messages"] as? [[String: Any]])?.first?["content"] as? String)
        XCTAssertTrue(system.contains("Reply with one JSON object"))
    }

    func testAStreamedReplyIsCollectedAndAFallbackOrARefusalIsHandled() throws {
        let plan = #"{"summary":"A run.","hook_line":4,"hook_why":"Loud.","sections":[{"title":"One","role":"setup","from_line":3,"to_line":9,"payoff_line":8,"why":"Start.","cuts":[]}]}"#
        func delta(_ text: String) -> String {
            let escaped = String(decoding: try! JSONSerialization.data(withJSONObject: [text], options: []), as: UTF8.self).dropFirst().dropLast()
            return #"data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":\#(escaped)}}"#
        }
        var stream = MessageStream()
        let half = plan.index(plan.startIndex, offsetBy: 40)
        for line in ["event: message_start", #"data: {"type":"message_start","message":{"id":"msg_1","model":"claude-opus-5-5"}}"#, "",
                     #"data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#,
                     #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hidden"}}"#,
                     "event: ping", #"data: {"type":"ping"}"#,
                     delta(String(plan[..<half])), delta(String(plan[half...])),
                     #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":90}}"#,
                     #"data: {"type":"message_stop"}"#] {
            stream.feed(line: line)
        }
        XCTAssertTrue(stream.isFinished)
        XCTAssertEqual(stream.text, plan, "thinking is not part of the answer")
        XCTAssertEqual(stream.model, "claude-opus-5-5")
        let draft = try AnthropicInsightProvider.draft(text: stream.text, stopReason: stream.stopReason, refusalCategory: nil, servedBy: stream.model ?? "")
        XCTAssertEqual(draft.sections.first?.title, "One")
        XCTAssertEqual(draft.writtenBy, "Claude (claude-opus-5-5)")

        // Another model takes over part-way: what the first one wrote before declining is not the answer.
        var switched = MessageStream()
        for line in [#"data: {"type":"message_start","message":{"model":"claude-opus-5-5"}}"#, delta(#"{"summary":"half a pl"#),
                     #"data: {"type":"content_block_start","index":2,"content_block":{"type":"fallback","from":{"model":"claude-opus-5-5"},"to":{"model":"claude-opus-4-8"}}}"#,
                     delta(plan), #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#, #"data: {"type":"message_stop"}"#] {
            switched.feed(line: line)
        }
        XCTAssertEqual(switched.text, plan)
        XCTAssertEqual(switched.model, "claude-opus-4-8")

        // Declined, cut off, or broken: an error that says which, never a half plan.
        var refused = MessageStream()
        refused.feed(line: #"data: {"type":"message_delta","delta":{"stop_reason":"refusal","stop_details":{"type":"refusal","category":"cyber"}}}"#)
        XCTAssertThrowsError(try AnthropicInsightProvider.draft(text: refused.text, stopReason: refused.stopReason, refusalCategory: refused.refusalCategory, servedBy: "")) {
            XCTAssertEqual($0 as? AIProviderError, .refused("cyber"))
        }
        XCTAssertThrowsError(try AnthropicInsightProvider.draft(text: String(plan.prefix(60)), stopReason: "max_tokens", refusalCategory: nil, servedBy: ""))
        var broken = MessageStream()
        broken.feed(line: #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)
        XCTAssertEqual(broken.error, "Overloaded")

        // The same from a reply that was not streamed, and from a local model that wraps its JSON in a fence.
        let whole: [String: Any] = ["model": "claude-opus-5-5", "stop_reason": "end_turn",
                                    "content": [["type": "thinking", "thinking": ""], ["type": "text", "text": plan]]]
        XCTAssertEqual(try AnthropicInsightProvider.draft(response: whole, model: "x").hookLine, 4)
        let fenced: [String: Any] = ["choices": [["finish_reason": "stop", "message": ["content": "Here is the plan:\n```json\n\(plan)\n```"]]]]
        XCTAssertEqual(try OpenAICompatibleInsightProvider.draft(completion: fenced, servedBy: "local").sections.count, 1)
        let cut: [String: Any] = ["choices": [["finish_reason": "length", "message": ["content": String(plan.prefix(50))]]]]
        XCTAssertThrowsError(try OpenAICompatibleInsightProvider.draft(completion: cut, servedBy: "local"))
    }
}
