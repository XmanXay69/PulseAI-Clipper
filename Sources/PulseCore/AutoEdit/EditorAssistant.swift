import Foundation

/// What you asked the editor assistant to do (#498), read off plain English by rules — no model, no
/// network — so "cut the intro" or "make the hook punchier" turns into an ordinary, undoable edit.
public enum EditorIntent: Equatable, Sendable {
    /// Tighten the pauses between sentences; `minimum` is the pause left in place.
    case tightenPauses(minimum: Seconds)
    case trimStart(Seconds)
    case trimEnd(Seconds)
    /// Shorten the edit by roughly this fraction (0.1…0.6).
    case shorter(by: Double)
    case punchierHook
    case captions(on: Bool)
    case captionStyle(String)
    case music(on: Bool)
    case musicLevel(deltaDB: Double)
    case zooms(more: Bool)
    case removeZooms
    case moreEntertaining
    case progressBar(on: Bool)
    case addMarker(String)
    case speed(Double)
    case closeGaps
    case roomTone
    case removeAI
    case undo
    case redo
    case unknown(String)
}

public enum EditorAssistant {
    /// What you can say, for the empty state.
    public static let examples = [
        "cut the first 10 seconds", "make the hook punchier", "tighten the pauses", "make it 20 % shorter",
        "add captions", "captions like TikTok", "turn the music down", "fewer zooms", "add a progress bar",
        "speed up 1.25×", "fill the gaps with room tone", "undo",
    ]

    public static func parse(_ raw: String) -> EditorIntent {
        let text = normalize(raw)
        guard !text.isEmpty else { return .unknown(raw) }
        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }
        let seconds = Self.seconds(in: text)
        let percent = Self.percent(in: text)

        if text == "undo" || text.hasPrefix("undo ") { return .undo }
        if text == "redo" || text.hasPrefix("redo ") { return .redo }

        // The hook / the opening.
        if has("hook") && has("punch", "stronger", "better", "harder", "snappier", "grab") { return .punchierHook }
        if has("cold open", "start with the best", "open with the best") { return .punchierHook }

        // Cutting a stretch off either end.
        if has("intro", "beginning", "first", "start", "opening") && has("cut", "trim", "remove", "drop", "skip", "lose", "delete") {
            if has("last", "end", "ending", "outro") == false || has("first", "intro", "beginning") {
                return .trimStart(seconds ?? 5)
            }
        }
        if has("outro", "ending", "last", "the end", "tail") && has("cut", "trim", "remove", "drop", "lose", "delete") {
            return .trimEnd(seconds ?? 5)
        }

        // Pauses and length.
        if has("jump cut", "jumpcut", "tighten", "tighter", "pauses", "silence", "dead air", "gaps between") && !has("room tone", "fill") {
            let minimum: Seconds = has("very", "really", "all", "hard", "aggressive") ? 0.15 : (has("a bit", "little", "slightly", "gently") ? 0.45 : 0.3)
            return .tightenPauses(minimum: minimum)
        }
        if has("shorter", "shorten", "trim it down", "cut it down", "too long", "tighter overall") {
            if let percent { return .shorter(by: (percent / 100).clamped(0.1, 0.6)) }
            if has("much", "a lot", "way") { return .shorter(by: 0.4) }
            if has("bit", "little", "slightly") { return .shorter(by: 0.15) }
            return .shorter(by: 0.25)
        }
        if has("room tone", "fill the gaps", "fill gaps") { return .roomTone }
        if has("close the gaps", "close gaps", "remove the gaps", "remove gaps", "no gaps") { return .closeGaps }

        // Captions.
        if has("caption", "subtitle") {
            if has("remove", "off", "hide", "no ", "without", "delete", "get rid") { return .captions(on: false) }
            if has("like", "style", "preset", "look") {
                for name in ["tiktok", "bold", "karaoke", "clean", "neon", "minimal", "boxed", "hormozi", "beast", "podcast", "news", "retro", "outline", "classic"] where text.contains(name) {
                    return .captionStyle(name)
                }
            }
            return .captions(on: true)
        }

        // Music.
        if has("music", "song", "soundtrack", "bed") {
            if has("louder", "up", "more") && !has("turn down", "down") { return .musicLevel(deltaDB: 3) }
            if has("quieter", "down", "softer", "lower", "too loud") { return .musicLevel(deltaDB: -3) }
            if has("remove", "mute", "no ", "without", "off", "delete", "kill", "get rid") { return .music(on: false) }
            return .music(on: true)
        }

        // Zooms, energy, chrome.
        if has("zoom", "punch-in", "punch in", "punchin") {
            if has("no ", "remove", "without", "none", "get rid", "delete") { return .removeZooms }
            if has("fewer", "less", "calmer", "too many", "tone down") { return .zooms(more: false) }
            return .zooms(more: true)
        }
        if has("entertaining", "more energy", "more exciting", "spice", "livelier", "more fun") { return .moreEntertaining }
        if has("progress bar") { return .progressBar(on: !has("remove", "no ", "without", "off", "delete")) }
        if has("marker") {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let called = name.range(of: "called ", options: .caseInsensitive).map { String(name[$0.upperBound...]) }
                ?? name.range(of: "named ", options: .caseInsensitive).map { String(name[$0.upperBound...]) }
            return .addMarker(called?.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) ?? "Marker")
        }
        if has("speed", "faster", "slower", "slow down", "slow it", "speed up", "quicker") {
            if let x = multiplier(in: text) { return .speed(x) }
            if has("slow") { return .speed(0.75) }
            return .speed(1.25)
        }
        if has("remove ai", "undo the ai", "strip ai", "no ai edits", "remove the ai") { return .removeAI }
        return .unknown(raw)
    }

    /// One line on what the intent will do, for the confirmation.
    public static func describe(_ intent: EditorIntent) -> String {
        switch intent {
        case .tightenPauses(let m): return String(format: "Tighten the pauses, leaving %.2f s", m)
        case .trimStart(let s): return "Cut the first \(Self.seconds(s))"
        case .trimEnd(let s): return "Cut the last \(Self.seconds(s))"
        case .shorter(let f): return "Make it about \(Int((f * 100).rounded())) % shorter"
        case .punchierHook: return "Open on the most exciting moment, then the story"
        case .captions(let on): return on ? "Add captions" : "Hide the captions"
        case .captionStyle(let name): return "Captions in the \(name.capitalized) style"
        case .music(let on): return on ? "Add a music bed" : "Mute the music"
        case .musicLevel(let d): return String(format: "Music %@ by %.0f dB", d < 0 ? "down" : "up", abs(d))
        case .zooms(let more): return more ? "More punch-in zooms" : "Fewer punch-in zooms"
        case .removeZooms: return "Remove the AI zooms"
        case .moreEntertaining: return "Run Make More Entertaining"
        case .progressBar(let on): return on ? "Add a progress bar" : "Remove the progress bar"
        case .addMarker(let name): return "Add a marker named “\(name)” at the playhead"
        case .speed(let x): return String(format: "Set the selected clips to %.2f×", x)
        case .closeGaps: return "Close the gaps between clips"
        case .roomTone: return "Fill short gaps with room tone"
        case .removeAI: return "Remove every AI edit"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .unknown: return "Not sure what you mean"
        }
    }

    // MARK: Parsing helpers

    static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "please", with: "")
            .replacingOccurrences(of: "can you", with: "")
            .replacingOccurrences(of: "could you", with: "")
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: "percent", with: "%")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "10 seconds", "10s", "half a minute", "a minute", "1:30".
    static func seconds(in text: String) -> Seconds? {
        if text.contains("half a minute") { return 30 }
        if text.contains("a minute") || text.contains("one minute") { return 60 }
        let pattern = #"(\d+(?:[.,]\d+)?)\s*(seconds?|secs?|s\b|minutes?|mins?|m\b)"#
        if let match = text.range(of: pattern, options: .regularExpression) {
            let found = String(text[match])
            let number = Double(found.prefix { "0123456789.,".contains($0) }.replacingOccurrences(of: ",", with: ".")) ?? 0
            return found.contains("m") ? number * 60 : number
        }
        if let match = text.range(of: #"(\d+):(\d{2})"#, options: .regularExpression) {
            let parts = text[match].split(separator: ":").compactMap { Double($0) }
            if parts.count == 2 { return parts[0] * 60 + parts[1] }
        }
        return nil
    }

    static func percent(in text: String) -> Double? {
        guard let match = text.range(of: #"(\d+)\s*%"#, options: .regularExpression) else {
            if text.contains("half") { return 50 }
            if text.contains("a third") { return 33 }
            if text.contains("a quarter") { return 25 }
            return nil
        }
        return Double(text[match].prefix { $0.isNumber })
    }

    static func multiplier(in text: String) -> Double? {
        guard let match = text.range(of: #"(\d+(?:[.,]\d+)?)\s*x"#, options: .regularExpression) else { return nil }
        let number = text[match].prefix { "0123456789.,".contains($0) }.replacingOccurrences(of: ",", with: ".")
        guard let x = Double(number), x >= 0.1, x <= 8 else { return nil }
        return x
    }

    /// "12 s" under a minute, else "1:30".
    public static func seconds(_ s: Seconds) -> String {
        s < 60 ? "\(Int(s.rounded())) s" : Timecode.short(s)
    }
}
