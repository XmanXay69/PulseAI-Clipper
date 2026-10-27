import PulseCore
import PulseEngine
import SwiftUI

/// The mix bus level next to the transport (#194): peak hold, and a red dot that stays lit once the bus
/// clips until you click it.
struct MasterMeter: View {
    @ObservedObject var session: ProjectSession
    @ObservedObject var playback: PlaybackController
    @State private var ballistics = PeakMeter.Ballistics()

    var body: some View {
        ClockObserving(clock: playback.clock) {
            let level = session.meterLevels(at: playback.currentTime).master
            MeterBar(level: level, ballistics: $ballistics, time: playback.currentTime, width: 72, height: 8)
                .onTapGesture { ballistics.reset() }
                .onAppear { session.ensureMeterPeaks() }
                .onChange(of: session.activeTimeline?.assetIDs) { _, _ in session.ensureMeterPeaks() }
                .help(ballistics.clipped ? "The mix clipped — turn a track down; click to clear" : "Mix level (peak hold); red = clipping")
        }
    }
}

/// One track's level in its header (#281).
struct TrackMeter: View {
    @ObservedObject var session: ProjectSession
    @ObservedObject var playback: PlaybackController
    let trackID: UUID
    @State private var ballistics = PeakMeter.Ballistics()

    init(session: ProjectSession, trackID: UUID) {
        self.session = session
        self.playback = session.playback
        self.trackID = trackID
    }

    var body: some View {
        ClockObserving(clock: playback.clock) {
            let level = session.meterLevels(at: playback.currentTime).tracks[trackID] ?? 0
            MeterBar(level: level, ballistics: $ballistics, time: playback.currentTime, width: 36, height: 5)
                .onTapGesture { ballistics.reset() }
                .onAppear { session.ensureMeterPeaks() }
                .help("Track level (peak hold)")
        }
    }
}

/// A horizontal bar from −60 to 0 dB with a hold tick and a clip light.
struct MeterBar: View {
    let level: Float
    @Binding var ballistics: PeakMeter.Ballistics
    let time: Seconds
    var width: CGFloat
    var height: CGFloat

    var body: some View {
        let shown = PeakMeter.fraction(ballistics.level)
        let hold = PeakMeter.fraction(ballistics.hold)
        HStack(spacing: 3) {
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.well)
                Capsule()
                    .fill(LinearGradient(colors: [Theme.success, Theme.success, Theme.warning, Theme.danger], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, CGFloat(shown) * width))
                Rectangle().fill(hold > 0.9 ? Theme.danger : Color.white.opacity(0.85))
                    .frame(width: 1.5, height: height)
                    .offset(x: max(0, CGFloat(hold) * width - 1))
                    .opacity(ballistics.hold > 0.001 ? 1 : 0)
            }
            .frame(width: width, height: height)
            .clipShape(Capsule())
            Circle().fill(ballistics.clipped ? Theme.danger : Theme.well).frame(width: height * 0.9, height: height * 0.9)
        }
        .onChange(of: time) { _, t in ballistics.update(level: level, at: t) }
        .accessibilityLabel("Level \(Int(PeakMeter.dB(level))) decibels")
    }
}

/// Momentary / short-term / integrated loudness against the −14 LUFS target (#262), a few times a second.
struct LoudnessReadout: View {
    @ObservedObject var session: ProjectSession
    @ObservedObject var playback: PlaybackController
    static let target = AudioEnhanceChain.targetLUFS

    var body: some View {
        ClockObserving(clock: playback.slowClock) {
            let now = session.loudness(at: playback.currentTime)
            let integrated = session.integratedLoudnessValue()
            if now.momentary != nil || integrated != nil {
                HStack(spacing: 6) {
                    part("M", now.momentary)
                    part("S", now.shortTerm)
                    part("I", integrated)
                    Text("LUFS").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                }
                .help(String(format: "Loudness — momentary (0.4 s), short-term (3 s) and the whole edit, against the %.0f LUFS target most platforms normalise to. Green is within a dB; orange is quiet; red is hot. Read off the analysed recordings through every gain, so it's a close estimate rather than a true meter.", Self.target))
            }
        }
    }

    func part(_ label: String, _ value: Double?) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            Text(value.map { String(format: "%.0f", $0) } ?? "–").font(.pulseMono).monospacedDigit()
                .foregroundStyle(value.map { colour(PlayheadLoudness.verdict($0, target: Self.target)) } ?? Theme.textTertiary)
        }
    }

    func colour(_ verdict: PlayheadLoudness.Verdict) -> Color {
        switch verdict {
        case .onTarget: return Theme.success
        case .quiet: return Theme.warning
        case .hot: return Theme.danger
        }
    }
}
