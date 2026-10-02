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
        .preferredColorScheme(.dark)
        .onAppear { if let style = reference.current { answers = .recommended(for: style) } }
        .onChange(of: reference.current?.id) { _, _ in
            if let style = reference.current { answers = .recommended(for: style) }
        }
    }

    var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars").font(.system(size: 20)).foregroundStyle(Theme.ai)
                .frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: 10).fill(Theme.aiSoft))
            VStack(alignment: .leading, spacing: 3) {
                Text("Edit Like a Reference").font(.pulseTitle).foregroundStyle(Theme.textPrimary)
                Text(reference.current.map { "Studied “\($0.name)” — answer a few questions, then PULSE edits your VOD the same way." }
                     ?? "Show PULSE a video whose editing you love. It studies the cuts, zooms, captions, music and effects, then edits your VOD that way.")
                    .font(.pulseCaption).foregroundStyle(Theme.textSecondary).lineLimit(2)
            }
        }
        .padding(20)
    }

    // MARK: Step 1 — pick a reference

    var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 10) {
                    Image(systemName: "film.stack").font(.system(size: 30)).foregroundStyle(dropTargeted ? Theme.accent : Theme.textTertiary)
                    Text("Drop a reference video here").font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
                    Text("A YouTube video, TikTok or short you'd like yours to feel like. Download it first — PULSE studies it right here on your Mac; nothing is uploaded.")
                        .font(.pulseCaption).foregroundStyle(Theme.textTertiary).multilineTextAlignment(.center).frame(maxWidth: 420)
                    Button("Choose Video…") { choose() }.buttonStyle(.pulsePrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .background(RoundedRectangle(cornerRadius: Theme.radiusLarge).fill(dropTargeted ? Theme.accent.opacity(0.08) : Theme.panelRaised))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge)
                    .strokeBorder(dropTargeted ? Theme.accent : Theme.border, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                    loadURLs(from: providers) { urls in if let url = urls.first { reference.study(url) } }
                    return true
                }
                if let failure = reference.failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill").font(.pulseCaption).foregroundStyle(Theme.warning)
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
                Text("\(style.summary) · studied \(style.measuredAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.pulseMicro).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            Spacer()
            Button("Use") { reference.current = style }.buttonStyle(.pulse(.secondary, compact: true))
            Button { reference.forget(style) } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(Theme.textTertiary).help("Forget this style")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.panelRaised))
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
                SectionLabel(text: "How “\(style.name)” is edited")
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
                        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.panelRaised))
                    }
                }

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
        case .likeReference: return "About as long as the reference (~\(Timecode.short(style.duration)))"
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
                Button { reference.current = nil } label: { Label("Different Reference", systemImage: "arrow.uturn.backward") }
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
                    app.session?.editLikeReference(style, answers: answers)
                    dismiss()
                } label: {
                    Label(answers.length == .shorts ? "Make \(answers.shortsCount) Short\(answers.shortsCount == 1 ? "" : "s") Like This" : "Edit My VOD Like This",
                          systemImage: "wand.and.stars")
                }
                .buttonStyle(.pulseAI)
                .keyboardShortcut(.defaultAction)
                .disabled(app.session?.document.primaryAsset == nil)
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
