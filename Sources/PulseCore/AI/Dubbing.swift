import Foundation

/// A dub for a second-language channel (#486): the translated captions spoken by a synthesized voice, laid
/// on their own track with the original voice lowered underneath.
public struct DubLine: Hashable, Sendable {
    public var text: String
    /// Timeline time.
    public var start: Seconds
    public var end: Seconds
    public var speaker: Int?

    public init(text: String, start: Seconds, end: Seconds, speaker: Int? = nil) {
        self.text = text
        self.start = start
        self.end = end
        self.speaker = speaker
    }

    public var duration: Seconds { max(0.2, end - start) }
    public var wordCount: Int { text.split(whereSeparator: { $0 == " " }).count }
}

public enum DubPlanner {
    public static let trackName = "Dub"

    /// One line per sentence of the track as it plays on the timeline (cuts respected): a break at sentence
    /// punctuation, a pause over 0.8 s, a change of speaker, or 24 words.
    public static func lines(from track: CaptionTrack, in timeline: Timeline) -> [DubLine] {
        let words = CaptionLayoutEngine.timelineWords(track, in: timeline)
        var out: [DubLine] = []
        var current: [TimedCaptionWord] = []
        func flush() {
            guard let first = current.first, let last = current.last else { return }
            out.append(DubLine(text: current.map(\.text).joined(separator: " "), start: first.start, end: max(last.end, first.start + 0.2), speaker: first.speaker))
            current = []
        }
        for word in words {
            if let last = current.last {
                let gap = word.start - last.end
                let punctuated = last.text.hasSuffix(".") || last.text.hasSuffix("!") || last.text.hasSuffix("?")
                if punctuated || gap > 0.8 || gap < -0.05 || word.speaker != last.speaker || current.count >= 24 { flush() }
            }
            current.append(word)
        }
        flush()
        return out
    }

    /// The synthesizer's speech rate (0…1, 0.5 ≈ 160 words a minute) that fits `wordCount` words into
    /// `seconds`, kept between 0.42 (unhurried) and 0.62 (brisk but clear).
    public static func rate(wordCount: Int, seconds: Seconds) -> Double {
        guard wordCount > 0, seconds > 0 else { return 0.5 }
        let wordsPerSecond = Double(wordCount) / seconds
        // 0.5 ≈ 2.7 words a second; the scale is roughly linear around it.
        let rate = 0.5 * wordsPerSecond / 2.7
        return rate.clamped(0.42, 0.62)
    }

    /// Adds the dub as one clip on a new audio track and lowers the original dialogue under it. Returns how
    /// many original voice clips were lowered.
    @discardableResult
    public static func place(_ timeline: inout Timeline, dubAssetID: UUID, duration: Seconds, language: String, duckOriginalBy dB: Double = -18) -> Int {
        let name = "A\(timeline.audioTracks.count + 1) \(trackName) (\(language))"
        var track = Track(kind: .audio, name: name)
        var clip = TimelineClip(name: "\(trackName) · \(CaptionTranslator.name(for: language))", content: .media(assetID: dubAssetID), start: 0,
                                sourceDuration: max(0.1, duration), role: .microphone, aiGenerated: true)
        clip.audio.normalize = true
        track.clips = [clip]
        timeline.tracks.append(track)
        var lowered = 0
        for t in timeline.tracks.indices where timeline.tracks[t].kind == .audio && timeline.tracks[t].id != track.id {
            for c in timeline.tracks[t].clips.indices {
                let role = timeline.tracks[t].clips[c].role
                guard role == .microphone || role == .main || role == .camera || role == .webcam else { continue }
                timeline.tracks[t].clips[c].audio.gainDB += dB
                lowered += 1
            }
        }
        return lowered
    }
}
