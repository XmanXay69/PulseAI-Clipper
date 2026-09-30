import Foundation

public enum TranscriptParseError: Error, LocalizedError, Equatable {
    case empty
    case unrecognizedFormat
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .empty: return "The transcript file doesn't contain any text."
        case .unrecognizedFormat: return "PULSE couldn't recognise this transcript format. Use SRT, WebVTT, Whisper JSON or a PULSE transcript."
        case .malformed(let detail): return "The transcript file is damaged: \(detail)"
        }
    }
}

/// Parses subtitle and speech-to-text outputs into a word-level `Transcript`.
public enum TranscriptParser {
    public static func parse(data: Data, fileExtension: String) throws -> Transcript {
        switch fileExtension.lowercased() {
        case "srt":
            return try parseSRT(String(decoding: data, as: UTF8.self))
        case "vtt":
            return try parseVTT(String(decoding: data, as: UTF8.self))
        case "json":
            return try parseJSON(data)
        default:
            let text = String(decoding: data, as: UTF8.self)
            if text.hasPrefix("WEBVTT") { return try parseVTT(text) }
            if text.contains("-->") { return try parseSRT(text) }
            throw TranscriptParseError.unrecognizedFormat
        }
    }

    // MARK: SRT / VTT

    struct Cue {
        var start: Seconds
        var end: Seconds
        var text: String
        var speaker: String?
    }

    public static func parseSRT(_ text: String) throws -> Transcript {
        let cues = try parseCues(text)
        return try transcript(from: cues, source: .imported)
    }

    public static func parseVTT(_ text: String) throws -> Transcript {
        var body = text
        if body.hasPrefix("\u{FEFF}") { body.removeFirst() }
        guard body.hasPrefix("WEBVTT") else { throw TranscriptParseError.unrecognizedFormat }
        let cues = try parseCues(body)
        return try transcript(from: cues, source: .imported)
    }

    static func parseCues(_ text: String) throws -> [Cue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [Cue] = []
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let timing = lines[timingIndex].components(separatedBy: "-->")
            guard timing.count == 2 else { throw TranscriptParseError.malformed("bad timing line “\(lines[timingIndex])”") }
            // VTT cue settings follow the end time ("00:01.000 align:start").
            let endToken = timing[1].trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
            guard let start = Timecode.parse(timing[0]), let end = Timecode.parse(endToken) else {
                throw TranscriptParseError.malformed("bad timestamp “\(lines[timingIndex])”")
            }
            var textLines = Array(lines[(timingIndex + 1)...])
            var speaker: String?
            // WebVTT voice span: <v Speaker Name>text
            if let first = textLines.first, first.hasPrefix("<v ") , let close = first.firstIndex(of: ">") {
                speaker = String(first[first.index(first.startIndex, offsetBy: 3)..<close]).trimmingCharacters(in: .whitespaces)
                textLines[0] = String(first[first.index(after: close)...])
            }
            let joined = textLines.joined(separator: " ")
            let cleaned = stripTags(joined).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            // "SPEAKER: text" convention.
            var body = cleaned
            if speaker == nil, let colon = cleaned.firstIndex(of: ":"), cleaned.distance(from: cleaned.startIndex, to: colon) <= 24 {
                let candidate = String(cleaned[..<colon])
                if candidate.split(separator: " ").count <= 3, candidate.first?.isUppercase == true {
                    speaker = candidate
                    body = String(cleaned[cleaned.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                }
            }
            cues.append(Cue(start: start, end: end, text: body, speaker: speaker))
        }
        return cues.sorted { $0.start < $1.start }
    }

    static func stripTags(_ text: String) -> String {
        var result = ""
        var inTag = false
        for ch in text {
            if ch == "<" { inTag = true; continue }
            if ch == ">" { inTag = false; continue }
            if !inTag { result.append(ch) }
        }
        return result
    }

    /// Distributes cue time over its words proportionally to word length.
    static func transcript(from cues: [Cue], source: TranscriptSource) throws -> Transcript {
        guard !cues.isEmpty else { throw TranscriptParseError.empty }
        var speakerIDs: [String: Int] = [:]
        var words: [TranscriptWord] = []
        for cue in cues {
            let speakerID: Int? = cue.speaker.map { name in
                if let id = speakerIDs[name] { return id }
                let id = speakerIDs.count
                speakerIDs[name] = id
                return id
            }
            words.append(contentsOf: distribute(text: cue.text, over: TimeRange(start: cue.start, end: cue.end), speaker: speakerID))
        }
        guard !words.isEmpty else { throw TranscriptParseError.empty }
        let speakers = speakerIDs.map { Speaker(id: $0.value, name: $0.key) }.sorted { $0.id < $1.id }
        return Transcript(words: words, speakers: speakers, source: source)
    }

    public static func distribute(text: String, over range: TimeRange, speaker: Int? = nil) -> [TranscriptWord] {
        let tokens = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
        guard !tokens.isEmpty else { return [] }
        let weights = tokens.map { Double(max($0.count, 2)) }
        let total = weights.reduce(0, +)
        var cursor = range.start
        var result: [TranscriptWord] = []
        for (token, weight) in zip(tokens, weights) {
            let d = range.duration * weight / total
            result.append(TranscriptWord(text: token, start: cursor, end: cursor + d, speaker: speaker))
            cursor += d
        }
        return result
    }

    // MARK: JSON (PULSE, whisper.cpp, OpenAI verbose_json)

    public static func parseJSON(_ data: Data) throws -> Transcript {
        // 1. Native PULSE transcript.
        if let native = try? ProjectStore.makeDecoder().decode(Transcript.self, from: data), !native.words.isEmpty {
            return native
        }
        let isoDecoder = JSONDecoder()
        isoDecoder.dateDecodingStrategy = .iso8601
        if let native = try? isoDecoder.decode(Transcript.self, from: data), !native.words.isEmpty {
            return native
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranscriptParseError.unrecognizedFormat
        }
        // 2. OpenAI-style: { "words": [ { "word", "start", "end" } ] }
        if let wordList = root["words"] as? [[String: Any]], !wordList.isEmpty {
            let words = wordList.compactMap { item -> TranscriptWord? in
                guard let text = (item["word"] ?? item["text"]) as? String,
                      let start = number(item["start"]), let end = number(item["end"]) else { return nil }
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                return TranscriptWord(text: trimmed, start: start, end: end, confidence: number(item["probability"]).map { Float($0) })
            }
            guard !words.isEmpty else { throw TranscriptParseError.empty }
            return Transcript(language: root["language"] as? String, words: words, source: .whisper)
        }
        // 3. whisper.cpp: { "result": {"language"}, "transcription": [ { "offsets": {from,to} (ms), "text", "tokens": [...] } ] }
        if let segments = root["transcription"] as? [[String: Any]] {
            let language = (root["result"] as? [String: Any])?["language"] as? String
            let words = whisperCppWords(segments)
            guard !words.isEmpty else { throw TranscriptParseError.empty }
            return Transcript(language: language, words: words, source: .whisper)
        }
        // 4. Generic segments: { "segments": [ { "start", "end", "text", "words"? } ] }
        if let segments = root["segments"] as? [[String: Any]] {
            var words: [TranscriptWord] = []
            for seg in segments {
                if let segWords = seg["words"] as? [[String: Any]], !segWords.isEmpty {
                    for item in segWords {
                        guard let text = (item["word"] ?? item["text"]) as? String,
                              let start = number(item["start"]), let end = number(item["end"]) else { continue }
                        let trimmed = text.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty { words.append(TranscriptWord(text: trimmed, start: start, end: end)) }
                    }
                } else if let text = seg["text"] as? String, let start = number(seg["start"]), let end = number(seg["end"]) {
                    words.append(contentsOf: distribute(text: text, over: TimeRange(start: start, end: end)))
                }
            }
            guard !words.isEmpty else { throw TranscriptParseError.empty }
            return Transcript(language: root["language"] as? String, words: words, source: .whisper)
        }
        throw TranscriptParseError.unrecognizedFormat
    }

    static func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    /// Builds words from whisper.cpp segments. With `--max-len 1 --split-on-word` every segment is
    /// already a word; with full JSON we merge sub-word tokens ("▁Hel", "lo").
    static func whisperCppWords(_ segments: [[String: Any]]) -> [TranscriptWord] {
        var words: [TranscriptWord] = []
        for seg in segments {
            let offsets = seg["offsets"] as? [String: Any]
            let segStart = (number(offsets?["from"]) ?? 0) / 1000
            let segEnd = (number(offsets?["to"]) ?? 0) / 1000
            if let tokens = seg["tokens"] as? [[String: Any]], !tokens.isEmpty {
                var current: TranscriptWord?
                for token in tokens {
                    guard let raw = token["text"] as? String, !raw.hasPrefix("[_"), !raw.hasPrefix("<|") else { continue }
                    let tOffsets = token["offsets"] as? [String: Any]
                    let tStart = (number(tOffsets?["from"]) ?? segStart * 1000) / 1000
                    let tEnd = (number(tOffsets?["to"]) ?? segEnd * 1000) / 1000
                    let p = number(token["p"]).map { Float($0) }
                    let startsWord = raw.hasPrefix(" ") || current == nil
                    let piece = raw.trimmingCharacters(in: .whitespaces)
                    if piece.isEmpty { continue }
                    let isPunctuation = piece.allSatisfy { $0.isPunctuation }
                    if startsWord && !isPunctuation {
                        if let c = current { words.append(c) }
                        current = TranscriptWord(text: piece, start: tStart, end: tEnd, confidence: p)
                    } else {
                        current?.text += piece
                        current?.end = max(current?.end ?? tEnd, tEnd)
                    }
                }
                if let c = current { words.append(c) }
            } else if let text = seg["text"] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                if trimmed.split(separator: " ").count == 1 {
                    // Punctuation-only segments attach to the previous word.
                    if trimmed.allSatisfy({ $0.isPunctuation }), !words.isEmpty {
                        words[words.count - 1].text += trimmed
                    } else {
                        words.append(TranscriptWord(text: trimmed, start: segStart, end: segEnd))
                    }
                } else {
                    words.append(contentsOf: distribute(text: trimmed, over: TimeRange(start: segStart, end: segEnd)))
                }
            }
        }
        return words
    }

    // MARK: Export

    /// Writes an SRT file from caption pages or transcript sentences.
    public static func srt(from sentences: [(range: TimeRange, text: String)]) -> String {
        var out = ""
        for (i, item) in sentences.enumerated() {
            out += "\(i + 1)\n"
            out += "\(srtTime(item.range.start)) --> \(srtTime(item.range.end))\n"
            out += "\(item.text)\n\n"
        }
        return out
    }

    static func srtTime(_ t: Seconds) -> String {
        let ms = Int((max(0, t) * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
    }
}
