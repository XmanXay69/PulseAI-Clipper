import XCTest
@testable import PulseCore

final class ChatReplayTests: XCTestCase {
    func testParsesTheCommonFormats() throws {
        let twitch = #"{"video":{"title":"x"},"comments":[{"content_offset_seconds":12.5,"commenter":{"display_name":"Ann"},"message":{"body":"KEKW"}},{"content_offset_seconds":3,"commenter":{"display_name":"Bo"},"message":{"body":"hi"}}]}"#
        let t = try ChatReplayParser.parse(Data(twitch.utf8))
        XCTAssertEqual(t.format, "TwitchDownloader JSON")
        XCTAssertEqual(t.messages.map(\.time), [3, 12.5], "sorted by time")
        XCTAssertEqual(t.messages.last?.author, "Ann")

        let cd = #"[{"time_in_seconds": 61.2, "message": "LETS GO", "author": {"name": "Cy"}}]"#
        XCTAssertEqual(try ChatReplayParser.parse(Data(cd.utf8)).messages.first?.text, "LETS GO")

        let yt = """
        {"replayChatItemAction":{"actions":[{"addChatItemAction":{"item":{"liveChatTextMessageRenderer":{"message":{"runs":[{"text":"no way "},{"emoji":{"shortcuts":[":fire:"]}}]},"authorName":{"simpleText":"Dee"}}}}}],"videoOffsetTimeMsec":"90500"}}
        {"replayChatItemAction":{"actions":[{"addChatItemAction":{"item":{"liveChatTextMessageRenderer":{"message":{"runs":[{"text":"lol"}]},"authorName":{"simpleText":"Eve"}}}}}],"videoOffsetTimeMsec":"91000"}}
        """
        let y = try ChatReplayParser.parse(Data(yt.utf8))
        XCTAssertEqual(y.format, "YouTube live chat")
        XCTAssertEqual(y.messages.first?.time ?? 0, 90.5, accuracy: 1e-9)
        XCTAssertEqual(y.messages.first?.text, "no way :fire:")

        let csv = "time_in_seconds,author,message\n5.0,Fay,\"W, huge\"\n6.5,Gus,KEKW\n"
        let c = try ChatReplayParser.parse(Data(csv.utf8), fileName: "chat.csv")
        XCTAssertEqual(c.messages.first?.text, "W, huge")

        let text = "[0:00:05] Hal: hello\n[0:01:10] Ivy: KEKW KEKW\n[1:02:03] Jo: clip it\n"
        let l = try ChatReplayParser.parse(Data(text.utf8), fileName: "chat.txt")
        XCTAssertEqual(l.messages.map(\.time), [5, 70, 3723])

        XCTAssertThrowsError(try ChatReplayParser.parse(Data("just some words".utf8)))
    }

    func testLexiconSeesLaughsAndHype() {
        XCTAssertGreaterThan(ChatLexicon.score("KEKW KEKW").laugh, 1)
        XCTAssertGreaterThan(ChatLexicon.score("LMAOOOO 💀").laugh, 1)
        XCTAssertGreaterThan(ChatLexicon.score("CLIP IT").hype, 1)
        XCTAssertGreaterThan(ChatLexicon.score("PogU W").hype, 1)
        XCTAssertEqual(ChatLexicon.score("what's for dinner").laugh, 0)
    }

    /// Steady chatter, then a laughing burst 5 s after a moment at 300 s.
    func chat(burstAt moment: Seconds) -> ChatLog {
        var messages: [ChatMessage] = []
        for t in stride(from: 0.0, to: 600, by: 2) { messages.append(ChatMessage(time: t, author: "u", text: "hey")) }
        for k in 0..<60 { messages.append(ChatMessage(time: moment + 5 + Double(k) * 0.1, author: "u\(k)", text: k % 2 == 0 ? "KEKW" : "LMAO")) }
        return ChatLog(messages: messages, format: "test")
    }

    func testBurstLandsOnTheMomentNotTheReplies() {
        let signals = ChatSignals.compute(chat(burstAt: 300), duration: 600, step: 0.5)
        let peak = signals.activity.indices.max { signals.activity[$0] < signals.activity[$1] }!
        XCTAssertEqual(Double(peak) * 0.5, 302, accuracy: 4, "lag-corrected back to the moment")
        XCTAssertGreaterThan(signals.laughter[peak], 0.3)
        XCTAssertLessThan(signals.activity[Int(100 / 0.5)], 0.1, "normal chatter isn't a moment")
    }

    func testChatPicksTheMomentAudioAloneMissed() {
        // Audio has a loud spike at 450 s that chat ignored; chat erupts at 300 s over normal-volume talking.
        let duration: Seconds = 600
        let base = ClipGenerationInput(assetID: Fixtures.assetID, duration: duration,
                                       audio: Fixtures.audio(duration: duration, spikes: [450]),
                                       transcript: Fixtures.transcript(duration: duration), visual: nil)
        var withChat = base
        withChat.chat = chat(burstAt: 300)
        let settings = ClipGenerationSettings(targetDuration: 30, minimumPotential: 0, maxCandidates: 3)
        let plain = ClipGenerator(input: base, settings: settings).generate()
        let chatty = ClipGenerator(input: withChat, settings: settings).generate()
        XCTAssertFalse(plain.prefix(1).contains { $0.range.contains(300) })
        XCTAssertTrue(chatty.prefix(2).contains { $0.range.contains(301) }, "\(chatty.map(\.range))")
        XCTAssertTrue(chatty.first { $0.range.contains(301) }?.tags.contains(.funny) ?? false, "chat laughter tags it funny")
    }

    func testChatSurvivesTheAnalysisFile() throws {
        var analysis = MediaAnalysis(assetID: Fixtures.assetID, duration: 60)
        analysis.chat = ChatLog(messages: [ChatMessage(time: 1, text: "W")], format: "test", offset: -3)
        let data = try JSONEncoder().encode(analysis)
        let back = try JSONDecoder().decode(MediaAnalysis.self, from: data)
        XCTAssertEqual(back.chat?.offset, -3)
        // Old analysis files without chat still load.
        let old = try JSONEncoder().encode(MediaAnalysis(assetID: Fixtures.assetID, duration: 60))
        XCTAssertNil(try JSONDecoder().decode(MediaAnalysis.self, from: old).chat)
    }
}
