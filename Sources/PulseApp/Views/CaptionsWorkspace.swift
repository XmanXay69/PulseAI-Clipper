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
    @ObservedObject var session: ProjectSession

    var captions: CaptionTrack? { session.activeTimeline?.captions }

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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                ForEach(CaptionStyle.presets, id: \.presetName) { preset in
                    Button {
                        session.editTimeline("Caption Preset: \(preset.presetName)") { t in
                            let y = t.captions?.style.positionY ?? preset.positionY
                            let keepY = t.layout == .splitScreen || t.layout == .dynamic
                            t.captions?.style = preset
                            if keepY { t.captions?.style.positionY = y }
                        }
                    } label: {
                        CaptionPresetSwatch(style: preset, selected: captions?.style.presetName == preset.presetName)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
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

    /// The preset's own typeface, small.
    var swatchFont: Font {
        let name = style.text.fontName
        if name == TextStyle.tiktokSans || name == "Impact" { return .custom(name, size: 13).weight(fontWeight) }
        return .system(size: 13, weight: fontWeight, design: name.contains("Rounded") ? .rounded : (name == "New York" ? .serif : .default))
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x2A2F45), Color(hex: 0x151722)], startPoint: .top, endPoint: .bottom)
                HStack(spacing: 3) {
                    Text(style.text.textCase.apply("so"))
                        .foregroundStyle(Color(style.text.color))
                    Text(style.text.textCase.apply("good"))
                        .foregroundStyle(Color(style.highlightMode == .none ? style.text.color : style.highlightColor))
                        .padding(.horizontal, style.highlightMode == .box ? 3 : 0)
                        .background(RoundedRectangle(cornerRadius: 2).fill(style.highlightMode == .box ? Color(style.highlightBoxColor) : .clear))
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

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader("Caption Text", subtitle: "Double-click a word to edit · ★ emphasise · eye hides") {
                if let word = selectedWord {
                    HStack(spacing: 4) {
                        Button { session.editTimeline("Toggle Emphasis") { $0.captions?.toggleEmphasis(id: word.id) } } label: {
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
            }
        }
        .background(Theme.panel)
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
                .onTapGesture(count: 2) {
                    editingText = source?.text ?? w.text
                    editingID = w.id
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
