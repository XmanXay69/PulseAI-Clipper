import PulseCore
import PulseEngine
import SwiftUI

/// "Edit My VOD": choose the length and the finishing touches, then PULSE builds a YouTube-ready edit.
struct LongFormSheet: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    @Environment(\.dismiss) private var dismiss
    @AppStorage("longForm.minMinutes") private var minMinutes = 10.0
    @AppStorage("longForm.maxMinutes") private var maxMinutes = 20.0
    @AppStorage("longForm.coldOpen") private var coldOpen = true
    @AppStorage("longForm.zooms") private var zooms = true
    @AppStorage("longForm.captions") private var captions = true
    @AppStorage("longForm.memes") private var memes = true
    @AppStorage("longForm.sfx") private var soundEffects = true
    @AppStorage("longForm.music") private var music = true
    @AppStorage("longForm.restraint") private var restraint = LongFormOptions.Restraint.balanced.rawValue
    @AppStorage("longForm.tighten") private var tighten = false
    @AppStorage("longForm.shortenPauses") private var shortenPauses = false
    @AppStorage("longForm.musicLevel") private var musicLevel = 1.0
    @AppStorage("longForm.chapterTitles") private var chapterTitles = false
    @AppStorage("longForm.progressBar") private var progressBar = false
    @AppStorage("longForm.cutGameOnly") private var cutGameOnly = false
    @AppStorage("longForm.deadAir") private var deadAir = SilencePreset.balanced.rawValue
    /// A line early on that points at the strongest later moment (#582).
    @AppStorage("longForm.tease") private var tease = false
    /// The built-in editing style to cut in (an `EditorPlaybook` id); empty = PULSE's own way.
    @AppStorage("longForm.editStyle") private var editStyle = ""
    @State private var choosing = false
    /// The extras question is showing (asked before anything is built).
    @State private var askingExtras = false
    /// Your answer, once given (the storyboard then builds straight away).
    @State private var extras: EditExtras?
    /// Moments picked in the storyboard while the extras question is open.
    @State private var pendingSegments: [LongFormSegment]?
    /// The storyboard's rows were moved by hand (#109): build in that order.
    @State private var keepOrder = false
    @State private var pendingHook: Seconds?
    /// Settings' default style for this kind of recording was put in the menu when the sheet opened (#626).
    @State private var adoptedDefault = false
    /// The recording isn't analyzed yet, so its kind (and its default style) is only known when the edit starts.
    @State private var followsRecording = false
    /// You changed the style menu yourself: that choice stands.
    @State private var styleTouched = false
    @State private var comparing = false

    var options: LongFormOptions {
        var options = LongFormOptions(minimumLength: minMinutes * 60, maximumLength: max(maxMinutes, minMinutes) * 60, coldOpen: coldOpen,
                                      cutDeadAir: true, zooms: zooms, captions: captions, memes: memes, soundEffects: soundEffects, music: music,
                                      restraint: LongFormOptions.Restraint(rawValue: restraint) ?? .balanced)
        options.extras = extras ?? EditExtras()
        options.keepStoryOrder = keepOrder
        options.tighten = tighten
        options.shortenPauses = shortenPauses
        options.musicLevel = musicLevel
        options.chapterTitles = chapterTitles
        options.progressBar = progressBar
        options.cutGameOnly = cutGameOnly
        options.openLoop = tease
        options.socialHandle = app.settings.ai.socialHandle
        options.deadAir = SilencePreset(rawValue: deadAir) ?? .balanced
        options.memeTexts = app.settings.ai.memeTextsByTag
        if let playbook {
            // The style's tuning (spacing, zoom strength, caption look, pause tightness). The switches above
            // were set to the style when it was picked and stay yours to change.
            options.style = playbook.style.longFormOptions(.recommended(for: playbook.style)).style
        } else if let studied {
            options.style = studied.longFormOptions(.recommended(for: studied)).style
        }
        return options
    }

    /// The picker's tag for a video you studied (Edit Like a Reference), as opposed to a built-in style's id.
    static func studiedTag(_ style: ReferenceStyle) -> String { "studied:\(style.id.uuidString)" }

    /// The studied video chosen as the style, when one is.
    var studied: ReferenceStyle? {
        guard editStyle.hasPrefix("studied:") else { return nil }
        return app.settings.referenceStyles.first { Self.studiedTag($0) == editStyle }
    }

    /// The chosen style's name for the notes under the switches it sets.
    var styleName: String? { playbook?.name ?? studied.map { "“\($0.name)”" } }

    /// Sets the switches to what a studied video does.
    func apply(_ style: ReferenceStyle) {
        let styled = style.longFormOptions(.recommended(for: style))
        coldOpen = styled.coldOpen
        zooms = styled.zooms
        captions = styled.captions
        memes = styled.memes
        soundEffects = styled.soundEffects
        music = styled.music
        restraint = styled.restraint.rawValue
    }

    /// The chosen editing style, if one is.
    var playbook: EditorPlaybook? { EditorPlaybook.playbook(id: editStyle) }

    /// The style most recordings like this one are cut in.
    var suggestedPlaybook: EditorPlaybook? {
        guard let asset = session.document.primaryAsset, let analysis = session.analyses[asset.id] else { return nil }
        return EditorPlaybook.suggested(for: analysis.profile)
    }

    /// Sets the switches to what the style does, so the sheet shows the edit you'll get.
    func apply(_ playbook: EditorPlaybook) {
        let styled = playbook.style.longFormOptions(.recommended(for: playbook.style))
        coldOpen = styled.coldOpen
        zooms = styled.zooms
        captions = styled.captions
        memes = styled.memes
        soundEffects = styled.soundEffects
        music = styled.music
        restraint = styled.restraint.rawValue
        tease = playbook.plantsTease
    }

    var body: some View {
        Group {
            if choosing {
                LongFormStoryboard(session: session, options: options, approving: extras?.approveCut == true,
                                   onBack: { choosing = false; extras = nil }) { segments, hookPayoff, reordered in
                    keepOrder = reordered
                    if extras != nil {
                        build(segments: segments, hookPayoff: hookPayoff)
                    } else if skipExtrasQuestion {
                        extras = app.settings.ai.editExtras.with(approveCut: false)
                        build(segments: segments, hookPayoff: hookPayoff)
                    } else {
                        // Picked the moments first: ask about the extras before building.
                        pendingSegments = segments
                        pendingHook = hookPayoff
                        askingExtras = true
                    }
                }
                .frame(width: 820, height: 680)
                .background(Theme.panel)
                .preferredColorScheme(AppModel.current?.colorScheme)
            } else {
                settingsPage
            }
        }
        .sheet(isPresented: $askingExtras) {
            EditExtrasSheet(session: session, offerApproveCut: !choosing, musicOn: music,
                            onCancel: { askingExtras = false; pendingSegments = nil }) { answer in
                askingExtras = false
                extras = answer
                // Let the question close before this sheet does.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    if let segments = pendingSegments {
                        build(segments: segments, hookPayoff: pendingHook)
                    } else if answer.approveCut {
                        // Approve the cut: review every section before anything is built.
                        choosing = true
                    } else {
                        build(segments: nil, hookPayoff: nil)
                    }
                }
            }
            .environmentObject(app)
        }
    }

    /// The Extras question was answered for this project and you asked not to be asked again (#128).
    var skipExtrasQuestion: Bool { app.settings.ai.askExtrasOncePerProject && session.document.extrasAnswered }

    func build(segments: [LongFormSegment]?, hookPayoff: Seconds?) {
        session.editMyVOD(options: options, segments: segments, hookPayoff: hookPayoff, followDefaultStyle: followsRecording && !styleTouched)
        dismiss()
    }

    /// The genre whose style is chosen now, and the one this recording looks like.
    var selectedGenre: VideoGenre? { VideoGenre.genre(forPlaybook: editStyle) }
    var suggestedGenre: VideoGenre? {
        guard let asset = session.document.primaryAsset, let analysis = session.analyses[asset.id] else { return nil }
        return VideoGenre.suggested(for: analysis.profile)
    }

    /// The genre button: this project is that kind of video from now on, and the sheet is set to its style.
    func pick(_ genre: VideoGenre) {
        styleTouched = true
        followsRecording = false
        editStyle = genre.playbook.id
        apply(genre.playbook)
        session.setGenre(genre)
    }

    /// What kind of video this is. One button decides which editing knowledge the auto-editor uses.
    var genreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "What kind of video is this?")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(VideoGenre.allCases) { genre in
                    let selected = selectedGenre == genre
                    let suggested = suggestedGenre == genre
                    Button { pick(genre) } label: {
                        VStack(spacing: 5) {
                            Image(systemName: genre.symbol).font(.system(size: 15, weight: .medium))
                            Text(genre.displayName).font(.system(size: 11, weight: .semibold)).multilineTextAlignment(.center).lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(selected ? Theme.accent : Theme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .padding(.horizontal, 6)
                        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(selected ? Theme.accent.opacity(0.12) : Theme.panelRaised))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                            .strokeBorder(selected ? Theme.accent : Theme.border, lineWidth: selected ? 1.5 : 1))
                        .overlay(alignment: .topTrailing) {
                            if suggested && !selected { Circle().fill(Theme.ai).frame(width: 6, height: 6).padding(6) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(genre.blurb + (suggested ? " Suggested for this recording." : ""))
                    .accessibilityLabel(genre.displayName)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            if let genre = selectedGenre {
                Text("\(genre.blurb) PULSE cuts it as \(genre.playbook.name), and this project remembers the choice.")
                    .font(.pulseMicro).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("How \(genre.playbook.name) cuts, and where its rules come from") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(genre.playbook.principles, id: \.title) { principle in
                            Text("**\(principle.title).** \(principle.detail)").font(.pulseMicro).foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(genre.sources, id: \.url) { source in
                            if let url = URL(string: source.url) {
                                Link("\(source.title): \(source.gave)", destination: url).font(.pulseMicro)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        Text(genre.studyNote).font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                }
                .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            } else {
                Text(suggestedGenre.map { "Pick one and PULSE cuts the way that kind of video is edited. This recording looks like \($0.displayName.lowercased()) (the dot)." }
                     ?? "Pick one and PULSE cuts the way that kind of video is edited.")
                    .font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The sheet opens on the project's genre when it has one. Otherwise, with "the style that suits each
    /// recording" on in Settings, it opens on that style (#626).
    func adoptDefaultStyle() {
        // A studied video that has since been forgotten can't be the style any more.
        if editStyle.hasPrefix("studied:"), studied == nil { editStyle = "" }
        guard !adoptedDefault else { return }
        if let genre = session.document.genre {
            adoptedDefault = true
            followsRecording = false
            editStyle = genre.playbook.id
            apply(genre.playbook)
            return
        }
        guard app.settings.ai.autoEditStyle, let asset = session.document.primaryAsset else { return }
        adoptedDefault = true
        guard let analysis = session.analyses[asset.id] else {
            editStyle = ""
            followsRecording = true
            return
        }
        followsRecording = false
        let playbook = app.settings.ai.defaultPlaybook(for: analysis.profile)
        editStyle = playbook?.id ?? ""
        if let playbook { apply(playbook) }
    }

    /// What both drafts in "Compare two styles" share: the length and the things that are yours.
    var compareBase: LongFormOptions {
        var base = options
        base.style = nil
        return base
    }

    var settingsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    genreSection
                    editStyleSection
                    lengthSection
                    touchesSection
                    styleSection
                    deadAirSection
                    whatHappens
                }
                .padding(20)
            }
            Divider().overlay(Theme.divider)
            footer
        }
        .frame(width: 560, height: 640)
        .background(Theme.panel)
        .preferredColorScheme(AppModel.current?.colorScheme)
        .onAppear { adoptDefaultStyle() }
        .sheet(isPresented: $comparing) {
            let suggested = suggestedPlaybook?.id ?? EditorPlaybook.retention.id
            // Compare works on the built-in styles; a studied video stands in as PULSE's own there.
            let first = editStyle.isEmpty || studied != nil ? AISettings.ownStyle : editStyle
            StyleCompareSheet(session: session, base: compareBase, firstID: first,
                              secondID: first == suggested ? (suggested == EditorPlaybook.story.id ? EditorPlaybook.retention.id : EditorPlaybook.story.id) : suggested) { picked in
                styleTouched = true
                followsRecording = false
                editStyle = picked == AISettings.ownStyle ? "" : picked
            }
            .environmentObject(app)
        }
    }

    var header: some View {
        SheetHeader("Edit My VOD", symbol: "film.stack", subtitle: "Turn the whole stream into a YouTube video that feels produced, not a raw VOD.")
    }

    var lengthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Length")
            HStack(spacing: 10) {
                Stepper(value: $minMinutes, in: 3...30, step: 1) {
                    Text("\(Int(minMinutes)) min").font(.pulseBody).monospacedDigit()
                }
                Text("to").foregroundStyle(Theme.textTertiary)
                Stepper(value: $maxMinutes, in: 5...45, step: 1) {
                    Text("\(Int(max(maxMinutes, minMinutes))) min").font(.pulseBody).monospacedDigit()
                }
            }
            if let asset = session.document.primaryAsset {
                let target = options.targetLength(forSource: asset.metadata.duration)
                Text("From \(Timecode.duration(asset.metadata.duration)) of stream → \(target < 55 ? "under a minute" : DurationText.approximate(target)) of video.")
                    .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    var touchesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Add")
            touch("Fire hook", "flame.fill", "Opens with a teaser of the best moment", $coldOpen)
            touch("Tease", "hourglass", "A line in the first half minute that points at the strongest later moment", $tease)
            touch("Zooms", "plus.magnifyingglass", "Punch-ins on the big reactions", $zooms)
            touch("Captions", "captions.bubble", "Clean subtitles — outlined, no box, easy to read", $captions)
            touch("Memes", "face.smiling", "Pop-up text on the funniest moments", $memes, preview: .memes)
            touch("Sound effects", "speaker.wave.2.fill", "Whooshes, booms and comedy stings", $soundEffects)
            touch("Music", "music.note", "A quiet, calm bed under each chapter, ducked under talking", $music)
            if music {
                HStack(spacing: 8) {
                    Text("Music level").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    Slider(value: $musicLevel, in: 0.5...2, step: 0.25).frame(width: 140)
                    Text(musicLevel == 1 ? "normal" : String(format: "%.2g×", musicLevel)).font(.pulseMono).foregroundStyle(Theme.textTertiary)
                }
                .padding(.leading, 20)
            }
            touch("Tighten", "scissors", "Cut the ums, uhs and false starts (word timing isn't perfect — check the result)", $tighten)
            touch("Shorten pauses", "forward.frame", "Play 1–4 s pauses at 1.6× instead of cutting them — the breath stays, the wait goes", $shortenPauses)
            touch("Chapter titles", "text.below.photo", "A small lower-third with the chapter's name at the start of each chapter", $chapterTitles)
            touch("Progress bar", "minus", "A thin bar along the bottom edge that fills as the video plays — the \"how much is left\" cue", $progressBar)
            touch("Cut game-only stretches", "speaker.slash", "Drop 8 s or more of loud game with nobody talking inside a kept moment (its payoff stays)", $cutGameOnly)
            if music {
                touch("Find music on YouTube", "globe", "Creative Commons tracks via the built-in downloader (credits go in the description)",
                      Binding(get: { app.settings.ai.onlineMusic }, set: { app.settings.ai.onlineMusic = $0 }))
                    .padding(.leading, 20)
                if app.settings.ai.onlineMusic {
                    Toggle("Download five tracks per mood while the Mac is idle", isOn: Binding(get: { app.settings.ai.prefetchMusic }, set: { app.settings.ai.prefetchMusic = $0 }))
                        .toggleStyle(.checkbox).font(.pulseCaption)
                        .padding(.leading, 40)
                        .help("Every ten minutes, with nothing running, no input for three minutes and the Mac plugged in, each mood's shelf is topped up so an edit never waits on a download (#303)")
                }
            }
        }
    }

    func touch(_ title: String, _ symbol: String, _ detail: String, _ isOn: Binding<Bool>, preview: ExtraPreview.Kind? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(isOn.wrappedValue ? Theme.ai : Theme.textTertiary).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.pulseBody).foregroundStyle(Theme.textPrimary)
                Text(detail).font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            // The memes as they'll look (#104): the moods' pop-ups in their colours.
            if let preview { ExtraPreview(kind: preview).opacity(isOn.wrappedValue ? 1 : 0.45) }
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(Theme.ai)
        }
        .padding(.vertical, 4)
    }

    /// Which school of editing to cut in: PULSE's own way, or one of the built-in styles.
    var editStyleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Editing style")
            HStack(spacing: 8) {
                Picker("Editing style", selection: Binding(get: { editStyle }, set: { styleTouched = true; followsRecording = false; editStyle = $0 })) {
                    Text("PULSE's own").tag("")
                    Divider()
                    ForEach(EditorPlaybook.all.filter { !$0.style.isShortForm }) { Text($0.name).tag($0.id) }
                    if !app.settings.referenceStyles.isEmpty {
                        Divider()
                        // Videos studied in Edit Like a Reference.
                        ForEach(app.settings.referenceStyles) { Text("Like “\($0.name)”").tag(Self.studiedTag($0)) }
                    }
                }
                .labelsHidden()
                .frame(width: 200)
                .onChange(of: editStyle) { _, _ in
                    if let playbook { apply(playbook) } else if let studied { apply(studied) }
                    if styleTouched { session.setGenre(selectedGenre) }
                }
                Button("Compare two…") { comparing = true }
                    .buttonStyle(.pulse(.ghost, compact: true))
                    .fixedSize()
                    .disabled(suggestedPlaybook == nil)
                    .help(suggestedPlaybook == nil ? "Analyze the recording first" : "Draft this recording in two styles and see the coach's score and the predicted retention for each, side by side")
                Spacer(minLength: 0)
            }
            Text(playbook.map { "\($0.tagline) Best for \($0.bestFor.lowercased())." }
                 ?? studied.map(studiedNote)
                 ?? "Restrained zooms, captions, memes, sound effects and music: the way PULSE has always cut.")
                .font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            if let playbook {
                Text(playbook.recipe.joined(separator: " · ")).font(.pulseMicro).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Always start from the style that suits the recording", isOn: Binding(get: { app.settings.ai.autoEditStyle }, set: { on in
                app.settings.ai.autoEditStyle = on
                adoptedDefault = false
                followsRecording = false
                if on { adoptDefaultStyle() }
            }))
            .toggleStyle(.checkbox).font(.pulseCaption)
            .help("Gameplay opens on Retention cut, podcasts and talking-head on Clean commentary, anything else on Story first. Change which style each kind gets in Settings → AI Features. Shorts and the overnight batch follow it too.")
            if followsRecording {
                Text("This recording isn't analyzed yet. Its style is chosen when the edit starts, once PULSE knows what kind it is.")
                    .font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One line about a studied video chosen as the style: what was measured, and whether a model's lessons come with it.
    func studiedNote(_ style: ReferenceStyle) -> String {
        var note = "Measured from a video you studied: \(style.summary.lowercased())."
        if let lessons = style.lessons {
            let rules = lessons.planningGuidance.count
            note += rules > 0
                ? " Plan with the model follows the \(rules) rule\(rules == 1 ? "" : "s") it teaches about openings, pacing and story."
                : " A model read it, but found no rules about openings, pacing or story for the planner."
        } else {
            note += " Ask what it teaches in Edit Like a Reference, and Plan with the model will follow its rules."
        }
        return note
    }

    var styleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "How much editing")
            PulseSegmented(selection: $restraint, segments: LongFormOptions.Restraint.allCases.map { PulseSegment($0.rawValue, $0.displayName) })
                .disabled(styleName != nil)
            Text(styleName.map { "Set by \($0): its own spacing for zooms, pop-ups and effects." } ?? restraintNote)
                .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
        }
    }

    var deadAirSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Dead air")
            PulseSegmented(selection: $deadAir, segments: [PulseSegment(SilencePreset.conservative.rawValue, "Light"), PulseSegment(SilencePreset.balanced.rawValue, "Normal"), PulseSegment(SilencePreset.aggressive.rawValue, "Tight")])
                .disabled(styleName != nil)
            Text(styleName.map { "Set by \($0): \(options.silencePreset.displayName.lowercased()) pause cutting." } ?? deadAirNote)
                .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
        }
    }

    var deadAirNote: String {
        switch SilencePreset(rawValue: deadAir) ?? .balanced {
        case .conservative: return "Only pauses over 1.2 s go — the most natural rhythm."
        case .balanced: return "Recommended. Pauses over 0.7 s are cut; breaths stay."
        case .aggressive: return "Pauses over 0.4 s are cut — fast, YouTube-essay pacing."
        }
    }

    var restraintNote: String {
        switch LongFormOptions.Restraint(rawValue: restraint) ?? .balanced {
        case .subtle: return "Barely-there: a zoom every 40 s at most, a meme every few minutes."
        case .balanced: return "Recommended. Effects only on the moments that earn them — never on every line."
        case .energetic: return "More zooms and memes for high-energy channels. Still spaced out."
        }
    }

    var whatHappens: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "What PULSE does")
            Group {
                Label("Cuts the dead time and long pauses", systemImage: "scissors")
                Label("Keeps the funniest, highest-energy moments with enough context to follow", systemImage: "sparkles")
                Label("Builds chapters and a YouTube chapter list for your description", systemImage: "list.bullet")
                Label("Everything lands on the timeline — change anything afterwards", systemImage: "slider.horizontal.3")
                Label("Next, PULSE asks which extras you want — nothing extra happens unless you say yes", systemImage: "questionmark.bubble")
            }
            .font(.pulseCaption).foregroundStyle(Theme.textSecondary)
        }
    }

    var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if session.document.primaryAsset != nil {
                let analyzed = session.document.primaryAsset.flatMap { session.analyses[$0.id] } != nil
                let estimate = session.longFormEstimate(options: options) + (analyzed ? 0 : session.document.primaryAsset.map(session.analysisEstimate) ?? 0)
                Label("Takes \(DurationText.approximate(estimate))\(analyzed ? "" : " (includes analyzing)")", systemImage: "clock")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            footerButtons
        }
        .padding(16)
    }

    var footerButtons: some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { app.showReferenceSheet = true }
            } label: { Label("Editing styles…", systemImage: "wand.and.stars") }
                .buttonStyle(.pulse(.ghost, compact: true))
                .fixedSize()
                .help("Cut it in a style editors use, or like a video you love, instead")
            Spacer(minLength: 4)
            Button("Cancel") { dismiss() }.buttonStyle(.pulseSecondary).keyboardShortcut(.cancelAction).fixedSize()
            let analyzed = session.document.primaryAsset.flatMap { session.analyses[$0.id] }.map { $0.audio != nil || $0.transcript != nil } ?? false
            Button { choosing = true } label: { Text("Choose moments…") }
                .buttonStyle(.pulseSecondary)
                .fixedSize()
                .disabled(!analyzed)
                .help(analyzed ? "See every moment PULSE picked, swap some out and choose the hook" : "Analyze the video first (or just press Edit My VOD)")
            Button {
                extras = nil
                if skipExtrasQuestion {
                    // Answered once for this project (#128): reuse the answers.
                    let answer = app.settings.ai.editExtras
                    extras = answer
                    if answer.approveCut { choosing = true } else { build(segments: nil, hookPayoff: nil) }
                } else {
                    askingExtras = true
                }
            } label: { Label("Edit My VOD…", systemImage: "wand.and.stars") }
                .buttonStyle(.pulsePrimary)
                .fixedSize()
                .keyboardShortcut(.defaultAction)
                .disabled(session.document.primaryAsset == nil)
        }
    }
}
