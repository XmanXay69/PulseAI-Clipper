import PulseCore
import PulseEngine
import SwiftUI

/// "Compare two styles" (#627): the same recording drafted two ways, side by side, before one is built for real.
struct StyleCompareSheet: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    /// The length, extras and wording both drafts share.
    let base: LongFormOptions
    @State var firstID: String
    @State var secondID: String
    /// Called with the picked style's id (`AISettings.ownStyle` for PULSE's own way).
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var trials: [String: StyleTrial] = [:]
    @State private var failed = false

    struct Choice: Identifiable, Hashable {
        let id: String
        let name: String
    }

    /// PULSE's own way, then every long-form style.
    var choices: [Choice] {
        [Choice(id: AISettings.ownStyle, name: "PULSE's own")]
            + EditorPlaybook.all.filter { !$0.style.isShortForm }.map { Choice(id: $0.id, name: $0.name) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader("Compare two styles", symbol: "rectangle.split.2x1",
                        subtitle: "The same recording drafted both ways. Nothing is added to the project until you pick one.")
            Divider().overlay(Theme.divider)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    column($firstID, other: secondID)
                    column($secondID, other: firstID)
                }
                verdictCard
            }
            .padding(20)
            Spacer(minLength: 0)
            Divider().overlay(Theme.divider)
            HStack {
                Text("Drafts leave out the music search, B-roll and audio levelling the full edit adds.")
                    .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(.pulseSecondary).keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .frame(width: 720, height: 560)
        .background(Theme.panel)
        .preferredColorScheme(AppModel.current?.colorScheme)
        .task(id: firstID + "|" + secondID) { await draft() }
    }

    func column(_ selection: Binding<String>, other: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Style", selection: selection) {
                ForEach(choices.filter { $0.id != other }) { choice in Text(choice.name).tag(choice.id) }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            if let trial = trials[selection.wrappedValue] {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(trial.score)").font(.stat(34)).foregroundStyle(Theme.potentialColor(trial.score))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(trial.review.prediction.tier.displayName).font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
                        Text("coach score").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                    }
                }
                RetentionSparkline(curve: trial.retention)
                    .frame(height: 54)
                    .help("A guess at how many viewers are still watching, second by second")
                Text("Predicted average watched: \(Int((Double(trial.retention.average) * 100).rounded())) %")
                    .font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                Text(trial.facts.summary).font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(trial.review.prediction.factors, id: \.name) { factor in
                        HStack(spacing: 6) {
                            Text(factor.name).font(.pulseMicro).foregroundStyle(Theme.textSecondary).frame(width: 52, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.control)
                                    Capsule().fill(Theme.accent).frame(width: geo.size.width * CGFloat(max(0, min(1, factor.value))))
                                }
                            }
                            .frame(height: 4)
                        }
                    }
                }
                Spacer(minLength: 4)
                Button {
                    onPick(trial.id)
                    dismiss()
                } label: { Label("Use \(trial.name)", systemImage: "checkmark") }
                    .buttonStyle(.pulse(.primary, compact: true))
                    .help("Sets Edit My VOD to this style; the full edit is built when you press Edit My VOD")
            } else if failed {
                Text("Analyze the recording first, then compare.").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 4)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Drafting…").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 330, alignment: .topLeading)
        .raisedSurface(cornerRadius: Theme.radiusXL)
    }

    @ViewBuilder
    var verdictCard: some View {
        if let a = trials[firstID], let b = trials[secondID] {
            let verdict = StyleComparison.verdict(a, b)
            VStack(alignment: .leading, spacing: 5) {
                Label(verdict.headline, systemImage: verdict.winner == nil ? "equal.circle" : "trophy")
                    .font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
                ForEach(verdict.reasons, id: \.self) { reason in
                    Text(reason).font(.pulseCaption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Text("A guide, not a promise: the numbers come from the recording's own signals, not from your audience.")
                    .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .insetRow()
        }
    }

    /// Drafts whichever of the two styles hasn't been drafted yet, off the main thread.
    func draft() async {
        guard let asset = session.document.primaryAsset, let analysis = session.analyses[asset.id],
              analysis.audio != nil || analysis.transcript != nil else {
            failed = true
            return
        }
        failed = false
        let base = self.base
        let taste = app.settings.ai.taste
        let calibration = app.settings.ai.coachCalibration
        for id in [firstID, secondID] where trials[id] == nil {
            let playbook = EditorPlaybook.playbook(id: id)
            let trial = await Task.detached(priority: .userInitiated) {
                StyleComparison.trial(playbook, asset: asset, analysis: analysis, base: base, taste: taste, calibration: calibration)
            }.value
            trials[id] = trial
        }
    }
}

/// The predicted share still watching across an edit, as a small filled line.
struct RetentionSparkline: View {
    let curve: RetentionPredictor.Curve

    var body: some View {
        Canvas { context, size in
            let values = curve.values
            guard values.count > 1 else { return }
            var line = Path()
            for (i, value) in values.enumerated() {
                let point = CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                                    y: size.height * (1 - CGFloat(max(0, min(1, value)))))
                if i == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            context.fill(fill, with: .color(Theme.accent.opacity(0.14)))
            context.stroke(line, with: .color(Theme.accent), lineWidth: 1.5)
        }
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.well))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}
