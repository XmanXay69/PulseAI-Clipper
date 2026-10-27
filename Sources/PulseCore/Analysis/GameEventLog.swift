import Foundation

/// Exact game timestamps from a game's own API (#488): Riot's Live Client Data event log, or a plain CSV /
/// JSON list from any other tool. Events arrive on the game's clock; `shift` moves them onto the recording's.
public enum GameEventLog {
    public enum Source: String, Sendable {
        case riotLiveClient = "Riot Live Client Data"
        case csv = "CSV"
        case json = "JSON"
    }

    public struct Parsed: Sendable, Hashable {
        public var source: Source
        public var events: [HUDEvent]
    }

    /// Reads any of the supported formats; nil when nothing in it looks like events.
    public static func parse(data: Data) -> Parsed? {
        if let object = try? JSONSerialization.jsonObject(with: data) {
            if let dict = object as? [String: Any] {
                if let riot = dict["Events"] as? [[String: Any]] {
                    let events = riot.compactMap(riotEvent)
                    return events.isEmpty ? nil : Parsed(source: .riotLiveClient, events: events)
                }
                if let list = dict["events"] as? [[String: Any]] {
                    let events = list.compactMap(genericEvent)
                    return events.isEmpty ? nil : Parsed(source: .json, events: events)
                }
            }
            if let list = object as? [[String: Any]] {
                let events = list.compactMap(genericEvent)
                return events.isEmpty ? nil : Parsed(source: .json, events: events)
            }
        }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let events = parseCSV(text)
        return events.isEmpty ? nil : Parsed(source: .csv, events: events)
    }

    /// Riot: {"EventID":3,"EventName":"ChampionKill","EventTime":312.4,"KillerName":"…","VictimName":"…"}
    public static func riotEvent(_ e: [String: Any]) -> HUDEvent? {
        guard let name = e["EventName"] as? String, let time = (e["EventTime"] as? NSNumber)?.doubleValue else { return nil }
        let killer = (e["KillerName"] as? String) ?? ""
        let victim = (e["VictimName"] as? String) ?? ""
        switch name {
        case "ChampionKill": return HUDEvent(time: time, kind: .kill, text: killer.isEmpty ? "KILL" : "KILL: \(killer) → \(victim)".trimmingCharacters(in: .whitespaces))
        case "FirstBlood": return HUDEvent(time: time, kind: .kill, text: "FIRST BLOOD")
        case "Multikill":
            let streak = (e["KillStreak"] as? NSNumber)?.intValue ?? 2
            let names = [2: "DOUBLE KILL", 3: "TRIPLE KILL", 4: "QUADRA KILL", 5: "PENTA KILL"]
            return HUDEvent(time: time, kind: .multiKill, text: names[streak] ?? "MULTI KILL")
        case "Ace": return HUDEvent(time: time, kind: .clutch, text: "ACE")
        case "DragonKill", "BaronKill", "HeraldKill", "HordeKill", "TurretKilled", "InhibKilled", "FirstBrick", "AtakhanKill":
            return HUDEvent(time: time, kind: .objective, text: name.replacingOccurrences(of: "Kill", with: " KILL").replacingOccurrences(of: "Killed", with: " KILLED").uppercased())
        case "GameEnd":
            let won = ((e["Result"] as? String) ?? "").lowercased() == "win"
            return HUDEvent(time: time, kind: won ? .win : .loss, text: won ? "VICTORY" : "DEFEAT")
        default: return nil
        }
    }

    /// {"time": 312.4, "kind": "kill", "text": "…"} — `time` may also be "5:12" or "1:05:12".
    public static func genericEvent(_ e: [String: Any]) -> HUDEvent? {
        let time: Seconds?
        if let n = e["time"] as? NSNumber { time = n.doubleValue } else if let s = e["time"] as? String { time = seconds(from: s) } else { time = nil }
        guard let time, let kindName = (e["kind"] as? String)?.lowercased(), let kind = kind(named: kindName) else { return nil }
        let text = (e["text"] as? String) ?? kind.displayName.uppercased()
        let confidence = (e["confidence"] as? NSNumber)?.doubleValue ?? 1
        return HUDEvent(time: time, kind: kind, text: text, confidence: confidence.clamped(0, 1))
    }

    /// time,kind,text — a header line is optional; `#` lines are comments.
    static func parseCSV(_ text: String) -> [HUDEvent] {
        var out: [HUDEvent] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let cells = line.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            guard cells.count >= 2, let time = seconds(from: cells[0]), let kind = kind(named: cells[1].lowercased()) else { continue }
            out.append(HUDEvent(time: time, kind: kind, text: cells.count > 2 && !cells[2].isEmpty ? cells[2] : kind.displayName.uppercased()))
        }
        return out
    }

    /// "kill", "multi-kill", "Multi Kill", "objective"… → the banner kind.
    static func kind(named name: String) -> HUDEvent.Kind? {
        let key = name.lowercased().filter { $0.isLetter }
        if let exact = HUDEvent.Kind.allCases.first(where: { $0.rawValue.lowercased() == key }) { return exact }
        switch key {
        case "multikill", "doublekill", "triplekill", "quadrakill", "pentakill": return .multiKill
        case "victory", "won": return .win
        case "defeat", "lost": return .loss
        case "died", "killed": return .death
        case "ace": return .clutch
        case "rankup", "levelup": return .levelUp
        case "obj", "dragon", "baron", "turret", "goal", "capture": return .objective
        default: return nil
        }
    }

    /// "312.4", "5:12", "1:05:12.5" → seconds.
    public static func seconds(from text: String) -> Seconds? {
        let parts = text.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
    }

    /// The events moved onto the recording's clock: `offset` is where the game's 0:00 sits in the recording.
    public static func shift(_ events: [HUDEvent], by offset: Seconds) -> [HUDEvent] {
        events.map { var e = $0; e.time += offset; return e }.filter { $0.time >= 0 }
    }

    /// Adds `incoming` to `existing`, dropping an incoming event of the same kind within a second of one
    /// already there (a banner the screen reader also saw), sorted by time.
    public static func merge(_ existing: [HUDEvent], adding incoming: [HUDEvent]) -> [HUDEvent] {
        var out = existing
        for e in incoming where !out.contains(where: { $0.kind == e.kind && abs($0.time - e.time) <= 1 }) {
            out.append(e)
        }
        return out.sorted { $0.time < $1.time }
    }
}
