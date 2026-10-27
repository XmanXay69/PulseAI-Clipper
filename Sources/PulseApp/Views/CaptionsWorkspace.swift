import PulseCore
import PulseEngine
import SwiftUI

struct CaptionsWorkspace: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession

    static func generateCaptions(session: ProjectSession) {
        guard let timeline = session.activeTimeline,
              let assetID = timeline.origin?.assetID ?? timeline.assetIDs.first,
              let transcript = session.analyses[assetID]?.transcript else {
            session.app.presentMessage(title: "No transcript yet", message: "Transcribe the recording first (Import → Analyze), or import an SRT/VTT file.")
            return
        }
        let clipRanges = timeline.allClips.filter { $0.assetID == assetID }.map(\.sourceRange)
        let range = timeline.origin?.sourceRange ?? clipRanges.dropFirst().reduce(clipRanges.first ?? .zero) { $0.union($1) }
        let style = CaptionStyle.preset(named: session.app.settings.ai.captionPresetName) ?? .tiktok
        session.editTimeline("Generate Captions") { t in
            t.captions = CaptionTrack.make(from: transcript, range: range, assetID: assetID, style: style, emphasize: true)
        }
    }

    var body: some View {
        if let timeline = session.activeTimeline {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ViewerView(session: session)
                    if timeline.captions != nil {
                        CaptionWordEditor(session: session)
                            .frame(height: 230)
                    }
                }
                .frame(maxWidth: .infinity)
                Rectangle().fill(Theme.divider).frame(width: 1)
                CaptionStylePanel(session: session)
                    .frame(width: 360)
            }
        } else {
            EmptyStateView(symbol: "captions.bubble", title: "Open a clip to caption it",
                           message: "Captions live on a timeline. Open an AI clip or create a timeline first.",
                           actionTitle: "Go to AI Clips") { app.section = .aiClips }
        }
    }
}

struct CaptionStylePanel: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession

    var captions: CaptionTrack? { session.activeTimeline?.captions }
    @State private var findText = ""
    @State private var replaceText = ""
    @State private var showSpelling = false
    /// The mouse is over the preset gallery, so the swatches animate (#233).
    @State private var galleryHovering = false

    func shiftCaptions(by delta: Seconds) {
        session.editTimeline("Shift Captions") { $0.captions?.shiftTiming(by: delta) }
        session.app.toast("Captions moved \(delta > 0 ? "later" : "earlier") by \(Int(abs(delta) * 1000)) ms")
    }

    /// Only the words from the playhead on (#241): the source time under the playhead decides.
    func shiftCaptionsAfterPlayhead(by delta: Seconds) {
        guard let timeline = session.activeTimeline, let captions = timeline.captions else { return }
        let playhead = session.playhead
        let source = timeline.tracks.first { $0.kind == .video }?.clips.first { $0.content.assetID == captions.sourceAssetID && $0.timelineRange.contains(playhead) }
            .map { $0.sourceIn + (playhead - $0.start) * $0.speed }
        guard let source else { session.app.toast("Put the playhead on the captioned video first"); return }
        var count = 0
        session.editTimeline("Shift Captions After Playhead") { count = $0.captions?.shiftTiming(by: delta, after: source) ?? 0 }
        session.app.toast("\(count) words from the playhead on moved \(delta > 0 ? "later" : "earlier") by \(Int(abs(delta) * 1000)) ms")
    }

    func sentenceCase() {
        var count = 0
        session.editTimeline("Sentence Case") { count = $0.captions?.applySentenceCase() ?? 0 }
        session.app.toast(count == 0 ? "Already in sentence case" : "\(count) words re-cased")
    }

    func stripFillers() {
        var count = 0
        session.editTimeline("Remove Fillers") { count = $0.captions?.stripFillers() ?? 0 }
        session.app.toast(count == 0 ? "No um / uh in the captions" : "\(count) filler word\(count == 1 ? "" : "s") removed from the captions (the audio keeps them)")
    }

    func positionCaptions(for platform: SafeAreaPlatform) {
        session.editTimeline("Captions for \(platform.displayName)") { $0.captions?.style.position(for: platform) }
        session.app.toast("Captions sit at \(Int((platform.captionCenterY * 100).rounded())) %, above \(platform.displayName)'s own UI")
    }

    func replaceAllInCaptions() {
        var count = 0
        session.editTimeline("Replace in Captions") { count = $0.captions?.replaceAll(findText, with: replaceText) ?? 0 }
        session.app.toast(count == 0 ? "“\(findText)” isn't in the captions" : "Replaced in \(count) word\(count == 1 ? "" : "s")")
    }

    func applyShadow(_ preset: CaptionStyle.ShadowPreset) {
        session.editTimeline("Shadow: \(preset.displayName)") { t in
            guard var style = t.captions?.style else { return }
            preset.apply(to: &style)
            t.captions?.style = style
        }
    }

    func addLaughEmoji() {
        var count = 0
        session.editTimeline("Laugh Emoji") { count = $0.captions?.addLaughEmoji() ?? 0 }
        session.app.toast(count == 0 ? "No laughter words without an emoji" : "😂 on \(count) laugh\(count == 1 ? "" : "s")")
    }

    /// The audio censoring in force on this timeline (the first clip that has any).
    var audioCensor: CensorAudio { session.activeTimeline?.allClips.first { $0.audio.censors }?.audio.censor ?? .off }

    var audioCensorNote: String {
        let n = session.activeTimeline?.allClips.reduce(0) { $0 + $1.audio.censorRanges.count } ?? 0
        return audioCensor == .off
            ? "Mute or bleep the words the caption filter masks. Rendered into the enhance cache — the source file is never changed."
            : "\(n) stretch\(n == 1 ? "" : "es") \(audioCensor == .mute ? "muted" : "bleeped") across this timeline's clips."
    }

    func setAudioCensor(_ mode: CensorAudio) {
        let extra = session.app.settings.ai.normalizedExtraProfanity
        session.editTimeline("Censor Audio") { t in
            for id in Set(t.allClips.compactMap(\.content.assetID)) {
                guard let words = session.analyses[id]?.transcript?.words else { continue }
                AudioCensor.apply(mode, to: &t, words: words, assetID: id, extra: extra)
            }
        }
    }

    func applyHighlight(_ preset: HighlightPreset) {
        session.editTimeline("Highlight: \(preset.name)") { t in
            guard var style = t.captions?.style else { return }
            preset.apply(to: &style)
            t.captions?.style = style
        }
    }

    func styleBinding<T>(_ label: String, _ keyPath: WritableKeyPath<CaptionStyle, T>, fallback: T) -> Binding<T> {
        Binding(get: { session.activeTimeline?.captions?.style[keyPath: keyPath] ?? fallback },
                set: { v in
                    session.editTimeline(label, coalesce: "caption-\(label)") { t in
                        t.captions?.style[keyPath: keyPath] = v
                        if t.captions?.style.presetName != "Custom", CaptionStyle.preset(named: t.captions?.style.presetName ?? "") != t.captions?.style {
                            t.captions?.style.presetName = "Custom"
                        }
                    }
                })
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader("Caption Style", subtitle: captions?.style.presetName)
            if captions == nil {
                VStack(spacing: 12) {
                    EmptyStateView(symbol: "captions.bubble", title: "No captions", message: "Generate word-timed captions from the transcript.",
                                   actionTitle: "Generate Captions") { CaptionsWorkspace.generateCaptions(session: session) }
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        presets
                        InspectorSection("Text") {
                            Picker("Font", selection: styleBinding("Caption Font", \.text.fontName, fallback: TextStyle.tiktokSans)) {
                                ForEach(TextInspector.fonts, id: \.self) { Text($0).tag($0) }
                            }
                            Picker("Weight", selection: styleBinding("Caption Weight", \.text.weight, fallback: .black)) {
                                ForEach(FontWeight.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                            Picker("Case", selection: styleBinding("Caption Case", \.text.textCase, fallback: .uppercase)) {
                                ForEach(TextCase.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                            LabeledSlider(label: "Size", value: styleBinding("Caption Size", \.text.fontSize, fallback: 80), range: 30...160, format: "%.0f")
                            LabeledSlider(label: "Spacing", value: styleBinding("Letter Spacing", \.text.letterSpacing, fallback: 0), range: -5...20, format: "%.1f")
                            LabeledSlider(label: "Line height", value: styleBinding("Line Height", \.text.lineHeight, fallback: 1.1), range: 0.8...1.8)
                            ColorRow(label: "Text color", color: styleBinding("Caption Color", \.text.color, fallback: .white))
                        }
                        InspectorSection("Outline & Shadow") {
                            ColorRow(label: "Outline", color: styleBinding("Outline Color", \.text.strokeColor, fallback: .black))
                            LabeledSlider(label: "Thickness", value: styleBinding("Outline", \.text.strokeWidth, fallback: 8), range: 0...20, format: "%.0f")
                            ColorRow(label: "Shadow", color: styleBinding("Shadow Color", \.text.shadowColor, fallback: .black))
                            LabeledSlider(label: "Opacity", value: styleBinding("Shadow Opacity", \.text.shadowOpacity, fallback: 0.5), range: 0...1)
                            LabeledSlider(label: "Blur", value: styleBinding("Shadow Blur", \.text.shadowRadius, fallback: 6), range: 0...30, format: "%.0f")
                            ColorRow(label: "Background", color: styleBinding("Caption Background", \.text.backgroundColor, fallback: .black))
                            LabeledSlider(label: "Bg opacity", value: styleBinding("Background Opacity", \.text.backgroundOpacity, fallback: 0), range: 0...1)
                        }
                        InspectorSection("Highlight & Animation") {
                            Picker("Mode", selection: styleBinding("Display Mode", \.displayMode, fallback: .phrase)) {
                                ForEach(CaptionDisplayMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            HStack(spacing: 5) {
                                ForEach(HighlightPreset.all) { preset in
                                    let on = captions.map { preset.matches($0.style) } ?? false
                                    Button(preset.name) { applyHighlight(preset) }
                                        .buttonStyle(.pulse(on ? .primary : .secondary, compact: true))
                                }
                            }
                            Picker("Speaker", selection: styleBinding("Speaker Label", \.speakerLabelStyle, fallback: .text)) {
                                ForEach(SpeakerLabelStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .help("Speaker names above the words: plain small caps or a lower-third chip (#252)")
                            Picker("Box", selection: styleBinding("Caption Background", \.backgroundStyle, fallback: .solid)) {
                                ForEach(CaptionBackgroundStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .help("Frosted blurs the picture behind the words instead of a solid box (#253)")
                            Picker("Highlight", selection: styleBinding("Highlight Mode", \.highlightMode, fallback: .color)) {
                                ForEach(WordHighlightMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                            ColorRow(label: "Highlight", color: styleBinding("Highlight Color", \.highlightColor, fallback: .yellow))
                            ColorRow(label: "Highlight box", color: styleBinding("Highlight Box", \.highlightBoxColor, fallback: .pulse))
                            Picker("Animation", selection: styleBinding("Caption Animation", \.animation, fallback: .pop)) {
                                ForEach(CaptionAnimation.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                            LabeledSlider(label: "Speed", value: styleBinding("Animation Speed", \.animationSpeed, fallback: 1), range: 0.3...3, unit: "×")
                            Stepper("Words per page: \(captions?.style.maxWordsPerPage ?? 3)", value: styleBinding("Words per Page", \.maxWordsPerPage, fallback: 3), in: 1...12)
                                .font(.pulseCaption)
                            Stepper("Max lines: \(captions?.style.maxLines ?? 2)", value: styleBinding("Max Lines", \.maxLines, fallback: 2), in: 1...4)
                                .font(.pulseCaption)
                        }
                        InspectorSection("Emphasis", isAI: true) {
                            ColorRow(label: "Emphasis color", color: styleBinding("Emphasis Color", \.emphasisColor, fallback: .yellow))
                            LabeledSlider(label: "Emphasis size", value: styleBinding("Emphasis Scale", \.emphasisScale, fallback: 1.12), range: 1...1.6, unit: "×")
                            HStack {
                                Button("AI Emphasis") { session.editTimeline("AI Emphasis") { $0.captions?.applyAIEmphasis() } }
                                    .buttonStyle(.pulse(.ai, compact: true))
                                Button("Clear AI Emphasis") { session.editTimeline("Clear AI Emphasis") { $0.captions?.resetAIEmphasis() } }
                                    .buttonStyle(.pulse(.ghost, compact: true))
                            }
                            Text("Click a word below to emphasise it yourself.").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                        }
                        if let captions, captions.captionSpeakers.count >= 2 {
                            SpeakerCaptionSection(session: session, captions: captions)
                        }
                        InspectorSection("Timing & text") {
                            HStack(spacing: 6) {
                                Text("Timing").font(.pulseCaption).foregroundStyle(Theme.textSecondary).frame(width: 74, alignment: .leading)
                                Button("−50 ms") { shiftCaptions(by: -0.05) }.buttonStyle(.pulse(.secondary, compact: true))
                                Button("+50 ms") { shiftCaptions(by: 0.05) }.buttonStyle(.pulse(.secondary, compact: true))
                                Text("when the captions run early or late").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                            }
                            HStack(spacing: 6) {
                                Text("After playhead").font(.pulseCaption).foregroundStyle(Theme.textSecondary).frame(width: 74, alignment: .leading)
                                Button("−200 ms") { shiftCaptionsAfterPlayhead(by: -0.2) }.buttonStyle(.pulse(.secondary, compact: true))
                                Button("+200 ms") { shiftCaptionsAfterPlayhead(by: 0.2) }.buttonStyle(.pulse(.secondary, compact: true))
                                Text("only the words from here on — after a re-cut").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                            }
                            HStack(spacing: 6) {
                                Text("Position").font(.pulseCaption).foregroundStyle(Theme.textSecondary).frame(width: 74, alignment: .leading)
                                ForEach(SafeAreaPlatform.allCases, id: \.self) { platform in
                                    let on = captions.map { abs($0.style.positionY - platform.captionCenterY) < 0.005 } ?? false
                                    Button(platform.displayName) { positionCaptions(for: platform) }.buttonStyle(.pulse(on ? .primary : .secondary, compact: true))
                                }
                            }
                            .help("Puts the captions just above the zone the platform's own buttons and caption cover")
                            HStack(spacing: 6) {
                                Text("Text").font(.pulseCaption).foregroundStyle(Theme.textSecondary).frame(width: 74, alignment: .leading)
                                Button("Sentence case") { sentenceCase() }.buttonStyle(.pulse(.secondary, compact: true))
                                    .help("First word of each sentence capitalised, shouting lowered; I, GG and the like stay")
                                Button("Remove um / uh") { stripFillers() }.buttonStyle(.pulse(.secondary, compact: true))
                                    .help("Takes filler-only words out of the captions; the audio is untouched")
                                Button("Rebuild") { session.rebuildCaptionsKeepingFixes() }.buttonStyle(.pulse(.secondary, compact: true))
                                    .help("Captions again from the latest transcript — words you retyped, hid or emphasised stay as you left them")
                                Button("Spelling") { showSpelling = true }.buttonStyle(.pulse(.secondary, compact: true))
                                    .help("Words the dictionary doesn't know, with fixes; names and game words you teach it are skipped (#242)")
                                    .popover(isPresented: $showSpelling, arrowEdge: .bottom) { CaptionSpellingPopover(session: session).environmentObject(app) }
                                Button("Import…") { session.importCaptionsFile() }.buttonStyle(.pulse(.secondary, compact: true))
                                    .help("An SRT or VTT for the main recording becomes this timeline's captions, re-timed to the cut (#247)")
                            }
                            HStack(spacing: 6) {
                                TextField("Find", text: $findText).textFieldStyle(.roundedBorder).frame(width: 88)
                                TextField("Replace", text: $replaceText).textFieldStyle(.roundedBorder).frame(width: 88)
                                Button("Replace All") { replaceAllInCaptions() }.buttonStyle(.pulse(.secondary, compact: true)).disabled(findText.isEmpty)
                            }
                            HStack(spacing: 6) {
                                Text("Shadow").font(.pulseCaption).foregroundStyle(Theme.textSecondary).frame(width: 74, alignment: .leading)
                                ForEach(CaptionStyle.ShadowPreset.allCases, id: \.self) { preset in
                                    let on = captions.map { preset.matches($0.style) } ?? false
                                    Button(preset.displayName) { applyShadow(preset) }.buttonStyle(.pulse(on ? .primary : .secondary, compact: true))
                                }
                            }
                            HStack(spacing: 6) {
                                Button { addLaughEmoji() } label: { Label("Laugh emoji", systemImage: "face.smiling") }
                                    .buttonStyle(.pulse(.secondary, compact: true))
                                    .help("Adds 😂 to hahaha, lol, lmao… once")
                                Button { session.applyCaptionStyleToAllShorts() } label: { Label("Style to all shorts", systemImage: "square.on.square") }
                                    .buttonStyle(.pulse(.secondary, compact: true))
                                    .help("Every other short with captions takes this look; split layouts keep their caption height")
                            }
                        }
                        InspectorSection("Swear words") {
                            Picker("Audio", selection: Binding(get: { audioCensor }, set: { setAudioCensor($0) })) {
                                ForEach(CensorAudio.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            Text(audioCensorNote).font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                        }
                        InspectorSection("Position") {
                            LabeledSlider(label: "Vertical", value: styleBinding("Caption Position", \.positionY, fallback: 0.7), range: 0.05...0.95)
                            LabeledSlider(label: "Horizontal", value: styleBinding("Caption Position X", \.positionX, fallback: 0.5), range: 0.1...0.9)
                            Picker("Keep clear of", selection: styleBinding("Safe Area", \.safeArea, fallback: .tiktok)) {
                                Text("Nothing").tag(SafeAreaPlatform?.none)
                                ForEach(SafeAreaPlatform.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                            }
                            Picker("Profanity", selection: Binding(get: { captions?.profanity ?? .off }, set: { v in session.editTimeline("Profanity") { $0.captions?.profanity = v } })) {
                                ForEach(ProfanityMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                        }
                        InspectorSection("Export", expanded: false) {
                            Button("Export SRT…") { exportSRT() }.buttonStyle(.pulse(.secondary, compact: true))
                            Button("Remove Captions", role: .destructive) { session.editTimeline("Remove Captions") { $0.captions = nil } }
                                .buttonStyle(.pulse(.ghost, compact: true))
                        }
                    }
                }
            }
        }
        .background(Theme.panel)
    }

    var presets: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Presets")
            presetGrid
                .onHover { galleryHovering = $0 }
                .help("Rest the mouse here and every preset plays its highlight (#233)")
        }
        .padding(12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    var presetGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]
        let currentName = captions?.style.presetName
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(CaptionStyle.presets, id: \.presetName) { preset in
                Button { applyPreset(preset) } label: {
                    CaptionPresetSwatch(style: preset, selected: currentName == preset.presetName, animated: galleryHovering)
                }
                .buttonStyle(.plain)
            }
        }
    }

    func applyPreset(_ preset: CaptionStyle) {
        session.editTimeline("Caption Preset: \(preset.presetName)") { t in
            let y = t.captions?.style.positionY ?? preset.positionY
            let keepY = t.layout == .splitScreen || t.layout == .dynamic
            t.captions?.style = preset
            if keepY { t.captions?.style.positionY = y }
        }
    }

    func exportSRT() {
        guard let timeline = session.activeTimeline, let captions = timeline.captions else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ExportSettings.sanitize(timeline.name) + ".srt"
        if panel.runModal() == .OK, let url = panel.url {
            try? CaptionLayoutEngine.srt(track: captions, timeline: timeline).write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

/// Mini preview of a caption preset.
struct CaptionPresetSwatch: View {
    let style: CaptionStyle
    let selected: Bool
    /// Plays the highlight through the words (#233) — on while the mouse is over the gallery.
    var animated = false

    /// The preset's own typeface, small.
    var swatchFont: Font {
        let name = style.text.fontName
        if name == TextStyle.tiktokSans || name == "Impact" { return .custom(name, size: 13).weight(fontWeight) }
        return .system(size: 13, weight: fontWeight, design: name.contains("Rounded") ? .rounded : (name == "New York" ? .serif : .default))
    }

    static let words = ["so", "good", "right"]

    var body: some View {
        TimelineView(.periodic(from: .now, by: animated ? 0.45 : 3600)) { context in
            let active = animated ? Int(context.date.timeIntervalSinceReferenceDate / 0.45) % Self.words.count : 1
            swatch(active: active)
        }
    }

    func swatch(active: Int) -> some View {
        VStack(spacing: 4) {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x2A2F45), Color(hex: 0x151722)], startPoint: .top, endPoint: .bottom)
                HStack(spacing: 3) {
                    ForEach(Array(Self.words.enumerated()), id: \.offset) { index, word in
                        let on = index == active && style.highlightMode != .none
                        let scaled = on && (style.highlightMode == .scale || style.highlightMode == .colorAndScale)
                        Text(style.text.textCase.apply(word))
                            .foregroundStyle(Color(on && style.highlightMode != .scale ? style.highlightColor : style.text.color))
                            .padding(.horizontal, style.highlightMode == .box ? 3 : 0)
                            .background(RoundedRectangle(cornerRadius: 2).fill(on && style.highlightMode == .box ? Color(style.highlightBoxColor) : .clear))
                            .scaleEffect(scaled ? 1.18 : 1)
                            .animation(animated ? Theme.motion(.spring(response: 0.25, dampingFraction: 0.6)) : nil, value: active)
                    }
                }
                .font(swatchFont)
                .italic(style.text.italic)
                .shadow(color: .black.opacity(style.text.strokeWidth > 0 ? 0.9 : style.text.shadowOpacity), radius: style.text.strokeWidth > 0 ? 0.8 : 2)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color(style.text.backgroundColor).opacity(style.text.backgroundOpacity)))
            }
            .frame(height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? Theme.accent : Theme.border, lineWidth: selected ? 2 : 1))
            Text(style.presetName).font(.system(size: 10, weight: .medium)).foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
        }
    }

    var fontWeight: Font.Weight {
        switch style.text.weight {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }
}

/// Page-by-page caption word editor: click to select, double-click to edit text,
/// toggle emphasis, hide words, jump the playhead.
struct CaptionWordEditor: View {
    @ObservedObject var session: ProjectSession
    @ObservedObject var playback: PlaybackController
    @State private var editingID: UUID?
    @State private var editingText = ""

    init(session: ProjectSession) {
        self.session = session
        self.playback = session.playback
    }

    var body: some View { ClockObserving(clock: playback.slowClock) { clockedBody } }

    @ViewBuilder var clockedBody: some View {
        VStack(spacing: 0) {
            PanelHeader("Caption Text", subtitle: "Double-click edits · tab next word · return breaks the page · ⌫ merges · ★ emphasise") {
                if let word = selectedWord {
                    HStack(spacing: 4) {
                        Button { session.learnEmphasis(word); session.editTimeline("Toggle Emphasis") { $0.captions?.toggleEmphasis(id: word.id) } } label: {
                            Image(systemName: word.isEmphasized ? "star.fill" : "star")
                        }
                        .buttonStyle(.pulse(.ghost, compact: true))
                        Button {
                            session.editTimeline(word.isHidden ? "Show Word" : "Hide Word") { t in
                                if let i = t.captions?.words.firstIndex(where: { $0.id == word.id }) { t.captions?.words[i].isHidden.toggle() }
                            }
                        } label: { Image(systemName: word.isHidden ? "eye" : "eye.slash") }
                            .buttonStyle(.pulse(.ghost, compact: true))
                    }
                }
            }
            if let timeline = session.activeTimeline, let captions = timeline.captions {
                let words = CaptionLayoutEngine.timelineWords(captions, in: timeline)
                let pages = CaptionLayoutEngine.pages(words, style: captions.style)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(pages, id: \.index) { page in
                            HStack(alignment: .top, spacing: 10) {
                                Text(Timecode.short(page.range.start)).font(.pulseMono).foregroundStyle(Theme.textTertiary).frame(width: 44, alignment: .leading)
                                FlowLayout(spacing: 5) {
                                    ForEach(page.words, id: \.id) { w in
                                        wordChip(w, captions: captions, active: page.range.contains(playback.currentTime) && w.start <= playback.currentTime && playback.currentTime < w.end + 0.2)
                                    }
                                }
                            }
                        }
                        let hidden = captions.words.filter(\.isHidden)
                        if !hidden.isEmpty {
                            HStack(spacing: 6) {
                                Text("\(hidden.count) hidden").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                                Button("Show all") { session.editTimeline("Show Hidden Words") { t in
                                    guard let words = t.captions?.words else { return }
                                    for i in words.indices { t.captions?.words[i].isHidden = false }
                                } }
                                .buttonStyle(.pulse(.ghost, compact: true))
                            }
                        }
                    }
                    .padding(10)
                }
                .focusable()
                .onKeyPress(phases: .down, action: handleKey)
            }
        }
        .background(Theme.panel)
    }

    /// Keyboard editing (#256): tab / ⇧tab move between words, return starts a new caption page after the
    /// word (again to undo), ⌫ merges the word into the one before it, space seeks to it.
    func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard editingID == nil, let captions = session.activeTimeline?.captions else { return .ignored }
        guard let id = session.focusedCaptionWordID else {
            if press.key == .tab, let first = captions.words.first(where: { !$0.isHidden }) { session.focusedCaptionWordID = first.id; return .handled }
            return .ignored
        }
        switch press.key {
        case .tab:
            let step = press.modifiers.contains(.shift) ? -1 : 1
            if let next = captions.neighborWord(of: id, step: step) {
                session.focusedCaptionWordID = next.id
                playback.seek(to: CaptionLayoutEngine.timelineWords(captions, in: session.activeTimeline!).first { $0.id == next.id }?.start ?? playback.currentTime)
            }
            return .handled
        case .return:
            session.editTimeline("Caption Page Break") { $0.captions?.toggleBreak(afterID: id) }
            return .handled
        case .delete:
            var merged: UUID?
            session.editTimeline("Merge Caption Words") { merged = $0.captions?.mergeIntoPrevious(id: id) }
            if let merged { session.focusedCaptionWordID = merged }
            return .handled
        case .space:
            if let word = CaptionLayoutEngine.timelineWords(captions, in: session.activeTimeline!).first(where: { $0.id == id }) { playback.seek(to: word.start) }
            return .handled
        default:
            return .ignored
        }
    }

    var selectedWord: CaptionWord? {
        guard let id = session.focusedCaptionWordID else { return nil }
        return session.activeTimeline?.captions?.words.first { $0.id == id }
    }

    @ViewBuilder
    func wordChip(_ w: TimedCaptionWord, captions: CaptionTrack, active: Bool) -> some View {
        let source = captions.words.first { $0.id == w.id }
        if editingID == w.id {
            TextField("", text: $editingText, onCommit: {
                let id = w.id
                let text = editingText
                session.editTimeline("Edit Caption") { $0.captions?.setWordText(id: id, text: text) }
                editingID = nil
            })
            .textFieldStyle(.roundedBorder)
            .frame(width: max(60, CGFloat(editingText.count) * 9))
        } else {
            Text(w.text)
                .font(.system(size: 12, weight: w.isEmphasized ? .bold : .medium))
                .foregroundStyle(active ? Theme.accent : (w.isEmphasized ? Theme.warning : Theme.textPrimary))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(session.focusedCaptionWordID == w.id ? Theme.info.opacity(0.35) : Theme.control))
                .overlay(alignment: .topTrailing) {
                    if source?.emphasisIsAI == true { Circle().fill(Theme.ai).frame(width: 4, height: 4).offset(x: 1, y: -1) }
                }
                .overlay(alignment: .trailing) {
                    if source?.pageBreakAfter == true { Image(systemName: "return").font(.system(size: 7, weight: .bold)).foregroundStyle(Theme.info).offset(x: 9) }
                }
                .onTapGesture(count: 2) {
                    editingText = source?.text ?? w.text
                    editingID = w.id
                    // Hear the word you're retyping (#257).
                    playback.seek(to: w.start)
                    playback.play()
                    let length = max(0.3, w.end - w.start + 0.15)
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(length))
                        if playback.isPlaying { playback.pause() }
                    }
                }
                .onTapGesture {
                    session.focusedCaptionWordID = w.id
                    playback.seek(to: w.start)
                }
        }
    }
}

/// Per-speaker caption looks: color by speaker, name labels, and each speaker's color and position.
struct SpeakerCaptionSection: View {
    @ObservedObject var session: ProjectSession
    let captions: CaptionTrack

    func suggestNames() {
        let words = session.analyses[captions.sourceAssetID]?.transcript?.words ?? []
        let names = SpeakerNameSuggester.suggest(words: words)
        guard !names.isEmpty else { session.app.toast("No introductions found (“this is Mark”, “joined by Sarah”…)"); return }
        session.editTimeline("Suggest Speaker Names") { t in
            for (id, name) in names where (t.captions?.speakerNames[id] ?? "").isEmpty { t.captions?.speakerNames[id] = name }
        }
        session.app.toast("Named " + names.sorted { $0.key < $1.key }.map { $0.value }.joined(separator: ", "))
    }

    func override(_ id: Int, _ label: String, _ change: @escaping (inout SpeakerCaptionStyle) -> Void) {
        session.editTimeline(label, coalesce: "speaker-\(id)-\(label)") { t in
            var s = t.captions?.speakerStyles[id] ?? SpeakerCaptionStyle()
            change(&s)
            t.captions?.speakerStyles[id] = s.isEmpty ? nil : s
        }
    }

    var body: some View {
        InspectorSection("Speakers") {
            ToggleRow(label: "Color by speaker", isOn: Binding(get: { captions.isColoredBySpeaker }, set: { on in
                session.editTimeline(on ? "Color Captions by Speaker" : "Same Color for All Speakers") { t in
                    if on { t.captions?.colorBySpeaker() } else { t.captions?.clearSpeakerColors() }
                }
            }), help: "Each voice gets its own caption color so viewers can follow the conversation")
            ToggleRow(label: "Show speaker names", isOn: Binding(get: { captions.showSpeakerLabels }, set: { on in
                session.editTimeline("Speaker Names") { $0.captions?.showSpeakerLabels = on }
            }), help: "A small name tag above each caption (rename speakers in the transcript)")
            Button { suggestNames() } label: { Label("Suggest names from the conversation", systemImage: "person.text.rectangle") }
                .buttonStyle(.pulse(.secondary, compact: true))
                .help("“This is Mark”, “joined by Sarah” — the next voice gets the name; a suggestion you can change")
            ForEach(captions.captionSpeakers, id: \.self) { id in
                let style = captions.style(forSpeaker: id)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle().fill(Color(style.text.color)).frame(width: 8, height: 8)
                        Text(captions.speakerName(id)).font(.pulseCaption.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if captions.speakerStyles[id] != nil {
                            Button("Reset") { session.editTimeline("Reset Speaker Style") { $0.captions?.speakerStyles[id] = nil } }
                                .buttonStyle(.plain).font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    ColorRow(label: "Text", color: Binding(get: { style.text.color }, set: { c in override(id, "Speaker Color") { $0.textColor = c } }))
                    ColorRow(label: "Highlight", color: Binding(get: { style.highlightColor }, set: { c in override(id, "Speaker Highlight") { $0.highlightColor = c } }))
                    LabeledSlider(label: "Vertical", value: Binding(get: { style.positionY }, set: { y in override(id, "Speaker Position") { $0.positionY = y } }),
                                  range: 0.05...0.95, onEditingChanged: { editing in if !editing { session.commitCoalescing() } })
                }
                .padding(.vertical, 4)
            }
            Text("Tip: in a split screen, put each person's captions next to their camera.")
                .font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Caption words the system dictionary doesn't know (#242): click a word to go there, a suggestion to use
/// it, or Learn to add it to your vocabulary so it's never flagged again.
struct CaptionSpellingPopover: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession

    struct Finding: Identifiable {
        let id: UUID
        let word: CaptionWord
        let guesses: [String]
    }

    @State private var findings: [Finding] = []
    @State private var checked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelHeader("Spelling", subtitle: checked ? (findings.isEmpty ? "Nothing the dictionary doesn't know" : "\(findings.count) word\(findings.count == 1 ? "" : "s") to look at") : "Checking…")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(findings) { finding in row(finding) }
                }
            }
        }
        .padding(12)
        .frame(width: 380, height: 320)
        .onAppear(perform: check)
    }

    func row(_ finding: Finding) -> some View {
        HStack(spacing: 6) {
            Button(finding.word.text) { go(to: finding.word) }
                .buttonStyle(.pulse(.ghost, compact: true))
                .help("Go to this word")
            ForEach(finding.guesses, id: \.self) { guess in
                Button(guess) { replace(finding, with: guess) }.buttonStyle(.pulse(.secondary, compact: true))
            }
            Spacer()
            Button("Learn") { learn(finding) }.buttonStyle(.pulse(.ghost, compact: true)).help("Add to your vocabulary")
        }
    }

    func check() {
        guard let timeline = session.activeTimeline, let captions = timeline.captions else { checked = true; return }
        let known = app.settings.ai.customVocabulary + Array(captions.speakerNames.values)
        let checker = NSSpellChecker.shared
        var out: [Finding] = []
        for word in CaptionSpelling.checkable(captions.words, known: known) {
            let text = word.text.trimmingCharacters(in: .punctuationCharacters)
            let range = checker.checkSpelling(of: text, startingAt: 0)
            guard range.location != NSNotFound else { continue }
            let guesses = checker.guesses(forWordRange: NSRange(location: 0, length: (text as NSString).length), in: text, language: nil, inSpellDocumentWithTag: 0) ?? []
            out.append(Finding(id: word.id, word: word, guesses: Array(guesses.prefix(3))))
            if out.count >= 80 { break }
        }
        findings = out
        checked = true
    }

    func go(to word: CaptionWord) {
        session.focusedCaptionWordID = word.id
        if let timeline = session.activeTimeline, let captions = timeline.captions,
           let placed = CaptionLayoutEngine.timelineWords(captions, in: timeline).first(where: { $0.id == word.id }) {
            session.playback.seek(to: placed.start)
        }
    }

    func replace(_ finding: Finding, with guess: String) {
        let core = finding.word.text.trimmingCharacters(in: .punctuationCharacters)
        var text = guess
        if let range = finding.word.text.range(of: core) { text = finding.word.text.replacingCharacters(in: range, with: guess) }
        let id = finding.id
        session.editTimeline("Fix Spelling") { $0.captions?.setWordText(id: id, text: text) }
        findings.removeAll { $0.id == finding.id }
    }

    func learn(_ finding: Finding) {
        let word = finding.word.text.trimmingCharacters(in: .punctuationCharacters)
        if !app.settings.ai.customVocabulary.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) {
            app.settings.ai.customVocabulary.append(word)
        }
        findings.removeAll { CaptionSpelling.normalize($0.word.text) == CaptionSpelling.normalize(word) }
    }
}
