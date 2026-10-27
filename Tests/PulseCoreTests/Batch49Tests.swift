import XCTest
@testable import PulseCore

final class Batch49Tests: XCTestCase {
    // MARK: #481 — moments found while recording

    func testLiveMeterFindsABurstOnceAndNotTheRoomTone() {
        var detector = LiveMomentDetector()
        var found: [LiveMoment] = []
        var t: Seconds = 0
        // 40 s of ordinary speech around −22 dB.
        while t < 40 { if let m = detector.feed(levelDB: -22 + Float(sin(t)) * 2, at: t) { found.append(m) }; t += 0.25 }
        XCTAssertTrue(found.isEmpty, "steady speech is not a moment")
        // A shout at −6 dB for a second.
        while t < 41 { if let m = detector.feed(levelDB: -6, at: t) { found.append(m) }; t += 0.25 }
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].time, 40, accuracy: 0.26)
        XCTAssertGreaterThan(found[0].strength, 0.5)
        // Back to speech, then another shout 5 s later: inside the refractory window, so no second moment…
        while t < 46 { if let m = detector.feed(levelDB: -22, at: t) { found.append(m) }; t += 0.25 }
        while t < 47 { if let m = detector.feed(levelDB: -5, at: t) { found.append(m) }; t += 0.25 }
        XCTAssertEqual(found.count, 1)
        // …but one 30 s later counts.
        while t < 75 { if let m = detector.feed(levelDB: -22, at: t) { found.append(m) }; t += 0.25 }
        while t < 76 { if let m = detector.feed(levelDB: -5, at: t) { found.append(m) }; t += 0.25 }
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(detector.moments.count, 2)
        // A blip shorter than the hold is nothing.
        var quick = LiveMomentDetector()
        for i in 0..<120 { _ = quick.feed(levelDB: -24, at: Double(i) * 0.25) }
        XCTAssertNil(quick.feed(levelDB: -4, at: 30))
        XCTAssertNil(quick.feed(levelDB: -24, at: 30.25))
        XCTAssertTrue(quick.moments.isEmpty)
        // Silence never makes a whisper a moment: the baseline has a floor.
        var silent = LiveMomentDetector()
        for i in 0..<200 { _ = silent.feed(levelDB: -60, at: Double(i) * 0.25) }
        for i in 200..<210 { _ = silent.feed(levelDB: -40, at: Double(i) * 0.25) }
        XCTAssertTrue(silent.moments.isEmpty)
        let events = LiveMomentDetector.events(from: found)
        XCTAssertEqual(events.map(\.kind), [.live, .live])
        XCTAssertEqual(HUDEvent.Kind.live.tag, .hype)
        XCTAssertLessThan(HUDEvent.Kind.live.weight, HUDEvent.Kind.marked.weight, "a pressed clip-it still outranks a guessed moment")
    }

    // MARK: #488 — game event logs

    func testRiotLiveClientLogParses() throws {
        let json = """
        {"Events":[
          {"EventID":0,"EventName":"GameStart","EventTime":0},
          {"EventID":1,"EventName":"FirstBlood","EventTime":95.2,"Recipient":"Me"},
          {"EventID":2,"EventName":"ChampionKill","EventTime":95.2,"KillerName":"Me","VictimName":"Them","Assisters":[]},
          {"EventID":3,"EventName":"Multikill","EventTime":131.0,"KillerName":"Me","KillStreak":3},
          {"EventID":4,"EventName":"DragonKill","EventTime":400.5,"DragonType":"Fire","KillerName":"Me"},
          {"EventID":5,"EventName":"Ace","EventTime":900,"Acer":"Me","AcingTeam":"ORDER"},
          {"EventID":6,"EventName":"GameEnd","EventTime":1800,"Result":"Win"}
        ]}
        """
        let parsed = try XCTUnwrap(GameEventLog.parse(data: Data(json.utf8)))
        XCTAssertEqual(parsed.source, .riotLiveClient)
        XCTAssertEqual(parsed.events.map(\.kind), [.kill, .kill, .multiKill, .objective, .clutch, .win])
        XCTAssertEqual(parsed.events[0].text, "FIRST BLOOD")
        XCTAssertEqual(parsed.events[1].text, "KILL: Me → Them")
        XCTAssertEqual(parsed.events[2].text, "TRIPLE KILL")
        XCTAssertEqual(parsed.events[3].text, "DRAGON KILL")
        XCTAssertEqual(parsed.events[5].text, "VICTORY")
        XCTAssertEqual(parsed.events[5].time, 1800)
        XCTAssertNil(GameEventLog.parse(data: Data(#"{"Events":[{"EventID":0,"EventName":"GameStart","EventTime":0}]}"#.utf8)), "nothing clip-worthy")
    }

    func testCSVAndJSONLogsParseAndClocksShift() throws {
        let csv = """
        # time,kind,text
        time,kind,text
        5:12,kill,Headshot
        1:05:00.5,multi-kill,
        312,victory,GG
        notatime,kill,x
        400,unknownkind,x
        """
        let parsed = try XCTUnwrap(GameEventLog.parse(data: Data(csv.utf8)))
        XCTAssertEqual(parsed.source, .csv)
        XCTAssertEqual(parsed.events.map(\.time), [312, 3900.5, 312])
        XCTAssertEqual(parsed.events.map(\.kind), [.kill, .multiKill, .win])
        XCTAssertEqual(parsed.events[0].text, "Headshot")
        XCTAssertEqual(parsed.events[1].text, "MULTI-KILL")
        let json = try XCTUnwrap(GameEventLog.parse(data: Data(#"[{"time":"2:00","kind":"Objective","text":"Capture A","confidence":0.8},{"time":10,"kind":"death"}]"#.utf8)))
        XCTAssertEqual(json.source, .json)
        XCTAssertEqual(json.events[0].time, 120)
        XCTAssertEqual(json.events[0].confidence, 0.8)
        XCTAssertEqual(json.events[1].text, "DEATH")
        XCTAssertNil(GameEventLog.parse(data: Data("hello".utf8)))
        XCTAssertEqual(GameEventLog.seconds(from: "1:02:03"), 3723)
        XCTAssertNil(GameEventLog.seconds(from: "1:xx"))
        // The game's 0:00 sits 90 s into the recording; events before the recording started are dropped.
        let shifted = GameEventLog.shift([HUDEvent(time: 10, kind: .kill, text: "K"), HUDEvent(time: -100, kind: .kill, text: "early")], by: 90)
        XCTAssertEqual(shifted.map(\.time), [100])
        // Merging skips what the screen reader already saw within a second.
        let existing = [HUDEvent(time: 100.4, kind: .kill, text: "DOUBLE KILL banner")]
        let merged = GameEventLog.merge(existing, adding: [HUDEvent(time: 100, kind: .kill, text: "api"), HUDEvent(time: 100, kind: .objective, text: "obj"), HUDEvent(time: 50, kind: .kill, text: "k")])
        XCTAssertEqual(merged.map(\.time), [50, 100, 100.4])
        XCTAssertEqual(merged.map(\.kind), [.kill, .objective, .kill])
    }

    func testAssetsCarryGameEventsAndOldOnesDecode() throws {
        var asset = MediaAsset(name: "ranked", path: "/tmp/r.mov", kind: .video, role: .gameplay)
        XCTAssertTrue(asset.gameEvents.isEmpty)
        asset.gameEvents = [HUDEvent(time: 12, kind: .kill, text: "K")]
        let back = try JSONDecoder().decode(MediaAsset.self, from: JSONEncoder().encode(asset))
        XCTAssertEqual(back.gameEvents.count, 1)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(asset)) as! [String: Any]
        json["gameEvents"] = nil
        XCTAssertTrue(try JSONDecoder().decode(MediaAsset.self, from: JSONSerialization.data(withJSONObject: json)).gameEvents.isEmpty)
    }
}
