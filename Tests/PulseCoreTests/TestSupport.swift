import Foundation
@testable import PulseCore

/// Helpers for building synthetic analysis data.
enum Fixtures {
    static let assetID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    static func mediaAsset(duration: Seconds = 600, width: Int = 1920, height: Int = 1080) -> MediaAsset {
        MediaAsset(id: assetID, name: "Stream.mp4", path: "/tmp/Stream.mp4", kind: .video, role: .main,
                   metadata: MediaMetadata(duration: duration, width: width, height: height, frameRate: 60, hasVideo: true,
                                           hasAudio: true, audioTrackCount: 1, audioChannels: 2, audioSampleRate: 48000))
    }

    /// Words spoken at a steady pace with sentence breaks every 8 words.
    static func transcript(duration: Seconds, wordsPerSecond: Double = 2.5, special: [(Seconds, String)] = []) -> Transcript {
        var words: [TranscriptWord] = []
        let vocab = ["so", "we", "are", "going", "to", "try", "this", "again", "and", "then", "maybe", "it", "works", "right", "okay", "now"]
        var t = 0.5
        var i = 0
        let step = 1 / wordsPerSecond
        while t < duration - 1 {
            // Leave a 3 s pause every 40 s so silence detection has something to find.
            if Int(t) % 40 == 20 && Int(t) > 0 {
                t += 3
                continue
            }
            var text = vocab[i % vocab.count]
            if (i + 1) % 8 == 0 { text += "." }
            words.append(TranscriptWord(text: text, start: t, end: t + step * 0.8))
            t += step
            i += 1
        }
        for (time, text) in special {
            words.removeAll { abs($0.start - time) < 0.3 }
            words.append(TranscriptWord(text: text, start: time, end: time + 0.3))
        }
        return Transcript(language: "en", words: words.sorted { $0.start < $1.start }, source: .demo)
    }

    /// Quiet speech-level audio with loud spikes at the given times.
    static func audio(duration: Seconds, hop: Seconds = 0.1, spikes: [Seconds] = [], silences: [TimeRange] = []) -> AudioFeatureSeries {
        let n = Int(duration / hop)
        var rms = [Float](repeating: -24, count: n)
        var flux = [Float](repeating: 0.1, count: n)
        for i in 0..<n {
            // Gentle variation.
            rms[i] += Float(sin(Double(i) * 0.37)) * 2
        }
        for s in spikes {
            let a = Int(s / hop)
            for k in a..<min(n, a + Int(2.5 / hop)) {
                rms[k] = -6
                flux[k] = 3
            }
        }
        for r in silences {
            for k in Int(r.start / hop)..<min(n, Int(r.end / hop)) { rms[k] = -70 }
        }
        return AudioFeatureSeries(hop: hop, rmsDB: rms, peakDB: rms.map { $0 + 6 }, zeroCrossingRate: [Float](repeating: 0.1, count: n), spectralFlux: flux)
    }

    static func simpleTimeline(clipDuration: Seconds = 10) -> Timeline {
        var t = Timeline.empty(name: "Test", canvas: .vertical1080)
        let group = UUID()
        let v = TimelineClip(name: "V", content: .media(assetID: assetID), start: 0, sourceIn: 100, sourceDuration: clipDuration, linkGroup: group, role: .gameplay)
        let a = TimelineClip(name: "A", content: .media(assetID: assetID), start: 0, sourceIn: 100, sourceDuration: clipDuration, linkGroup: group, role: .microphone)
        t.tracks[0].clips = [v]
        t.tracks[3].clips = [a]
        return t
    }
}
