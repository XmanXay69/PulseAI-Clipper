import AppKit
import PulseCore
import PulseEngine
import SwiftUI
import UniformTypeIdentifiers

/// "Edit Like a Reference": give PULSE a video whose editing you like, answer a few questions,
/// and it edits your VOD the same way (pacing, jump cuts, zooms, captions, music, effects, pop-ups).
struct ReferenceSheet: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var reference: ReferenceController
    @Environment(\.dismiss) private var dismiss
    @State private var answers = ReferenceAnswers()
    @State private var dropTargeted = false
    /// The extras question before a long-form edit.
    @State private var askingExtras = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.divider)
            Group {
                if reference.isStudying {
                    studying
                } else if let style = reference.current {
                    questions(style)
                } else {
                    picker
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().overlay(Theme.divider)
            footer
        }
        .frame(width: 780, height: 680)
        .background(Theme.panel)
        .preferredColorScheme(AppModel.current?.colorScheme)
        .onAppear { if let style = reference.current { answers = .recommended(for: style) } }
        .onChange(of: reference.current?.id) { _, _ in
            if let style = reference.current { answers = .recommended(for: style) }
        }
    }

    var header: some View {
        SheetHeader("Edit Like a Reference", symbol: "wand.and.stars",
                    subtitle: reference.current.map { style in
                        EditorPlaybook.playbook(for: style) != nil
                            ? "“\(style.name)” — answer a few questions, then PULSE edits your VOD in this style."
                            : "Studied “\(style.name)” — answer a few questions, then PULSE edits your VOD the same way."
                    } ?? "Pick a style editors cut in, or show PULSE a video whose editing you love. It edits your VOD that way.")
    }

    // MARK: Step 1 — pick a reference

    /// The style most recordings like the open one are cut in.
    var suggestedPlaybook: EditorPlaybook? {
        guard let session = app.session, let asset = session.document.primaryAsset, let analysis = session.analyses[asset.id] else { return nil }
        return EditorPlaybook.suggested(for: analysis.profile)
    }

    /// One built-in editing style: what it feels like, what it's for, and what the edit will do.
    func playbookCard(_ playbook: EditorPlaybook) -> some View {
        Button { reference.current = playbook.style } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: playbook.symbol).font(.system(size: 13)).foregroundStyle(Theme.accent).frame(width: 18)
                    Text(playbook.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 4)
                    if suggestedPlaybook == playbook { TagChip(text: "Suggested", color: Theme.accent) }
                }
                Text(playbook.tagline).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                Text(playbook.bestFor).font(.pulseMicro).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .raisedSurface(cornerRadius: Theme.radiusLarge)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(playbook.recipe.joined(separator: " · "))
    }

    var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Editing styles")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(EditorPlaybook.all) { playbook in playbookCard(playbook) }
                    }
                    Text("How working editors cut, written down as settings: pacing, zooms, captions, music and effects. Nothing is uploaded.")
                        .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                }
                SectionLabel(text: "Or study a video you love")
                VStack(spacing: 10) {
                    Image(systemName: "film.stack").font(.system(size: 30)).foregroundStyle(dropTargeted ? Theme.accent : Theme.textTertiary)
                    Text("Drop a reference video here").font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
                    Text("A YouTube video, TikTok or short you'd like yours to feel like. Download it first — PULSE studies it right here on your Mac; nothing is uploaded.")
                        .font(.pulseCaption).foregroundStyle(Theme.textTertiary).multilineTextAlignment(.center).frame(maxWidth: 420)
                    Button("Choose Video…") { choose() }.buttonStyle(.pulsePrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .background(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous).fill(dropTargeted ? Theme.accent.opacity(0.08) : Theme.panelRaised))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                    .strokeBorder(dropTargeted ? Theme.accent : Theme.border, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                    loadURLs(from: providers) { urls in if let url = urls.first { reference.study(url) } }
                    return true
                }
                if let failure = reference.failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill").font(.pulseCaption).foregroundStyle(Theme.warning)
                }
                if let mine = app.settings.ownStyle {
                    SectionLabel(text: "Your own style")
                    ownStyleRow(mine, samples: app.settings.ownStyleSamples.count)
                }
                if !reference.saved.isEmpty {
                    SectionLabel(text: "Styles you've studied")
                    ForEach(reference.saved) { style in savedRow(style) }
                }
            }
            .padding(20)
        }
    }

    func savedRow(_ style: ReferenceStyle) -> some View {
        HStack(spacing: 10) {
            Image(systemName: style.isVertical ? "rectangle.portrait" : "rectangle").foregroundStyle(Theme.ai).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(style.name).font(.pulseBody).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text("\(style.summary) · studied \(style.measuredAt.formatted(date: .abbreviated, time: .omitted))" + (style.lastUsedAt.map { " · used \($0.formatted(.relative(presentation: .named)))" } ?? ""))
                    .font(.pulseMicro).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            Spacer()
            Button("Use") { reference.current = style }.buttonStyle(.pulse(.secondary, compact: true))
            Button { reference.forget(style) } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(Theme.textTertiary).help("Forget this style")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.panelRaised))
    }

    /// "Edit like my last videos" (#489): the average of how your recent exports were cut.
    func ownStyleRow(_ style: ReferenceStyle, samples: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.rectangle").foregroundStyle(Theme.accent).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("Edit like my last \(samples == 1 ? "video" : "\(samples) videos")").font(.pulseBody).foregroundStyle(Theme.textPrimary)
                Text("\(style.summary) · measured from your exports, nothing uploaded").font(.pulseMicro).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            Spacer()
            Button("Use") { reference.current = style }.buttonStyle(.pulse(.secondary, compact: true))
            Button { app.settings.ownStyleSamples = [] } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(Theme.textTertiary).help("Forget what PULSE learned from your exports")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.panelRaised))
        .help("PULSE keeps the fingerprint of your last ten exports — pacing, zooms, captions, music, effects — and can edit the next one the same way (#489)")
    }

    // MARK: Step 2 — studying

    var studying: some View {
        VStack(spacing: 14) {
            ProgressView(value: reference.progress).progressViewStyle(.linear).tint(Theme.ai).frame(width: 380)
            Text("Studying “\(reference.studyingName)”").font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
            Text(reference.stage).font(.pulseCaption).foregroundStyle(Theme.textSecondary)
            if let remaining = reference.remaining {
                Text(remaining).font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            }
            Text("You can close this window — it keeps going in the background, and the style is saved for next time.")
                .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            Button("Stop") { reference.cancel() }.buttonStyle(.pulse(.ghost, compact: true))
        }
    }

    // MARK: Step 3 — the fingerprint and the questions

    func questions(_ style: ReferenceStyle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let playbook = EditorPlaybook.playbook(for: style) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "How this style cuts")
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(playbook.principles, id: \.self) { principle in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(principle.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                                    Text(principle.detail).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .card(padding: 14)
                    }
                }
                SectionLabel(text: EditorPlaybook.playbook(for: style) != nil ? "What the edit will do" : "How “\(style.name)” is edited")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(style.traits, id: \.self) { trait in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: trait.symbol).font(.system(size: 12)).foregroundStyle(Theme.ai).frame(width: 18).padding(.top, 1)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(trait.title).font(.pulseCaption).foregroundStyle(Theme.textPrimary)
                                Text(trait.detail).font(.pulseMicro).foregroundStyle(Theme.textTertiary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.panelRaised))
                    }
                }

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(style.explain(answers), id: \.self) { line in
                            Text("• " + line).font(.pulseMicro).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Text("What copying it changes").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                }
                .help("Each setting the reference sets, with the measurement behind it (#368)")

                question("How long should your video be?") {
                    ForEach(ReferenceAnswers.Length.allCases, id: \.self) { length in
                        choice(lengthTitle(length, style), selected: answers.length == length,
                               recommended: ReferenceAnswers.recommended(for: style).length == length) { answers.length = length }
                    }
                    if answers.length == .shorts {
                        Stepper(value: $answers.shortsCount, in: 1...10) {
                            Text("\(answers.shortsCount) short\(answers.shortsCount == 1 ? "" : "s") from your best clips").font(.pulseCaption)
                        }
                        .padding(.leading, 26)
                    }
                }
                question("What should it focus on?") {
                    ForEach(ReferenceAnswers.Focus.allCases, id: \.self) { focus in
                        choice(focus.displayName, selected: answers.focus == focus, recommended: focus == .everything) { answers.focus = focus }
                    }
                }
                question("How closely should it copy the style?") {
                    ForEach(ReferenceAnswers.Closeness.allCases, id: \.self) { closeness in
                        choice(closeness.displayName, selected: answers.closeness == closeness, recommended: closeness == .closely) {
                            answers.closeness = closeness
                        }
                    }
                }
                if answers.length != .shorts {
                    question("Open with a hook?") {
                        choice("Yes — start with the best moment, then the story", selected: answers.coldOpen,
                               recommended: ReferenceAnswers.recommended(for: style).coldOpen) { answers.coldOpen = true }
                        choice("No — start from the beginning", selected: !answers.coldOpen,
                               recommended: !ReferenceAnswers.recommended(for: style).coldOpen) { answers.coldOpen = false }
                    }
                }
                question("What should it copy? (off = PULSE's usual way)") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                        copyToggle("Pacing & jump cuts", $answers.copyPacing)
                        copyToggle("Zooms", $answers.copyZooms)
                        copyToggle("Captions", $answers.copyCaptions)
                        copyToggle("Music", $answers.copyMusic)
                        copyToggle("Sound effects", $answers.copySoundEffects)
                        copyToggle("Text & meme pop-ups", $answers.copyPopups)
                        copyToggle("Transitions", $answers.copyTransitions)
                    }
                }
                Label(plan(style), systemImage: "sparkles").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
    }

    func question<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
            content()
        }
    }

    func choice(_ title: String, selected: Bool, recommended: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Theme.accent : Theme.textTertiary)
                Text(title).font(.pulseBody).foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                if recommended {
                    Text("Suggested").font(.pulseMicro).foregroundStyle(Theme.ai)
                        .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Theme.aiSoft))
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func copyToggle(_ title: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Text(title).font(.pulseBody) }
            .toggleStyle(.checkbox)
    }

    func lengthTitle(_ length: ReferenceAnswers.Length, _ style: ReferenceStyle) -> String {
        switch length {
        case .likeReference:
            return EditorPlaybook.playbook(for: style) != nil ? "This style's usual length (~\(Timecode.short(style.duration)))"
                : "About as long as the reference (~\(Timecode.short(style.duration)))"
        case .youtube: return "A 10–20 minute YouTube video"
        case .medium: return "5–8 minutes"
        case .short: return "Under 3 minutes"
        case .shorts: return "Vertical shorts in this style"
        }
    }

    /// What will happen, in one sentence.
    func plan(_ style: ReferenceStyle) -> String {
        if answers.length == .shorts {
            return "PULSE builds \(answers.shortsCount) short\(answers.shortsCount == 1 ? "" : "s") from your best clips with this style's captions, zooms, pacing and effects."
        }
        let o = style.longFormOptions(answers)
        var parts: [String] = []
        if o.coldOpen { parts.append("a hook") }
        switch o.silencePreset {
        case .aggressive: parts.append("tight jump cuts")
        case .balanced: parts.append("trimmed pauses")
        case .conservative: parts.append("natural pauses")
        }
        if o.zooms { parts.append(o.style?.rhythmZooms == true ? "punch-ins on most sentences" : "zooms about every \(Int(o.zoomSpacing)) s") }
        if o.captions { parts.append(o.style?.captionLook != nil ? "captions in the reference's look" : "captions") }
        if o.music { parts.append("music") }
        if o.soundEffects { parts.append("sound effects") }
        if o.memes { parts.append("pop-ups") }
        if o.style?.fades == true { parts.append("fades between sections") }
        let minutes = "\(Int((o.minimumLength / 60).rounded()))–\(Int((o.maximumLength / 60).rounded())) min"
        return "A \(minutes) edit with " + parts.joined(separator: ", ") + ". Everything stays editable."
    }

    // MARK: Footer

    var footer: some View {
        HStack(spacing: 10) {
            if reference.current != nil, !reference.isStudying {
                Button { reference.current = nil } label: { Label("Different style", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(.pulse(.ghost, compact: true))
            }
            if app.session?.document.primaryAsset == nil, reference.current != nil {
                Text("Open a project with your VOD to use this — the style is saved for later.")
                    .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Button("Close") { dismiss() }.buttonStyle(.pulseSecondary).keyboardShortcut(.cancelAction)
            if let style = reference.current, !reference.isStudying {
                Button {
                    if answers.length == .shorts {
                        app.session?.editLikeReference(style, answers: answers)
                        dismiss()
                    } else if app.settings.ai.askExtrasOncePerProject, app.session?.document.extrasAnswered == true {
                        // Answered once for this project (#128).
                        app.session?.editLikeReference(style, answers: answers, extras: app.settings.ai.editExtras.with(approveCut: false))
                        dismiss()
                    } else {
                        askingExtras = true
                    }
                } label: {
                    Label(answers.length == .shorts ? "Make \(answers.shortsCount) Short\(answers.shortsCount == 1 ? "" : "s") Like This" : "Edit My VOD Like This",
                          systemImage: "wand.and.stars")
                }
                .buttonStyle(.pulsePrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(app.session?.document.primaryAsset == nil)
                .sheet(isPresented: $askingExtras) {
                    if let session = app.session {
                        EditExtrasSheet(session: session, offerApproveCut: false, musicOn: style.longFormOptions(answers).music,
                                        onCancel: { askingExtras = false }) { extras in
                            askingExtras = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                session.editLikeReference(style, answers: answers, extras: extras)
                                dismiss()
                            }
                        }
                        .environmentObject(app)
                    }
                }
            }
        }
        .padding(16)
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .video]
        panel.message = "Choose a video whose editing style you'd like to copy"
        if panel.runModal() == .OK, let url = panel.url { reference.study(url) }
    }
}
