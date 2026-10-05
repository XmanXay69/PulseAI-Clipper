import AVFoundation
import PulseCore
import PulseEngine
import SwiftUI

/// Edit My VOD, step 2: every moment PULSE considered, in stream order. Switch moments on/off, preview them,
/// trim their edges, pick the hook, rate them (that also teaches your taste) — then build. With the
/// "Approve the cut" extra this is the review step before anything is built.
struct LongFormStoryboard: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    let options: LongFormOptions
    var approving = false
    let onBack: () -> Void
    let onBuild: ([LongFormSegment], Seconds?) -> Void

    @State private var plan: LongFormPlan?
    @State private var selected: Set<UUID> = []
    @State private var hook: UUID?
    @State private var ratings: [UUID: Bool] = [:]
    /// Edges you moved, by moment.
    @State private var trims: [UUID: TimeRange] = [:]
    @State private var previewing: UUID?

    var asset: MediaAsset? { session.document.primaryAsset }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.divider)
            if let plan {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(plan.moments) { moment in row(moment) }
                    }
                    .padding(16)
                }
            } else {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.large)
                    Text("Finding the moments…").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider().overlay(Theme.divider)
            footer
        }
        .task { await loadPlan() }
    }

    func loadPlan() async {
        guard let asset, let analysis = session.analyses[asset.id] else { return }
        let options = options
        let taste = app.settings.ai.taste
        let result = await Task.detached(priority: .userInitiated) {
            LongFormEditor.planMoments(analysis: analysis, options: options, taste: taste)
        }.value
        plan = result
        selected = result.selected
        hook = result.hook
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(approving ? "Approve the cut" : "Choose the moments").font(.pulseTitle).foregroundStyle(Theme.textPrimary)
            Text(approving
                 ? "Nothing is built yet. Preview each section (▶), keep or drop it, move its start and end, and choose the moment that opens the video — then build."
                 : "PULSE picked these for your video. Untick anything you don't want, tick alternatives, and choose the moment that opens the video.")
                .font(.pulseCaption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
    }

    /// The moment's range with your trims.
    func range(of moment: LongFormSegment) -> TimeRange { trims[moment.id] ?? moment.range }

    /// Moves one edge by `delta` (kept ≥ 3 s long and inside the recording).
    func trim(_ moment: LongFormSegment, start delta: Seconds = 0, end endDelta: Seconds = 0) {
        let r = range(of: moment)
        let limit = asset?.metadata.duration ?? r.end
        var start = max(0, r.start + delta), end = min(max(limit, r.end), r.end + endDelta)
        if end - start < 3 { if delta != 0 { start = end - 3 } else { end = start + 3 } }
        trims[moment.id] = TimeRange(start: start, end: end)
        selected.insert(moment.id)
    }

    func row(_ moment: LongFormSegment) -> some View {
        let on = selected.contains(moment.id)
        let isHook = hook == moment.id
        let r = range(of: moment)
        return HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { on }, set: { value in
                if value { selected.insert(moment.id) } else {
                    selected.remove(moment.id)
                    if hook == moment.id { hook = nil }
                }
            }))
            .labelsHidden().toggleStyle(.checkbox)
            ThumbnailView(url: asset.map(session.url(for:)), time: moment.payoff, maxWidth: 240)
                .frame(width: 120, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .bottomLeading) {
                    Text(Timecode.short(r.duration)).font(.pulseMicro).padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(.black.opacity(0.65))).foregroundStyle(.white).padding(4)
                }
                .opacity(on ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 4) {
                Text(moment.title.isEmpty ? "Moment at \(Timecode.short(moment.payoff))" : moment.title)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(on ? Theme.textPrimary : Theme.textTertiary).lineLimit(1)
                Text("\(Timecode.short(r.start)) → \(Timecode.short(r.end)) in the stream\(trims[moment.id] != nil ? " · trimmed" : "")")
                    .font(.pulseMicro).foregroundStyle(trims[moment.id] != nil ? Theme.ai : Theme.textTertiary)
                HStack(spacing: 4) {
                    ForEach(moment.tags.prefix(3), id: \.self) { TagChip(text: $0.displayName, color: Theme.ai) }
                }
                HStack(spacing: 6) {
                    Button { previewing = moment.id } label: { Label("Preview", systemImage: "play.fill").font(.system(size: 10, weight: .medium)) }
                        .buttonStyle(.pulse(.ghost, compact: true))
                        .popover(isPresented: Binding(get: { previewing == moment.id }, set: { if !$0 { previewing = nil } })) {
                            if let asset { RangePreview(url: session.url(for: asset), range: r) }
                        }
                    trimControl("Start", earlier: { trim(moment, start: -2) }, later: { trim(moment, start: 2) })
                    trimControl("End", earlier: { trim(moment, end: -2) }, later: { trim(moment, end: 2) })
                    if trims[moment.id] != nil {
                        Button("Reset") { trims[moment.id] = nil }.buttonStyle(.plain).font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            Spacer(minLength: 8)
            PotentialMeter(potential: moment.potential)
            Button {
                hook = isHook ? nil : moment.id
                if !on { selected.insert(moment.id) }
            } label: {
                Label(isHook ? "Hook" : "Make Hook", systemImage: isHook ? "flame.fill" : "flame")
                    .font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
            .buttonStyle(.pulse(isHook ? .primary : .ghost, compact: true))
            .fixedSize()
            .disabled(!options.coldOpen)
            IconButton(symbol: ratings[moment.id] == true ? "hand.thumbsup.fill" : "hand.thumbsup", help: "More like this", isActive: ratings[moment.id] == true, size: 22) {
                rate(moment, liked: true)
            }
            IconButton(symbol: ratings[moment.id] == false ? "hand.thumbsdown.fill" : "hand.thumbsdown", help: "Less like this", isActive: ratings[moment.id] == false, size: 22) {
                rate(moment, liked: false)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.radiusLarge).fill(on ? Theme.panelRaised : Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).strokeBorder(isHook ? Theme.accent : (on ? Theme.border : Theme.divider)))
    }

    func trimControl(_ title: String, earlier: @escaping () -> Void, later: @escaping () -> Void) -> some View {
        HStack(spacing: 2) {
            Text(title).font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            IconButton(symbol: "minus", help: "\(title) 2 s earlier", size: 18, action: earlier)
            IconButton(symbol: "plus", help: "\(title) 2 s later", size: 18, action: later)
        }
    }

    /// Ratings here teach the same taste profile as 👍/👎 on clips.
    func rate(_ moment: LongFormSegment, liked: Bool) {
        guard ratings[moment.id] != liked else { return }
        var taste = app.settings.ai.taste
        if let old = ratings[moment.id] { taste.forget(liked: old) }
        taste.learn(scores: moment.scores, tags: moment.tags, liked: liked)
        app.settings.ai.taste = taste
        ratings[moment.id] = liked
        if !liked { selected.remove(moment.id); if hook == moment.id { hook = nil } } else { selected.insert(moment.id) }
    }

    var footer: some View {
        HStack(spacing: 12) {
            Button { onBack() } label: { Label("Back", systemImage: "chevron.left") }.buttonStyle(.pulseSecondary)
            if let plan {
                let keptRanges: [TimeRange] = plan.moments.filter { selected.contains($0.id) }.map { range(of: $0) }.merged()
                let kept: Seconds = keptRanges.reduce(0.0) { $0 + $1.duration } * (options.cutDeadAir ? 0.9 : 1)
                let lo = options.minimumLength, hi = options.maximumLength
                let ok = kept >= min(lo, plan.target) * 0.9 && kept <= hi * 1.05
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selected.count) moments · about \(Timecode.short(kept))")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(ok ? Theme.success : Theme.warning)
                    Text(ok ? "Right in your \(Int(lo / 60))–\(Int(hi / 60)) min range" : (kept < lo ? "Shorter than your target — tick a few more" : "Longer than your target — untick a few"))
                        .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
            Button {
                guard let plan else { return }
                let chosen = plan.moments.filter { selected.contains($0.id) }.map { moment -> LongFormSegment in
                    var m = moment
                    m.range = range(of: moment)
                    m.payoff = min(max(m.payoff, m.range.start), m.range.end)
                    return m
                }
                let hookPayoff = chosen.first { $0.id == hook }?.payoff
                onBuild(chosen, hookPayoff)
            } label: { Label(approving ? "Approve & Build" : "Build My Video", systemImage: "wand.and.stars") }
                .buttonStyle(.pulseAI)
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty || plan == nil)
        }
        .padding(16)
    }
}

/// Plays one stretch of the recording (the storyboard's ▶ Preview).
struct RangePreview: View {
    let url: URL
    let range: TimeRange
    @State private var player = AVPlayer()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PlayerView(player: player)
                .frame(width: 480, height: 270)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            Text("\(Timecode.short(range.start)) → \(Timecode.short(range.end)) · \(Int(range.duration.rounded())) s")
                .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
        }
        .padding(10)
        .task {
            let item = AVPlayerItem(url: url)
            item.forwardPlaybackEndTime = .seconds(range.end)
            player.replaceCurrentItem(with: item)
            _ = await player.seek(to: .seconds(range.start), toleranceBefore: .zero, toleranceAfter: .zero)
            player.play()
        }
        .onDisappear { player.pause() }
    }
}
