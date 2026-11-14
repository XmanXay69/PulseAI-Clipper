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
    /// Segments in storyboard order, the hook's payoff, and whether the order was changed by hand (#109).
    let onBuild: ([LongFormSegment], Seconds?, Bool) -> Void
    @State private var reordered = false
    @State private var hoveringMoment: UUID?
    /// The moment whose before/after two-up is open (#108).
    @State private var comparing: UUID?

    @State private var plan: LongFormPlan?
    @State private var selected: Set<UUID> = []
    /// The kept moments read as a story (#581): which beat each is, the order that tells it, what is missing.
    @State private var arc: NarrativeArc?

    /// Reads the kept moments again after the selection changes.
    func readStory() {
        guard let plan else { arc = nil; return }
        let kept = plan.moments.filter { selected.contains($0.id) }
        let transcript = asset.flatMap { session.analyses[$0.id]?.transcript }
        arc = NarrativeArcBuilder.build(moments: kept, transcript: transcript, duration: asset?.metadata.duration ?? 0)
    }

    /// Puts the kept moments in the order that tells the story: the goal first, the setbacks and tries as they
    /// happened, the result last. Moments that aren't kept stay where they were, after them.
    func arrangeAsStory() {
        guard var plan, let arc else { return }
        let byID = Dictionary(plan.moments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let story = arc.order.compactMap { byID[$0] }
        guard story.count > 1 else { return }
        let rest = plan.moments.filter { !arc.order.contains($0.id) }
        if story.map(\.id) != plan.moments.filter({ arc.order.contains($0.id) }).map(\.id) { reordered = true }
        plan.moments = story + rest
        self.plan = plan
        app.toast(reordered ? "Arranged as a story: the goal first, the result last" : "Already in story order")
    }

    /// Asks the language model set up in Settings to plan the video (#1281): it reads the whole transcript with
    /// the signals and answers with where the video opens, which stretches it keeps and in what order, and
    /// what is dropped inside them. Its plan replaces the list here, to be approved or changed like any other;
    /// the same editor then builds it.
    func planWithModel() {
        guard !planning, let asset, let analysis = session.analyses[asset.id], let current = ownPlan ?? plan else { return }
        guard let provider = AIProviders.editPlanProvider(settings: app.settings.ai) else {
            app.presentMessage(title: "No language model is set up",
                               message: "A model that reads the whole transcript can plan the video: which stretches to keep, in what order, and where it opens. Choose Claude, or a model running on this Mac, in Settings → AI Processing. Until then, the plan below is PULSE's own.")
            return
        }
        if provider.location == .cloud && app.settings.ai.processingPolicy == .alwaysLocal {
            app.presentMessage(title: "Cloud AI is off", message: AIProviderError.cloudNotPermitted.localizedDescription)
            return
        }
        let signals = session.signals(for: asset.id)
        // A model on this Mac usually reads far less in one go than a hosted one.
        let budget = provider.location == .local ? 120_000 : 600_000
        // The rules of the style this edit was set up with: a built-in style's principles, or what a model
        // found a studied video teaches.
        let guidance = StyleStudy.planningGuidance(styleName: options.style?.name, saved: app.settings.referenceStyles)
        guard let brief = EditPlanner.brief(analysis: analysis, options: options, picks: current.moments, excitement: signals?.excitement ?? [],
                                            step: signals?.step ?? 1, budget: budget, guidance: guidance) else {
            app.presentMessage(title: "There are no words to plan from",
                               message: "The model plans from what was said, and this recording has no transcript. Transcribe it first, or build from PULSE's own plan.")
            return
        }
        if provider.location == .cloud && app.settings.ai.processingPolicy != .allowCloud {
            // The whole transcript is a bigger thing to send than one clip's words: say what goes, unless
            // Settings says cloud providers may be used without asking.
            let alert = NSAlert()
            alert.messageText = "Send this recording's transcript to \(provider.displayName)?"
            var text = "About \(brief.wordCount.formatted()) words are sent: what was said, with timecodes, an energy mark per line and the scores of \(brief.picks.count) moments PULSE found. Video and audio never leave your Mac. Your provider bills this request to your own key."
            if brief.leftOut > 1 {
                text += " The transcript is longer than one request holds, so \(Timecode.duration(brief.leftOut)) of the quietest talk is left out, and the model cannot consider it."
            }
            alert.informativeText = text
            alert.addButton(withTitle: "Send")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        planning = true
        Task {
            defer { planning = false }
            do {
                let draft = try await provider.planEdit(brief: brief)
                let answer = EditPlanner.resolve(draft, brief: brief)
                guard !answer.sections.isEmpty else {
                    app.presentMessage(title: "The model's plan kept nothing",
                                       message: "Nothing in its answer was a usable stretch of the recording. PULSE's own plan is unchanged." + (answer.notes.isEmpty ? "" : "\n\n" + answer.notes.joined(separator: "\n")))
                    return
                }
                adopt(answer, picks: brief.picks, over: current)
                app.logActivity(.autoEdit, title: "Edit planned by \(answer.writtenBy)",
                                detail: "\(answer.sections.count) sections · \(Timecode.short(answer.keptLength)) kept", location: provider.location)
            } catch {
                app.present(error, title: "The model couldn't plan this edit")
            }
        }
    }

    /// Shows the model's plan in the storyboard: its stretches first, in its order and switched on; then the
    /// moments PULSE found that it did not use, switched off, in case you want one back.
    func adopt(_ answer: EditPlan, picks: [EditBrief.Pick], over current: LongFormPlan) {
        if ownPlan == nil {
            ownPlan = current
            ownSelection = selected
            ownHook = hook
        }
        let moments = answer.segments(picks: picks)
        var reasons: [UUID: String] = [:]
        for moment in moments {
            guard let section = answer.sections.first(where: { $0.ranges.contains(moment.range) }) else { continue }
            let parts = [section.why] + section.cutNotes.map { "Dropped \($0)" }
            reasons[moment.id] = parts.filter { !$0.isEmpty }.joined(separator: " ")
        }
        var next = current
        next.moments = moments + current.moments.filter { own in !moments.contains { $0.range.overlaps(own.range) } }
        next.selected = Set(moments.map(\.id))
        next.hook = answer.hookPayoff.flatMap { at in moments.first { $0.range.contains(at) }?.id }
        next.hookCandidates = next.hook.map { [$0] } ?? []
        plan = next
        selected = next.selected
        hook = next.hook
        trims = [:]
        lengthScale = 1
        // The model's order and its cuts are the plan: the build keeps them as they are.
        reordered = true
        modelPlan = answer
        modelReasons = reasons
        readStory()
    }

    /// Back to the plan PULSE made itself.
    func restoreOwnPlan() {
        guard let own = ownPlan else { return }
        plan = own
        selected = ownSelection
        hook = ownHook
        trims = [:]
        reordered = false
        modelPlan = nil
        modelReasons = [:]
        ownPlan = nil
        readStory()
    }

    /// The row under the header that offers the model's plan, or says what it planned.
    @ViewBuilder
    var modelPlanRow: some View {
        if let modelPlan {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    TagChip(text: "Planned by \(modelPlan.writtenBy)", color: Theme.ai, symbol: "sparkles")
                    Text(modelPlan.summary.isEmpty ? "\(modelPlan.sections.count) sections, \(Timecode.short(modelPlan.keptLength)) kept" : modelPlan.summary)
                        .font(.pulseCaption).foregroundStyle(Theme.textPrimary).lineLimit(2)
                    Spacer(minLength: 8)
                    Button("Back to PULSE's Plan") { restoreOwnPlan() }
                        .buttonStyle(.pulse(.secondary, compact: true)).fixedSize()
                        .help("Puts back the moments PULSE picked itself. The model's plan is discarded.")
                }
                if !modelPlan.hookWhy.isEmpty {
                    Text("Opens on: \(modelPlan.hookWhy)").font(.pulseMicro).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
                ForEach(modelPlan.notes, id: \.self) { note in
                    Text(note).font(.pulseMicro).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 6)
            .help("A language model read the transcript and wrote this structure (#1281). PULSE checked every line it named; what it changed is listed. You approve it here like any plan.")
        } else {
            HStack(spacing: 8) {
                Button { planWithModel() } label: { Label(planning ? "Reading the transcript…" : "Plan with a Language Model", systemImage: "text.book.closed") }
                    .buttonStyle(.pulse(.ai, compact: true)).fixedSize().disabled(planning)
                if planning { ProgressView().controlSize(.small) }
                Text(planning ? "This can take a few minutes for a long recording. The list below is unchanged until it answers."
                              : "It reads everything that was said and proposes the structure: the opening, the stretches to keep, their order. You approve it here.")
                    .font(.pulseMicro).foregroundStyle(Theme.textTertiary).lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.top, 6)
        }
    }

    /// The main recording's words, for chapter names (#86).
    var words: [TranscriptWord] { session.document.primaryAsset.flatMap { session.analyses[$0.id]?.transcript?.words } ?? [] }
    @State private var focusedMoment: UUID?
    @State private var addQuery = ""

    /// Keyboard on the list (#111): ↑↓ move, space previews, return keeps or drops, ⌫ drops.
    func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard let plan else { return .ignored }
        let ids = plan.moments.map(\.id)
        let index = focusedMoment.flatMap { ids.firstIndex(of: $0) }
        switch press.key {
        case .downArrow:
            focusedMoment = ids[min((index ?? -1) + 1, ids.count - 1)]
            return .handled
        case .upArrow:
            focusedMoment = ids[max((index ?? 1) - 1, 0)]
            return .handled
        case .space:
            guard let id = focusedMoment else { return .ignored }
            previewing = previewing == id ? nil : id
            return .handled
        case .return:
            guard let id = focusedMoment else { return .ignored }
            if selected.contains(id) { selected.remove(id); if hook == id { hook = nil } } else { selected.insert(id) }
            return .handled
        case .delete:
            guard let id = focusedMoment else { return .ignored }
            selected.remove(id)
            if hook == id { hook = nil }
            return .handled
        default:
            return .ignored
        }
    }

    /// A moment from what was said (#110): the first place the words appear becomes a kept moment.
    func addMomentFromWords() {
        let terms = addQuery.lowercased().split(separator: " ").map { TranscriptWord.normalize(String($0)) }.filter { !$0.isEmpty }
        guard !terms.isEmpty, var current = plan else { return }
        let normalized = words.map(\.normalized)
        var hit: Int?
        for i in normalized.indices where i + terms.count <= normalized.count {
            if zip(terms, normalized[i..<(i + terms.count)]).allSatisfy({ $1.contains($0) }) { hit = i; break }
        }
        guard let i = hit else { app.toast("Nobody said “\(addQuery)” in this recording"); return }
        let t = words[i].start
        let limit = asset?.metadata.duration ?? t + 30
        let moment = LongFormSegment(range: TimeRange(start: max(0, t - 15), end: min(limit, t + 30)), payoff: t, potential: 55,
                                     title: words[i..<min(words.count, i + 8)].map(\.text).joined(separator: " "), tags: [.story])
        current.moments.append(moment)
        current.moments.sort { $0.range.start < $1.range.start }
        current.selected.insert(moment.id)
        plan = current
        selected.insert(moment.id)
        focusedMoment = moment.id
        addQuery = ""
        app.toast("Added a moment at \(Timecode.short(t))")
    }
    @State private var hook: UUID?
    /// A language model's plan for this video (#1281), when one was asked for; its reason for each stretch;
    /// and PULSE's own plan as it stood, to go back to.
    @State private var modelPlan: EditPlan?
    @State private var modelReasons: [UUID: String] = [:]
    @State private var planning = false
    @State private var ownPlan: LongFormPlan?
    @State private var ownSelection: Set<UUID> = []
    @State private var ownHook: UUID?
    @State private var lengthScale = 1.0
    @State private var ratings: [UUID: Bool] = [:]
    /// Edges you moved, by moment.
    @State private var trims: [UUID: TimeRange] = [:]
    @State private var previewing: UUID?
    @State private var analyzing = false

    var asset: MediaAsset? { session.document.primaryAsset }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.divider)
            if let plan {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(plan.moments) { moment in
                            row(moment)
                                .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(focusedMoment == moment.id ? Theme.accent : .clear, lineWidth: 1.5))
                                .onTapGesture { focusedMoment = moment.id }
                                .id(moment.id)
                        }
                    }
                    .padding(16)
                }
                .focusable()
                .onKeyPress(phases: .down, action: handleKey)
                .help("↑ ↓ move · space previews · return keeps or drops · ⌫ drops (#111)")
            } else {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.large)
                    if analyzing, let asset, let p = session.analysisProgress[asset.id] {
                        Text("Analyzing the recording first — \(p.stage) \(Int(p.fraction * 100))%").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    } else {
                        Text(analyzing ? "Analyzing the recording first…" : "Finding the moments…").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider().overlay(Theme.divider)
            footer
        }
        .task { await loadPlan() }
        .onChange(of: selected) { _, _ in readStory() }
    }

    /// Storyboard reorder (#109): swap with the neighbour; the build then keeps this order instead of the recording's.
    func move(_ moment: LongFormSegment, by delta: Int) {
        guard var plan, let i = plan.moments.firstIndex(where: { $0.id == moment.id }) else { return }
        let j = i + delta
        guard plan.moments.indices.contains(j) else { return }
        plan.moments.swapAt(i, j)
        self.plan = plan
        reordered = true
        focusedMoment = moment.id
    }

    func loadPlan() async {
        guard let asset else { return }
        guard let analysis = session.analyses[asset.id], analysis.audio != nil || analysis.transcript != nil else {
            // Not analyzed yet (Approve the cut straight from Edit My VOD): analyze first, then come back here.
            if !analyzing {
                analyzing = true
                session.analyze(assetID: asset.id, generateClips: false) { analyzing = false; Task { await loadPlan() } }
            }
            return
        }
        let options = options
        let taste = app.settings.ai.taste
        let result = await Task.detached(priority: .userInitiated) {
            LongFormEditor.planMoments(analysis: analysis, options: options, taste: taste)
        }.value
        plan = result
        selected = result.selected
        hook = result.hook
        readStory()
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(approving ? "Approve the cut" : "Choose the moments").font(.pulseTitle).foregroundStyle(Theme.textPrimary)
                Spacer()
                if plan != nil {
                    TextField("Add a moment by what was said…", text: $addQuery, onCommit: addMomentFromWords)
                        .textFieldStyle(.roundedBorder).font(.pulseCaption).frame(width: 240)
                        .help("Type a few words that were said; the first place they appear becomes a kept moment (#110)")
                }
            }
            Text(approving
                 ? "Nothing is built yet. Preview each section (▶), keep or drop it, move its start and end, and choose the moment that opens the video — then build."
                 : "PULSE picked these for your video. Untick anything you don't want, tick alternatives, and choose the moment that opens the video.")
                .font(.pulseCaption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            if let plan {
                HStack(spacing: 10) {
                    Text("Length").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    Slider(value: Binding(get: { lengthScale }, set: { v in lengthScale = v; selected = plan.selection(forLength: plan.target * v) }),
                           in: 0.5...1.6, step: 0.05)
                        .frame(width: 200)
                        .help("Preview what a shorter or longer video keeps (#88)")
                    Text("\(Timecode.short(plan.keptLength(selected))) kept · \(selected.count) of \(plan.moments.count)")
                        .font(.pulseMono).foregroundStyle(Theme.textTertiary)
                    if !plan.hookCandidates.isEmpty {
                        Spacer(minLength: 8)
                        Text("Open with").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                        ForEach(Array(plan.hookCandidates.enumerated()), id: \.element) { index, id in
                            Button("Hook \(index + 1)") { hook = id; selected.insert(id) }
                                .buttonStyle(.pulse(hook == id ? .primary : .secondary, compact: true))
                                .help(plan.moments.first { $0.id == id }?.title ?? "")
                        }
                    }
                }
                .padding(.top, 6)
                let chapters = ChapterOutline.propose(plan: plan.withSelection(selected), words: words)
                if chapters.count >= 2 {
                    HStack(spacing: 6) {
                        Text("Outline").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                        ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                            TagChip(text: "\(index + 1) · \(chapter.name) (\(chapter.momentIDs.count))", color: Theme.ai, symbol: nil)
                                .help("Moments \(chapter.momentIDs.count) in this chapter — drop or keep them below")
                        }
                    }
                    .padding(.top, 4)
                    .help("How the video will read, chapter by chapter (#86): split at the biggest jumps in the stream")
                }
                modelPlanRow
                if let arc, !arc.placements.isEmpty {
                    HStack(spacing: 8) {
                        Text("Story").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                        Text(arc.summary).font(.pulseCaption).foregroundStyle(arc.missing.isEmpty ? Theme.textPrimary : Theme.warning).lineLimit(1)
                        Button("Arrange as a story") { arrangeAsStory() }
                            .buttonStyle(.pulse(.ai, compact: true))
                            .fixedSize()
                            .disabled(arc.order.count < 2)
                            .help("Puts the goal first, the setbacks and tries in the order they happened, and the result last")
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
                    .help("The kept moments read as a story (#581): what they set out to do, what got in the way, what they tried and how it ended")
                    if let gap = arc.missing.first {
                        Text(gap.adviceWhenMissing).font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
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
            ZStack {
                ThumbnailView(url: asset.map(session.url(for:)), time: moment.payoff, maxWidth: 240)
                if hoveringMoment == moment.id, let asset {
                    // A short loop of the moment while the mouse rests on it (#112).
                    HoverLoopPreview(url: session.url(for: asset), range: r)
                }
            }
                .frame(width: 120, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .onHover { inside in hoveringMoment = inside ? moment.id : (hoveringMoment == moment.id ? nil : hoveringMoment) }
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
                if let why = modelReasons[moment.id], !why.isEmpty {
                    // The model's reason for keeping this stretch, to agree or disagree with (#1281).
                    Text(why).font(.pulseMicro).foregroundStyle(Theme.textSecondary).lineLimit(2).help(why)
                }
                HStack(spacing: 4) {
                    if on, let placement = arc?.placements.first(where: { $0.momentID == moment.id }) {
                        TagChip(text: placement.beat.displayName, symbol: placement.beat.symbolName)
                            .help("Read as the story's \(placement.beat.displayName.lowercased()) from \(placement.evidence)")
                    }
                    ForEach(moment.tags.prefix(3), id: \.self) { TagChip(text: $0.displayName, color: Theme.ai) }
                }
                if let asset, on {
                    // The moment's sound with its payoff marked (#438).
                    WaveformStrip(url: session.url(for: asset), sourceRange: r, color: Theme.ai)
                        .frame(height: 16)
                        .overlay {
                            GeometryReader { geo in
                                let x = r.duration > 0 ? CGFloat((moment.payoff - r.start) / r.duration) * geo.size.width : 0
                                Rectangle().fill(Theme.accent).frame(width: 1.5).offset(x: max(0, min(geo.size.width - 1.5, x)))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .help("The moment's waveform; the bright line is the payoff")
                }
                HStack(spacing: 6) {
                    Button { comparing = moment.id } label: { Label("Before / After", systemImage: "rectangle.split.2x1").font(.system(size: 10, weight: .medium)) }
                        .buttonStyle(.pulse(.ghost, compact: true))
                        .help("The raw stretch around this moment next to what the edit keeps (#108)")
                        .popover(isPresented: Binding(get: { comparing == moment.id }, set: { if !$0 { comparing = nil } })) {
                            if let asset {
                                let limit = asset.metadata.duration
                                let raw = TimeRange(start: max(0, moment.range.start - 4), end: min(limit, moment.range.end + 4))
                                BeforeAfterPreview(url: session.url(for: asset), before: raw, after: r)
                            }
                        }
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
            VStack(spacing: 2) {
                Button { move(moment, by: -1) } label: { Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.textTertiary)
                    .disabled(plan?.moments.first?.id == moment.id)
                    .help("Move this moment earlier in the video — the edit keeps your order (#109)")
                Button { move(moment, by: 1) } label: { Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.textTertiary)
                    .disabled(plan?.moments.last?.id == moment.id)
                    .help("Move this moment later in the video")
            }
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
        .background(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous).fill(on ? Theme.panelRaised : Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous).strokeBorder(isHook ? Theme.accent : (on ? Theme.border : Theme.divider)))
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
                onBuild(chosen, hookPayoff, reordered)
            } label: { Label(approving ? "Approve & Build" : "Build My Video", systemImage: "wand.and.stars") }
                .buttonStyle(.pulsePrimary)
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
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
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


/// Loops a stretch of the recording silently in a thumbnail-sized player (#112).
struct HoverLoopPreview: View {
    let url: URL
    let range: TimeRange
    @State private var player = AVPlayer()
    @State private var observer: Any?

    var body: some View {
        PlayerView(player: player)
            .allowsHitTesting(false)
            .onAppear {
                let item = AVPlayerItem(url: url)
                player.replaceCurrentItem(with: item)
                player.isMuted = true
                player.seek(to: .seconds(range.start), toleranceBefore: .zero, toleranceAfter: .positiveInfinity)
                player.play()
                let end = range.end
                let start = range.start
                observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak player] time in
                    if time.secondsValue >= end - 0.1 { player?.seek(to: .seconds(start), toleranceBefore: .zero, toleranceAfter: .positiveInfinity) }
                }
            }
            .onDisappear {
                if let observer { player.removeTimeObserver(observer) }
                observer = nil
                player.pause()
                player.replaceCurrentItem(with: nil)
            }
    }
}

/// Two silent loops side by side (#108): the raw stretch of the recording on the left, the kept moment on
/// the right, so a cut can be judged against what it came from.
struct BeforeAfterPreview: View {
    let url: URL
    let before: TimeRange
    let after: TimeRange

    var body: some View {
        HStack(spacing: 12) {
            pane("Before — as recorded", before, color: Theme.textTertiary)
            pane("After — what the edit keeps", after, color: Theme.ai)
        }
        .padding(12)
    }

    func pane(_ title: String, _ range: TimeRange, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HoverLoopPreview(url: url, range: range)
                .frame(width: 300, height: 169)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(color.opacity(0.7)))
            Text(title).font(.pulseCaption).foregroundStyle(Theme.textPrimary)
            Text("\(Timecode.short(range.start)) → \(Timecode.short(range.end)) · \(Int(range.duration.rounded())) s")
                .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
        }
    }
}
