import PulseCore
import PulseEngine
import SwiftUI

extension Theme {
    static func tierColor(_ tier: PerformanceTier) -> Color {
        switch tier {
        case .viral: return accent
        case .strong: return success
        case .solid: return info
        case .needsWork: return warning
        case .weak: return textTertiary
        }
    }
}

/// Big score ring: the predicted performance of the open edit.
struct PerformanceRing: View {
    let score: Int
    var size: CGFloat = 56

    var body: some View {
        let tier = PerformanceTier(score: score)
        ZStack {
            Circle().stroke(Theme.control, lineWidth: size * 0.09)
            Circle().trim(from: 0, to: CGFloat(score) / 100)
                .stroke(Theme.tierColor(tier), style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)").font(.system(size: size * 0.34, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
        }
        .frame(width: size, height: size)
    }
}

/// Compact score chip for the viewer header ("🔥 86").
struct PerformanceBadge: View {
    let prediction: PerformancePrediction

    var body: some View {
        HStack(spacing: 4) {
            Text(prediction.tier.emoji).font(.system(size: 10))
            Text("\(prediction.score)").font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .foregroundStyle(Theme.tierColor(prediction.tier))
        .background(Capsule().fill(Theme.tierColor(prediction.tier).opacity(0.14)))
        .help("Predicted performance: \(prediction.tier.displayName). Deselect clips to see the coach in the Inspector.")
    }
}

/// The coach card at the top of the Inspector: score, what drives it, and what to fix next.
struct CoachSection: View {
    @ObservedObject var session: ProjectSession
    let review: EditReview
    @State private var showAll = false

    var body: some View {
        InspectorSection("Coach", isAI: true) {
            let p = review.prediction
            HStack(spacing: 12) {
                PerformanceRing(score: p.score)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(p.tier.emoji) \(p.tier.displayName)")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.tierColor(p.tier))
                    Text(p.format == .short ? "Predicted for TikTok · Shorts · Reels" : "Predicted for YouTube")
                        .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                    if let best = p.strengths.first {
                        Text(best.note).font(.pulseMicro).foregroundStyle(Theme.textSecondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 4) {
                ForEach(p.factors, id: \.name) { factor in
                    HStack(spacing: 6) {
                        Text(factor.name).font(.pulseMicro).foregroundStyle(Theme.textSecondary).frame(width: 52, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.control)
                                Capsule().fill(factor.value >= 0.7 ? Theme.success : (factor.value >= 0.45 ? Theme.info : Theme.warning))
                                    .frame(width: geo.size.width * CGFloat(factor.value))
                            }
                        }
                        .frame(height: 4)
                    }
                    .help(factor.note)
                }
            }
            if let timeline = session.activeTimeline, timeline.duration > 90 {
                PacingGraph(timeline: timeline)
            }
            if review.suggestions.isEmpty {
                Label("Nothing to fix — this edit is in great shape.", systemImage: "checkmark.seal.fill")
                    .font(.pulseCaption).foregroundStyle(Theme.success)
            } else {
                SectionLabel(text: "Suggestions")
                ForEach(showAll ? review.suggestions : Array(review.suggestions.prefix(3))) { suggestion in
                    SuggestionRow(suggestion: suggestion) { session.applyCoachFix(suggestion) }
                }
                if review.suggestions.count > 3 {
                    Button(showAll ? "Show fewer" : "Show \(review.suggestions.count - 3) more") { showAll.toggle() }
                        .buttonStyle(.plain).font(.pulseMicro).foregroundStyle(Theme.info)
                }
            }
            Text(p.calibratedOn > 0 ? "Calibrated on \(p.calibratedOn) of your videos' real views — still a guide, not a guarantee."
                                    : "A prediction from the video's energy, hook, pacing and polish — a guide, not a guarantee. Import your analytics in Settings → Performance to calibrate it.")
                .font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Cuts per minute across the video, with the comfortable band for long-form (6–20) shaded.
struct PacingGraph: View {
    let timeline: Timeline

    var buckets: [Int] {
        guard let v = timeline.tracks.first(where: { $0.kind == .video }) else { return [] }
        let minutes = max(1, Int((timeline.duration / 60).rounded(.up)))
        var counts = Array(repeating: 0, count: minutes)
        for clip in v.clips.dropFirst() where clip.isEnabled {
            let i = min(minutes - 1, max(0, Int(clip.start / 60)))
            counts[i] += 1
        }
        return counts
    }

    var body: some View {
        let counts = buckets
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SectionLabel(text: "Pacing")
                Spacer()
                Text("\(counts.reduce(0, +)) cuts · \(String(format: "%.0f", Double(counts.reduce(0, +)) / max(timeline.duration / 60, 1)))/min")
                    .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            }
            GeometryReader { geo in
                let top = max(Double(counts.max() ?? 1), 24)
                ZStack(alignment: .bottomLeading) {
                    // The comfortable band for a long video.
                    Rectangle().fill(Theme.success.opacity(0.08))
                        .frame(height: geo.size.height * CGFloat((20 - 6) / top))
                        .offset(y: -geo.size.height * CGFloat(6 / top))
                    HStack(alignment: .bottom, spacing: 1) {
                        ForEach(Array(counts.enumerated()), id: \.offset) { _, n in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(n > 30 ? Theme.warning : (n < 4 ? Theme.textTertiary.opacity(0.5) : Theme.info))
                                .frame(height: max(1, geo.size.height * CGFloat(Double(n) / top)))
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.well))
        }
        .help("Cuts per minute, minute by minute. The green band (6–20) feels lively without tiring; orange minutes over 30 may feel frantic.")
    }
}

struct SuggestionRow: View {
    let suggestion: EditSuggestion
    let fix: () -> Void

    var color: Color {
        switch suggestion.severity {
        case .important: return Theme.accent
        case .recommended: return Theme.warning
        case .tip: return Theme.info
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: suggestion.symbol).font(.system(size: 11)).foregroundStyle(color).frame(width: 16).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title).font(.pulseCaption).foregroundStyle(Theme.textPrimary).lineLimit(2)
                Text(suggestion.detail).font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let title = suggestion.fix.buttonTitle {
                Button(title, action: fix).buttonStyle(.pulse(.secondary, compact: true)).fixedSize()
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.panelRaised))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(color.opacity(0.25)))
    }
}
