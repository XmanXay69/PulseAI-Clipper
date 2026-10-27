import AppKit
import AVKit
import PulseCore
import PulseEngine
import SwiftUI

struct AIClipsView: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    @State private var lengthFilter: LengthFilter = .all
    @State private var tagFilter: ClipTag?
    @State private var showBatchExport = false

    enum LengthFilter: String, CaseIterable { case all = "All", s15 = "≤ 20s", s30 = "20–45s", s60 = "45s+" }

    @State private var showMaybeLater = false

    var candidates: [ClipCandidate] {
        var list = showMaybeLater ? session.document.candidates.filter { $0.status == .dismissed } : session.document.visibleCandidates
        switch lengthFilter {
        case .all: break
        case .s15: list = list.filter { $0.duration <= 20 }
        case .s30: list = list.filter { $0.duration > 20 && $0.duration <= 45 }
        case .s60: list = list.filter { $0.duration > 45 }
        }
        if let tagFilter { list = list.filter { $0.tags.contains(tagFilter) } }
        return session.candidateSort.sort(list)
    }

    var selected: ClipCandidate? {
        guard session.selectedCandidateIDs.count == 1, let id = session.selectedCandidateIDs.first else { return nil }
        return session.document.candidates.first { $0.id == id }
    }

    func rateSelected(_ liked: Bool) {
        guard let selected else { return }
        session.rateCandidate(selected.id, liked: selected.feedback == (liked ? 1 : -1) ? nil : liked)
    }

    func moveSelection(_ step: Int) {
        let list = candidates
        guard !list.isEmpty else { return }
        let current = selected.flatMap { s in list.firstIndex { $0.id == s.id } } ?? (step > 0 ? -1 : list.count)
        let next = min(max(current + step, 0), list.count - 1)
        session.selectedCandidateIDs = [list[next].id]
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                if session.document.visibleCandidates.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 270, maximum: 340), spacing: 14)], spacing: 14) {
                            ForEach(candidates) { candidate in
                                ClipCandidateCard(session: session, candidate: candidate, isSelected: session.selectedCandidateIDs.contains(candidate.id))
                                    .onTapGesture {
                                        if NSEvent.modifierFlags.contains(.command) {
                                            if session.selectedCandidateIDs.contains(candidate.id) { session.selectedCandidateIDs.remove(candidate.id) } else { session.selectedCandidateIDs.insert(candidate.id) }
                                        } else {
                                            session.selectedCandidateIDs = [candidate.id]
                                        }
                                    }
                            }
                        }
                        .padding(16)
                    }
                    // Rate from the keyboard: K = 👍, J = 👎, ← → move (only while the grid has focus, so typing a
                    // title in the panel never rates a clip).
                    .focusable()
                    .focusEffectDisabled()
                    .onKeyPress(KeyEquivalent("k")) { rateSelected(true); return .handled }
                    .onKeyPress(KeyEquivalent("j")) { rateSelected(false); return .handled }
                    .onKeyPress(.rightArrow) { moveSelection(1); return .handled }
                    .onKeyPress(.leftArrow) { moveSelection(-1); return .handled }
                }
            }
            .frame(maxWidth: .infinity)
            if let selected {
                Rectangle().fill(Theme.divider).frame(width: 1)
                CandidateDetailPanel(session: session, candidate: selected)
                    .frame(width: 360)
            }
        }
        .sheet(isPresented: $showBatchExport) {
            BatchExportSheet(session: session, candidateIDs: session.selectedCandidateIDs.isEmpty ? Set(candidates.map(\.id)) : session.selectedCandidateIDs)
                .environmentObject(app)
        }
    }

    var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                let dismissed = session.document.candidates.filter { $0.status == .dismissed }.count
                HStack(spacing: 8) {
                    Text(showMaybeLater ? "Maybe later — \(dismissed) set aside" : "\(session.document.visibleCandidates.count) potential clips found")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    if dismissed > 0 || showMaybeLater {
                        Button(showMaybeLater ? "Back to clips" : "Maybe later (\(dismissed))") { showMaybeLater.toggle() }
                            .buttonStyle(.pulse(showMaybeLater ? .primary : .ghost, compact: true))
                            .help("Clips you set aside stay here instead of being deleted (#85)")
                    }
                }
                if let asset = session.document.primaryAsset {
                    Text("from \(asset.name) · \(Timecode.duration(asset.metadata.duration))").font(.pulseCaption).foregroundStyle(Theme.textTertiary)
                }
                Label(app.settings.ai.taste.summary, systemImage: "hand.thumbsup")
                    .font(.pulseMicro).foregroundStyle(Theme.ai).lineLimit(1)
                    .help("Your 👍 / 👎 teach PULSE what you find entertaining. Reset in Settings → AI Features.")
            }
            Spacer()
            Picker("", selection: $lengthFilter) {
                ForEach(LengthFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 210)
            Menu {
                Button("All tags") { tagFilter = nil }
                Divider()
                ForEach(ClipTag.allCases, id: \.self) { tag in
                    Button("\(tag.emoji) \(tag.displayName)") { tagFilter = tag }
                }
            } label: { Label(tagFilter?.displayName ?? "Tags", systemImage: "tag") }
                .menuStyle(.borderlessButton)
                .frame(width: 110)
            Menu {
                Picker("Sort by", selection: $session.candidateSort) {
                    ForEach(CandidateSort.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            } label: { Label(session.candidateSort.displayName, systemImage: "arrow.up.arrow.down") }
                .menuStyle(.borderlessButton)
                .frame(width: 140)
            AggressivenessControl(session: session)
            if session.selectedCandidateIDs.count >= 2 {
                Button { session.mergeCandidates(session.selectedCandidateIDs) } label: { Label("Merge \(session.selectedCandidateIDs.count) into One Short", systemImage: "rectangle.stack.badge.plus") }
                    .buttonStyle(.pulseSecondary)
                    .help("A callback joke, a story in two parts: the selected moments become one short, joined with a cut (#65)")
            }
            Button { app.showLongFormSheet = true } label: { Label("Edit My VOD", systemImage: "film.stack") }
                .buttonStyle(.pulseAI)
                .disabled(session.document.primaryAsset == nil)
                .help("Turn the whole stream into a 10–20 minute YouTube video")
            Button { app.showReferenceSheet = true } label: { Label("Like a Reference", systemImage: "wand.and.stars") }
                .buttonStyle(.pulseSecondary)
                .disabled(session.document.primaryAsset == nil)
                .help("Edit your VOD the way a video you love is edited (⌥⌘R)")
            Button { regenerateAll() } label: { Label("Find Again", systemImage: "arrow.clockwise") }
                .buttonStyle(.pulseSecondary)
                .disabled(session.document.primaryAsset == nil)
            Button { showBatchExport = true } label: {
                Label(session.selectedCandidateIDs.count > 1 ? "Export \(session.selectedCandidateIDs.count)" : "Batch Export", systemImage: "square.and.arrow.up.on.square")
            }
            .buttonStyle(.pulsePrimary)
            .disabled(session.document.visibleCandidates.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    var emptyState: some View {
        VStack {
            if let asset = session.document.primaryAsset, let progress = session.analysisProgress[asset.id] {
                VStack(spacing: 12) {
                    ZStack {
                        ProgressRing(progress: progress.fraction, size: 64, color: Theme.ai)
                        Text("\(Int(progress.fraction * 100))%").font(.pulseMono).foregroundStyle(Theme.textPrimary)
                    }
                    Text(progress.stage).font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
                    if let left = session.analysisRemaining[asset.id] {
                        Text(DurationText.remaining(left).capitalizedFirst).font(.pulseTitle).foregroundStyle(Theme.ai).monospacedDigit()
                    }
                    Text("You can keep working — analysis runs in the background.").font(.pulseCaption).foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(symbol: "sparkles", title: "No clips yet",
                               message: session.document.primaryAsset == nil ? "Import a long video, then PULSE will analyze it and propose clips." : "Analyze your recording to find the most entertaining moments.",
                               actionTitle: session.document.primaryAsset == nil ? "Import Video" : "Analyze & Find Clips") {
                    if let asset = session.document.primaryAsset { session.analyze(assetID: asset.id) } else { app.showImportPanel() }
                }
            }
        }
    }

    func regenerateAll() {
        guard let asset = session.document.primaryAsset else { return }
        session.generateCandidates(assetID: asset.id)
    }
}

/// How many moments to look for in this project (#53): a slider that re-runs the finder, with the count live.
struct AggressivenessControl: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    @State private var open = false
    @State private var value = 0.5

    var body: some View {
        Button { value = session.document.generation.aggressiveness; open.toggle() } label: { Label("\(session.document.visibleCandidates.count)", systemImage: "slider.horizontal.3") }
            .buttonStyle(.pulse(.ghost, compact: true))
            .help("How many moments PULSE looks for in this project")
            .popover(isPresented: $open, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Moments to find").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    HStack {
                        Text("Fewer, stronger").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                        Slider(value: $value, in: 0.1...1, step: 0.05).frame(width: 160)
                        Text("More").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                    }
                    Text("\(session.document.visibleCandidates.count) now · this project only; Settings → AI Features sets the default")
                        .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                    HStack {
                        Spacer()
                        Button("Find Again") {
                            guard let asset = session.document.primaryAsset else { return }
                            var settings = session.document.generation
                            settings.aggressiveness = value
                            session.edit("Clip Aggressiveness") { $0.generation = settings }
                            session.generateCandidates(assetID: asset.id, settings: settings)
                            open = false
                        }
                        .buttonStyle(.pulse(.ai, compact: true))
                        .disabled(session.document.primaryAsset == nil)
                    }
                }
                .padding(12)
            }
    }
}

struct ClipCandidateCard: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    let candidate: ClipCandidate
    let isSelected: Bool
    @State private var hovering = false
    @State private var hoverFrame = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                preview
                    .frame(height: 150)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                HStack {
                    Text(Timecode.short(candidate.range.start) + " → " + Timecode.short(candidate.range.end))
                        .font(.pulseMono).foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Text("\(Int(candidate.duration.rounded()))s")
                        .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.6)))
                        .foregroundStyle(.white)
                }
                .padding(8)
                if candidate.timelineID != nil {
                    Label("Edited", systemImage: "checkmark.circle.fill")
                        .font(.pulseMicro).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.info.opacity(0.85))).foregroundStyle(.white)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top) {
                    Text(candidate.title)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if candidate.isFavorite { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Theme.warning) }
                }
                if !candidate.transcriptSnippet.isEmpty {
                    Text(candidate.transcriptSnippet).font(.pulseCaption).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
                if let why = whyLine {
                    Text(why).font(.pulseMicro).foregroundStyle(Theme.ai).lineLimit(1)
                        .help("Why PULSE picked this moment")
                }
                if let banner = gameBanner {
                    TagChip(text: banner.text.capitalized, color: Theme.success, symbol: banner.kind.symbolName)
                        .help("The game showed this on screen during the clip")
                }
                if let twin = overlappingShort {
                    TagChip(text: "Overlaps “\(twin.title)”", color: Theme.warning, symbol: "exclamationmark.triangle.fill")
                        .help("Both shorts cover mostly the same stretch — posting both looks like a repost")
                }
                if let part = session.seriesLabels[candidate.id] {
                    TagChip(text: part, color: Theme.info, symbol: "square.stack")
                        .help("A running bit — this moment and another reference each other, so post them as a series")
                }
                if candidate.isMerged {
                    TagChip(text: "\(1 + (candidate.extraRanges?.count ?? 0)) moments · \(Int(candidate.totalDuration.rounded()))s", color: Theme.ai, symbol: "rectangle.stack")
                        .help("Built from several moments joined with cuts")
                }
                HStack(spacing: 4) {
                    ForEach(candidate.tags.prefix(2), id: \.self) { tag in TagChip(text: tag.displayName, color: Theme.ai) }
                    if candidate.timelineID == nil {
                        TagChip(text: app.settings.ai.captionPresetName.isEmpty ? "TikTok captions" : "\(app.settings.ai.captionPresetName) captions", color: Theme.textTertiary, symbol: "captions.bubble")
                            .help("The caption look this short gets (Settings → AI Features); change it per short in Captions (#61)")
                    }
                    Spacer(minLength: 2)
                    Text(PerformanceTier(score: candidate.potential).emoji).font(.system(size: 10))
                        .help(PerformanceTier(score: candidate.potential).displayName)
                    PotentialMeter(potential: candidate.potential)
                }
                HStack(spacing: 6) {
                    if candidate.status == .dismissed {
                        Button { session.restoreCandidate(candidate.id) } label: { Label("Restore", systemImage: "arrow.uturn.backward").lineLimit(1) }
                            .buttonStyle(.pulse(.secondary, compact: true))
                            .fixedSize()
                    } else {
                        Button { session.createShort(from: candidate.id) } label: { Label("Open in Editor", systemImage: "wand.and.stars").lineLimit(1) }
                            .buttonStyle(.pulse(.ai, compact: true))
                            .fixedSize()
                    }
                    Spacer()
                    IconButton(symbol: candidate.feedback == 1 ? "hand.thumbsup.fill" : "hand.thumbsup", help: "More like this — PULSE learns your taste",
                               isActive: candidate.feedback == 1, size: 22) {
                        session.rateCandidate(candidate.id, liked: candidate.feedback == 1 ? nil : true)
                    }
                    IconButton(symbol: candidate.feedback == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown", help: "Less like this",
                               isActive: candidate.feedback == -1, size: 22) {
                        session.rateCandidate(candidate.id, liked: candidate.feedback == -1 ? nil : false)
                    }
                    Menu {
                        Button("Shorten by 10 s") { session.reshapeCandidate(candidate.id, targetDuration: max(10, candidate.duration - 10), regenerate: false) }
                        Button("Extend by 10 s") { session.reshapeCandidate(candidate.id, targetDuration: min(90, candidate.duration + 10), regenerate: false) }
                        Button("Regenerate") { session.reshapeCandidate(candidate.id, targetDuration: nil, regenerate: true) }
                        Button("Make Thumbnail…") { app.thumbnailRequest = ThumbnailRequest(candidateID: candidate.id) }
                        Divider()
                        Button("Never Show Moments Like This") { session.neverCandidate(candidate.id) }
                        Button("Delete", role: .destructive) { session.deleteCandidates([candidate.id]) }
                    } label: { Image(systemName: "ellipsis.circle").font(.system(size: 11)) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .help("Shorten, extend, regenerate, make a thumbnail or delete")
                }
            }
            .padding(10)
        }
        .background(RoundedRectangle(cornerRadius: Theme.radiusLarge).fill(Theme.panelRaised))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).strokeBorder(isSelected ? Theme.ai : (hovering ? Theme.borderStrong : Theme.border), lineWidth: isSelected ? 2 : 1))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).strokeBorder(Theme.edgeHighlight, lineWidth: 1))
        .shadow(color: isSelected ? Theme.ai.opacity(0.25) : .black.opacity(hovering ? 0.35 : 0.22), radius: hovering ? 16 : 8, y: hovering ? 8 : 3)
        .offset(y: hovering ? -2 : 0)
        .animation(Theme.motion(.easeOut(duration: 0.14)), value: hovering)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open in Editor") { session.createShort(from: candidate.id) }
            Button("Auto Edit (aggressive)") { session.createShort(from: candidate.id, mode: .autoEdit) }
            Divider()
            Button(candidate.isFavorite ? "Unfavorite" : "Favorite") {
                session.edit("Favorite Clip") { doc in
                    if let i = doc.candidates.firstIndex(where: { $0.id == candidate.id }) { doc.candidates[i].isFavorite.toggle() }
                }
            }
            Button("Regenerate") { session.reshapeCandidate(candidate.id, targetDuration: nil, regenerate: true) }
            Menu("Length") {
                ForEach([15.0, 30, 60], id: \.self) { d in
                    Button("\(Int(d)) seconds") { session.reshapeCandidate(candidate.id, targetDuration: d, regenerate: false) }
                }
            }
            Divider()
            Button("Delete", role: .destructive) { session.deleteCandidates([candidate.id]) }
        }
        .task(id: hovering) {
            // Hover scrub: cycle through frames of the clip.
            guard hovering else { hoverFrame = 0; return }
            while !Task.isCancelled && hovering {
                try? await Task.sleep(nanoseconds: 450_000_000)
                hoverFrame = (hoverFrame + 1) % 6
            }
        }
    }

    /// "big laugh + chat spike": the signals behind the pick, in plain words (#50).
    var whyLine: String? {
        guard let signals = session.energySignal(for: candidate.assetID) else { return nil }
        let banners = session.analyses[candidate.assetID]?.hudEvents ?? []
        return MomentExplanation.explain(candidate: candidate, signals: signals, banners: banners).summary
    }

    /// The biggest game banner (win, multi-kill, death…) read off the screen inside this clip.
    var gameBanner: HUDEvent? {
        session.analyses[candidate.assetID]?.hudEvents?.filter { candidate.range.contains($0.time) }.max { $0.kind.weight < $1.kind.weight }
    }

    /// Another clip (already edited, or this one is) that covers mostly the same stretch.
    var overlappingShort: ClipCandidate? {
        let pair = session.document.visibleCandidates.overlappingPairs().first { p in
            (p.a.id == candidate.id || p.b.id == candidate.id) && (p.a.timelineID != nil || p.b.timelineID != nil)
        }
        guard let pair else { return nil }
        return pair.a.id == candidate.id ? pair.b : pair.a
    }

    var preview: some View {
        let asset = session.document.asset(id: candidate.assetID)
        let time: Seconds = hovering ? candidate.range.start + candidate.duration * (Double(hoverFrame) + 0.5) / 6 : candidate.payoffTime
        return ThumbnailView(url: asset.map { session.url(for: $0) }, time: time, maxWidth: 480)
    }
}

/// Right-hand panel: live preview, AI score breakdown, hook advice, titles, platform captions.
struct CandidateDetailPanel: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    let candidate: ClipCandidate
    @State private var player = AVPlayer()
    @State private var editingTitle = ""
    @State private var editingHashtags = ""
    @State private var boundaryObserver: Any?
    @State private var aiBusy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PlayerView(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                HStack {
                    Button { player.rate == 0 ? player.play() : player.pause() } label: { Label("Preview", systemImage: "play.fill") }
                        .buttonStyle(.pulse(.secondary, compact: true))
                    Button { shorten(by: 0.2) } label: { Label("20% shorter", systemImage: "scissors") }
                        .buttonStyle(.pulse(.ghost, compact: true))
                        .disabled(candidate.duration < 12)
                        .help("Trims setup and tail by what's in them — the payoff stays, edges land on words")
                    Spacer()
                    Text("\(Timecode.short(candidate.range.start)) → \(Timecode.short(candidate.range.end)) · \(Int(candidate.duration.rounded()))s")
                        .font(.pulseMono).foregroundStyle(Theme.textSecondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Title")
                    TextField("Title", text: $editingTitle, onCommit: commitTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, weight: .bold))
                    FlowChips(items: candidate.copy.titles) { title in
                        editingTitle = title
                        commitTitle()
                    }
                    Button { session.moreTitles(for: candidate.id) } label: { Label("More like this one", systemImage: "sparkles") }
                        .buttonStyle(.pulse(.ghost, compact: true))
                        .help("Three more titles in the spirit of the current one — a quote gets more quotes, a hook line gets its siblings")
                }
                HStack(spacing: 8) {
                    Button { session.createShort(from: candidate.id) } label: { Label("Create Short", systemImage: "wand.and.stars").frame(maxWidth: .infinity) }
                        .buttonStyle(.pulseAI)
                    Button { session.createABShorts(from: candidate.id) } label: { Label("A/B", systemImage: "square.split.2x1") }
                        .buttonStyle(.pulseSecondary)
                        .help("Two versions: the one-click cut, and an auto-edit with the other caption look, a cold open and a speed ramp")
                    Button { session.createShort(from: candidate.id, mode: .autoEdit) } label: { Label("Auto Edit", systemImage: "bolt.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.pulseSecondary)
                        .help("More aggressive: jump cuts, filler removal, punch-ins, SFX from your library")
                }
                scoreBreakdown
                whyCard
                if let hook = candidate.hook { hookCard(hook) }
                platformCopy
            }
            .padding(14)
        }
        .background(Theme.panel)
        .onAppear(perform: load)
        .onChange(of: candidate.id) { load() }
        .onChange(of: candidate.range) { load() }
        .onDisappear { player.pause() }
    }

    var scoreBreakdown: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(text: "AI Potential")
                Spacer()
                PotentialMeter(potential: candidate.potential)
            }
            let tier = PerformanceTier(score: candidate.potential)
            Text("\(tier.emoji) \(tier.displayName) — how well it may perform, from its hook, energy, reactions and ending")
                .font(.pulseMicro).foregroundStyle(Theme.tierColor(tier)).fixedSize(horizontal: false, vertical: true)
            ForEach(candidate.scores.breakdown, id: \.name) { item in
                HStack(spacing: 8) {
                    Text(item.name).font(.pulseCaption).foregroundStyle(Theme.textSecondary).frame(width: 92, alignment: .leading)
                    ThinProgressBar(progress: item.value, color: Theme.ai.opacity(0.8))
                    Text("\(Int((item.value * 100).rounded()))").font(.pulseMono).foregroundStyle(Theme.textTertiary).frame(width: 26, alignment: .trailing)
                }
            }
            Text("An estimate from loudness, reactions, pacing and story shape — not a verdict. Trust your taste.")
                .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.panelRaised))
    }

    /// "Why this moment?": the signals that scored it (#49).
    @ViewBuilder
    var whyCard: some View {
        if let analysis = session.analyses[candidate.assetID], let signals = session.energySignal(for: candidate.assetID) {
            let why = MomentExplanation.explain(candidate: candidate, signals: signals, banners: analysis.hudEvents ?? [])
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionLabel(text: "Why this moment")
                    AIBadge()
                    Spacer()
                }
                Text(why.summary).font(.pulseCaption).foregroundStyle(Theme.textPrimary)
                ForEach(why.signals.prefix(6)) { signal in
                    HStack(spacing: 8) {
                        Text(signal.name).font(.pulseCaption).foregroundStyle(Theme.textSecondary).frame(width: 92, alignment: .leading)
                        ThinProgressBar(progress: signal.value, color: Theme.accent.opacity(0.8))
                        Text(signal.detail).font(.pulseMicro).foregroundStyle(Theme.textTertiary).lineLimit(1).frame(width: 150, alignment: .leading)
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.panelRaised))
        }
    }

    func shorten(by fraction: Double) {
        guard let analysis = session.analyses[candidate.assetID] else { return }
        let shorter = ClipGenerator.shorten(candidate, by: fraction, analysis: analysis, settings: app.settings.ai.generationSettings)
        session.edit("Shorten Clip") { doc in
            if let i = doc.candidates.firstIndex(where: { $0.id == candidate.id }) { doc.candidates[i] = shorter }
        }
        app.toast("Now \(Int(shorter.duration.rounded())) s — the payoff stays in")
    }

    func hookCard(_ hook: HookAdvice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Hook")
                AIBadge()
                Spacer()
                Text("\(Int(hook.strength * 100))%").font(.pulseMono).foregroundStyle(hook.strength > 0.5 ? Theme.success : Theme.warning)
            }
            Text(hook.message).font(.pulseCaption).foregroundStyle(Theme.textSecondary)
            switch hook.recommendation {
            case .startEarlier(let s):
                Button("Start \(Int(s.rounded()))s earlier") { adjust(start: -s) }.buttonStyle(.pulse(.secondary, compact: true))
            case .startLater(let s):
                Button("Start \(Int(s.rounded()))s later") { adjust(start: s) }.buttonStyle(.pulse(.secondary, compact: true))
            case .coldOpen:
                Text("Tip: in the editor, copy the payoff to the start as a 1–2s cold open.").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            case .keep:
                EmptyView()
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.panelRaised))
    }

    var platformCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Platform captions")
                Spacer()
                Button {
                    generateCloudCopy()
                } label: {
                    if aiBusy { HStack(spacing: 6) { IndeterminateBar(width: 40); Text("Rewriting…") } } else { Label("Rewrite with AI", systemImage: "sparkles") }
                }
                .buttonStyle(.pulse(.ghost, compact: true))
                .disabled(aiBusy)
                .help(app.settings.ai.cloudProvider == .none ? "Uses PULSE's local title generator" : "Sends only the transcript text to \(app.settings.ai.cloudProvider.displayName)")
            }
            CopyRow(label: "YouTube Shorts", text: candidate.copy.shortsTitle)
            CopyRow(label: "TikTok", text: candidate.copy.tiktokCaption)
            CopyRow(label: "Instagram", text: candidate.copy.instagramCaption)
            HStack(spacing: 6) {
                Text("Hashtags").font(.pulseMicro).foregroundStyle(Theme.textTertiary).frame(width: 64, alignment: .leading)
                TextField("#tags", text: $editingHashtags, onCommit: commitHashtags)
                    .textFieldStyle(.roundedBorder).font(.pulseCaption)
                    .help("From the clip's tags and the names said in it (a game, a friend) — edit freely, they go into every post below")
            }
            HStack(spacing: 6) {
                ForEach(SharePlatform.allCases, id: \.self) { platform in
                    Button(platform.displayName) { copyShareText(platform) }.buttonStyle(.pulse(.secondary, compact: true))
                }
            }
            .help("Copies the title, caption and hashtags shaped to the platform's limits")
            Text("PULSE never posts anything. Copy what you like — the buttons give you the whole post for one platform.").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
        }
    }

    func load() {
        editingTitle = candidate.title
        editingHashtags = candidate.copy.hashtags.joined(separator: " ")
        guard let asset = session.document.asset(id: candidate.assetID) else { return }
        let item = AVPlayerItem(url: session.url(for: asset))
        item.forwardPlaybackEndTime = .seconds(candidate.range.end)
        player.replaceCurrentItem(with: item)
        player.seek(to: .seconds(candidate.range.start), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func copyShareText(_ platform: SharePlatform) {
        let text = ShareCopy.text(for: platform, candidate: candidate)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        app.toast("Copied the \(platform.displayName) post (\(text.count) characters)")
    }

    func commitHashtags() {
        let tags = Hashtags.parse(editingHashtags)
        guard tags != candidate.copy.hashtags else { return }
        session.setHashtags(editingHashtags, for: candidate.id)
        editingHashtags = tags.joined(separator: " ")
    }

    func commitTitle() {
        let title = editingTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, title != candidate.title else { return }
        session.edit("Rename Clip") { doc in
            if let i = doc.candidates.firstIndex(where: { $0.id == candidate.id }) {
                doc.candidates[i].title = title
                doc.candidates[i].userAdjusted = true
            }
        }
    }

    func adjust(start delta: Seconds) {
        session.edit("Adjust Clip Start") { doc in
            guard let i = doc.candidates.firstIndex(where: { $0.id == candidate.id }) else { return }
            let r = doc.candidates[i].range
            doc.candidates[i].range = TimeRange(start: max(0, r.start + delta), end: r.end)
            doc.candidates[i].userAdjusted = true
            doc.candidates[i].hook = nil
        }
    }

    func generateCloudCopy() {
        let transcript = session.analyses[candidate.assetID]?.transcript?.text(in: candidate.range) ?? candidate.transcriptSnippet
        let context = ClipContext(transcript: transcript, tags: candidate.tags.map(\.rawValue), duration: candidate.duration)
        let provider = AIProviders.insightProvider(settings: app.settings.ai)
        if provider.location == .cloud && app.settings.ai.processingPolicy == .askBeforeUploading {
            let alert = NSAlert()
            alert.messageText = "Send transcript text to \(provider.displayName)?"
            alert.informativeText = "Only the \(transcript.split(separator: " ").count)-word transcript of this clip is sent. Video and audio never leave your Mac."
            alert.addButton(withTitle: "Send")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        if provider.location == .cloud && app.settings.ai.processingPolicy == .alwaysLocal {
            app.presentMessage(title: "Cloud AI is off", message: AIProviderError.cloudNotPermitted.localizedDescription)
            return
        }
        aiBusy = true
        let candidateID = candidate.id
        Task {
            defer { aiBusy = false }
            do {
                let copy = try await provider.copy(for: context)
                session.edit("AI Titles") { doc in
                    if let i = doc.candidates.firstIndex(where: { $0.id == candidateID }) {
                        doc.candidates[i].copy = copy
                        if let first = copy.titles.first, !doc.candidates[i].userAdjusted { doc.candidates[i].title = first }
                    }
                }
                app.logActivity(.captions, title: "New titles for “\(candidate.title)”", detail: copy.generatedBy, location: provider.location)
            } catch {
                app.present(error, title: "Couldn't generate titles")
            }
        }
    }
}

struct CopyRow: View {
    let label: String
    let text: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                .buttonStyle(.pulse(.ghost, compact: true))
            }
            Text(text).font(.pulseCaption).foregroundStyle(Theme.textSecondary).textSelection(.enabled)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.well))
    }
}

/// Wrapping chips for title suggestions.
struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(items.prefix(5), id: \.self) { item in
                Button { onTap(item) } label: {
                    Text(item)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.control))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Resolves the insight provider from settings (Keychain API keys for cloud providers).
enum AIProviders {
    static func insightProvider(settings: AISettings) -> InsightProvider {
        switch settings.cloudProvider {
        case .none:
            return LocalInsightProvider()
        case .anthropic:
            guard let key = KeychainStore.read(account: "anthropic"), !key.isEmpty else { return LocalInsightProvider() }
            return AnthropicInsightProvider(apiKey: key, model: settings.cloudModel.isEmpty ? "claude-opus-5-5" : settings.cloudModel)
        case .openAICompatible:
            let key = KeychainStore.read(account: "openai") ?? ""
            let base = URL(string: settings.openAIBaseURL) ?? URL(string: "http://localhost:1234/v1")!
            return OpenAICompatibleInsightProvider(apiKey: key, model: settings.cloudModel, baseURL: base, isLocalServer: settings.openAIIsLocalServer)
        }
    }
}
