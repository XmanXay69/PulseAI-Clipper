import AppKit
import PulseCore
import PulseEngine
import SwiftUI
import UniformTypeIdentifiers

struct InspectorView: View {
    @ObservedObject var session: ProjectSession
    @ObservedObject var playback: PlaybackController

    init(session: ProjectSession) {
        self.session = session
        self.playback = session.playback
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader("Inspector", subtitle: subtitle)
            ScrollView {
                VStack(spacing: 0) {
                    if let timeline = session.activeTimeline {
                        let clips = session.selectedClips
                        if clips.count == 1, let clip = clips.first, let track = timeline.track(containingClip: clip.id) {
                            ClipInspector(session: session, playback: playback, clip: clip, track: track)
                        } else if clips.count > 1 {
                            MultiSelectionInspector(session: session, count: clips.count)
                        } else {
                            TimelineInspector(session: session, timeline: timeline)
                        }
                    }
                }
            }
        }
        .background(Theme.panel)
    }

    var subtitle: String {
        let clips = session.selectedClips
        if clips.count == 1 { return clips[0].name }
        if clips.count > 1 { return "\(clips.count) clips" }
        return session.activeTimeline?.name ?? ""
    }
}

/// Bindings that route through the undoable edit pipeline.
@MainActor
struct ClipBindings {
    let session: ProjectSession
    let clipID: UUID
    let local: Seconds

    var clip: TimelineClip? { session.activeTimeline?.clip(id: clipID) }

    func value<T>(_ label: String, _ keyPath: WritableKeyPath<TimelineClip, T>, fallback: T) -> Binding<T> {
        Binding(get: { clip?[keyPath: keyPath] ?? fallback },
                set: { newValue in session.editClip(clipID, label) { $0[keyPath: keyPath] = newValue } })
    }

    func animated(_ label: String, _ keyPath: WritableKeyPath<TimelineClip, AnimatedDouble>) -> Binding<Double> {
        let t = local
        return Binding(get: { clip?[keyPath: keyPath].value(at: t) ?? 0 },
                       set: { v in
                           session.editClip(clipID, label) { c in
                               if c[keyPath: keyPath].isAnimated { c[keyPath: keyPath].setKeyframe(at: t, value: v) } else { c[keyPath: keyPath].value = v }
                           }
                       })
    }

    func hasKeyframe(_ keyPath: WritableKeyPath<TimelineClip, AnimatedDouble>) -> Bool {
        clip?[keyPath: keyPath].keyframes.contains { abs($0.time - local) < 1.0 / 60 } ?? false
    }

    func toggleKeyframe(_ label: String, _ keyPath: WritableKeyPath<TimelineClip, AnimatedDouble>) {
        let t = local
        session.editClip(clipID, "Keyframe \(label)", coalesce: nil) { c in
            if let k = c[keyPath: keyPath].keyframes.first(where: { abs($0.time - t) < 1.0 / 60 }) {
                c[keyPath: keyPath].removeKeyframe(id: k.id)
            } else {
                let current = c[keyPath: keyPath].value(at: t)
                c[keyPath: keyPath].setKeyframe(at: t, value: current)
            }
        }
    }

    /// Slider with keyframe diamond.
    func slider(_ label: String, _ keyPath: WritableKeyPath<TimelineClip, AnimatedDouble>, range: ClosedRange<Double>, format: String = "%.2f", unit: String = "") -> some View {
        LabeledSlider(label: label, value: animated(label, keyPath), range: range, format: format, unit: unit,
                      keyframed: hasKeyframe(keyPath), onKeyframe: { toggleKeyframe(label, keyPath) },
                      onEditingChanged: { editing in if !editing { session.commitCoalescing() } })
    }

    func plainSlider(_ label: String, _ keyPath: WritableKeyPath<TimelineClip, Double>, range: ClosedRange<Double>, format: String = "%.2f", unit: String = "") -> some View {
        LabeledSlider(label: label, value: value(label, keyPath, fallback: 0), range: range, format: format, unit: unit,
                      onEditingChanged: { editing in if !editing { session.commitCoalescing() } })
    }
}

struct ClipInspector: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    @ObservedObject var playback: PlaybackController
    let clip: TimelineClip
    let track: Track

    var b: ClipBindings { ClipBindings(session: session, clipID: clip.id, local: max(0, playback.currentTime - clip.start)) }

    var body: some View {
        VStack(spacing: 0) {
            InspectorSection("Clip", isAI: clip.aiGenerated) {
                HStack {
                    TextField("Name", text: b.value("Rename", \.name, fallback: clip.name)).textFieldStyle(.roundedBorder)
                    Toggle("On", isOn: b.value("Enable", \.isEnabled, fallback: true)).toggleStyle(.switch).controlSize(.mini).labelsHidden()
                }
                KeyValueRow(key: "Timeline", value: "\(Timecode.short(clip.start)) → \(Timecode.short(clip.end)) (\(String(format: "%.2fs", clip.duration)))")
                if clip.assetID != nil {
                    KeyValueRow(key: "Source", value: "\(Timecode.short(clip.sourceIn)) → \(Timecode.short(clip.sourceOut))")
                }
                if let role = clip.role { KeyValueRow(key: "Role", value: role.displayName) }
            }
            switch clip.content {
            case .text(let element):
                TextInspector(session: session, clip: clip, element: element, b: b)
                transformSection(showCrop: false)
            case .solid:
                transformSection(showCrop: false)
            case .media(let assetID):
                if track.kind == .audio {
                    AudioInspector(session: session, clip: clip, b: b)
                    speedSection
                } else {
                    transformSection(showCrop: true)
                    styleSection
                    speedSection
                    ColorInspector(session: session, clip: clip, b: b)
                    EffectsInspector(session: session, clip: clip)
                    transitionsSection
                    aiSection(assetID: assetID)
                }
            }
        }
    }

    func transformSection(showCrop: Bool) -> some View {
        Group {
            InspectorSection("Transform", trailing: AnyView(resetButton("Reset Transform") { c in
                let crop = c.transform.crop
                c.transform = VisualTransform(crop: crop, fit: c.transform.fit)
            })) {
                b.slider("Position X", \.transform.positionX, range: -0.5...1.5)
                b.slider("Position Y", \.transform.positionY, range: -0.5...1.5)
                b.slider("Scale", \.transform.scale, range: 0.05...4, unit: "×")
                b.slider("Rotation", \.transform.rotation, range: -180...180, format: "%.0f", unit: "°")
                b.slider("Opacity", \.transform.opacity, range: 0...1)
                if showCrop {
                    Picker("Fit", selection: b.value("Fit Mode", \.transform.fit, fallback: .fit)) {
                        ForEach(FitMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Toggle("Flip H", isOn: b.value("Flip", \.transform.flipHorizontal, fallback: false)).toggleStyle(.checkbox)
                        Toggle("Flip V", isOn: b.value("Flip", \.transform.flipVertical, fallback: false)).toggleStyle(.checkbox)
                    }
                    .font(.pulseCaption)
                }
            }
            if showCrop {
                InspectorSection("Crop & Zoom", isAI: clip.transform.zoom.hasAIKeyframes || clip.transform.panX.hasAIKeyframes,
                                 trailing: AnyView(resetButton("Reset Crop") { c in
                                     c.transform.crop = .full
                                     c.transform.zoom = AnimatedDouble(1)
                                     c.transform.panX = AnimatedDouble(0)
                                     c.transform.panY = AnimatedDouble(0)
                                 })) {
                    cropSlider("Crop X", \.x, range: 0...0.95)
                    cropSlider("Crop Y", \.y, range: 0...0.95)
                    cropSlider("Crop W", \.width, range: 0.05...1)
                    cropSlider("Crop H", \.height, range: 0.05...1)
                    Divider()
                    b.slider("Zoom", \.transform.zoom, range: 1...3, unit: "×")
                    b.slider("Pan X", \.transform.panX, range: -0.5...0.5)
                    b.slider("Pan Y", \.transform.panY, range: -0.5...0.5)
                    Text("Keyframe Zoom and Pan to animate camera moves and punch-ins (◆ adds a keyframe at the playhead).")
                        .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                    if clip.transform.zoom.hasAIKeyframes {
                        Button("Remove AI Punch-ins") { session.editClip(clip.id, "Remove AI Punch-ins") { $0.transform.zoom.removeAIKeyframes() } }
                            .buttonStyle(.pulse(.ghost, compact: true))
                    }
                }
            }
        }
    }

    func cropSlider(_ label: String, _ keyPath: WritableKeyPath<NormRect, Double>, range: ClosedRange<Double>) -> some View {
        let binding = Binding<Double>(
            get: { session.activeTimeline?.clip(id: clip.id)?.transform.crop[keyPath: keyPath] ?? 0 },
            set: { v in session.editClip(clip.id, "Crop") { c in
                var r = c.transform.crop
                r[keyPath: keyPath] = v
                c.transform.crop = r.clampedToUnit()
            } })
        return LabeledSlider(label: label, value: binding, range: range, onEditingChanged: { if !$0 { session.commitCoalescing() } })
    }

    var styleSection: some View {
        InspectorSection("Shape & Border", expanded: clip.role == .webcam) {
            Picker("Mask", selection: b.value("Mask", \.style.mask, fallback: .rectangle)) {
                ForEach(MaskShape.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            b.plainSlider("Corners", \.style.cornerRadius, range: 0...0.5)
            b.plainSlider("Border", \.style.borderWidth, range: 0...30, format: "%.0f", unit: "px")
            ColorRow(label: "Border color", color: b.value("Border Color", \.style.borderColor, fallback: .white))
            b.plainSlider("Shadow", \.style.shadowOpacity, range: 0...1)
            b.plainSlider("Softness", \.style.shadowRadius, range: 0...60, format: "%.0f")
        }
    }

    var speedSection: some View {
        InspectorSection("Speed", expanded: clip.speed != 1) {
            HStack(spacing: 4) {
                ForEach([0.25, 0.5, 0.75, 1, 1.25, 1.5, 2], id: \.self) { s in
                    Button(String(format: "%.2g×", s)) {
                        session.selectedClipIDs = [clip.id]
                        session.setSpeed(s)
                    }
                    .buttonStyle(.pulse(abs(clip.speed - s) < 0.001 ? .primary : .secondary, compact: true))
                }
            }
            Text("Changing speed keeps the clip's start and ripples later clips. Audio pitch is preserved.")
                .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
        }
    }

    var transitionsSection: some View {
        InspectorSection("Transitions", expanded: clip.transitionIn != nil || clip.transitionOut != nil) {
            transitionPicker("In", \.transitionIn)
            transitionPicker("Out", \.transitionOut)
        }
    }

    func transitionPicker(_ label: String, _ keyPath: WritableKeyPath<TimelineClip, ClipTransition?>) -> some View {
        let current = clip[keyPath: keyPath]
        return HStack {
            Text(label).font(.pulseCaption).foregroundStyle(Theme.textSecondary).frame(width: 30, alignment: .leading)
            Picker("", selection: Binding(get: { current?.kind ?? .cut }, set: { kind in
                session.editClip(clip.id, "Transition \(label)") { c in
                    c[keyPath: keyPath] = kind == .cut ? nil : ClipTransition(kind: kind, duration: c[keyPath: keyPath]?.duration ?? 0.4)
                }
            })) {
                ForEach(TransitionKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .labelsHidden()
            if let current {
                Stepper(String(format: "%.1fs", current.duration), value: Binding(get: { current.duration }, set: { d in
                    session.editClip(clip.id, "Transition Duration") { c in c[keyPath: keyPath]?.duration = max(0.1, min(d, 3)) }
                }), step: 0.1)
                .font(.pulseMono)
            }
        }
    }

    func aiSection(assetID: UUID) -> some View {
        InspectorSection("AI Framing", isAI: true, expanded: false) {
            Button { autoReframe(assetID: assetID) } label: { Label("Auto Reframe to Face", systemImage: "person.crop.rectangle") }
                .buttonStyle(.pulse(.secondary, compact: true))
            Button { session.editClip(clip.id, "Remove AI Keyframes") { $0.transform.removeAIKeyframes() } } label: { Label("Remove AI Keyframes", systemImage: "sparkles") }
                .buttonStyle(.pulse(.ghost, compact: true))
            Text("AI framing only adds normal keyframes — adjust or delete any of them.").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
        }
    }

    func autoReframe(assetID: UUID) {
        guard let faces = session.analyses[assetID]?.visual?.faces, !faces.isEmpty else {
            app.presentMessage(title: "No faces detected", message: "Analyze the recording first so PULSE knows where faces are.")
            return
        }
        session.editClip(clip.id, "Auto Reframe") { c in AutoReframer.applyFaceTracking(to: &c, faces: faces) }
    }

    func resetButton(_ label: String, _ body: @escaping (inout TimelineClip) -> Void) -> some View {
        Button { session.editClip(clip.id, label, body) } label: { Image(systemName: "arrow.counterclockwise") }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textTertiary)
            .help(label)
    }
}

struct TextInspector: View {
    @ObservedObject var session: ProjectSession
    let clip: TimelineClip
    let element: TextElement
    let b: ClipBindings

    static let fonts = ["SF Pro Display", "SF Pro Rounded", "New York", "Helvetica Neue", "Avenir Next", "Futura", "Impact", "Arial Black", "Georgia", "Menlo", "Marker Felt", "Chalkboard SE"]

    func textBinding<T>(_ label: String, _ keyPath: WritableKeyPath<TextElement, T>) -> Binding<T> {
        Binding(get: { (session.activeTimeline?.clip(id: clip.id)?.content.textElement ?? element)[keyPath: keyPath] },
                set: { v in
                    session.editClip(clip.id, label) { c in
                        guard case .text(var e) = c.content else { return }
                        e[keyPath: keyPath] = v
                        c.content = .text(e)
                    }
                })
    }

    var body: some View {
        InspectorSection("Text") {
            TextEditor(text: textBinding("Edit Text", \.text))
                .font(.system(size: 12))
                .frame(height: 64)
                .scrollContentBackground(.hidden)
                .background(RoundedRectangle(cornerRadius: 4).fill(Theme.well))
            Picker("Font", selection: textBinding("Font", \.style.fontName)) {
                ForEach(Self.fonts, id: \.self) { Text($0).tag($0) }
            }
            HStack {
                Picker("Weight", selection: textBinding("Weight", \.style.weight)) {
                    ForEach(FontWeight.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Toggle("Italic", isOn: textBinding("Italic", \.style.italic)).toggleStyle(.checkbox)
            }
            Picker("Case", selection: textBinding("Case", \.style.textCase)) {
                ForEach(TextCase.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            LabeledSlider(label: "Size", value: textBinding("Size", \.style.fontSize), range: 16...240, format: "%.0f", onEditingChanged: { if !$0 { session.commitCoalescing() } })
            LabeledSlider(label: "Spacing", value: textBinding("Letter Spacing", \.style.letterSpacing), range: -5...20, format: "%.1f")
            LabeledSlider(label: "Wrap width", value: textBinding("Wrap", \.maxWidth), range: 0.2...1)
            Picker("Align", selection: textBinding("Align", \.style.alignment)) {
                Image(systemName: "text.alignleft").tag(TextAlign.leading)
                Image(systemName: "text.aligncenter").tag(TextAlign.center)
                Image(systemName: "text.alignright").tag(TextAlign.trailing)
            }
            .pickerStyle(.segmented)
        }
        InspectorSection("Look") {
            ColorRow(label: "Color", color: textBinding("Text Color", \.style.color))
            ColorRow(label: "Stroke", color: textBinding("Stroke Color", \.style.strokeColor))
            LabeledSlider(label: "Stroke", value: textBinding("Stroke Width", \.style.strokeWidth), range: 0...20, format: "%.0f")
            ColorRow(label: "Shadow", color: textBinding("Shadow Color", \.style.shadowColor))
            LabeledSlider(label: "Shadow", value: textBinding("Shadow", \.style.shadowOpacity), range: 0...1)
            ColorRow(label: "Background", color: textBinding("Background", \.style.backgroundColor))
            LabeledSlider(label: "Bg opacity", value: textBinding("Background Opacity", \.style.backgroundOpacity), range: 0...1)
        }
        InspectorSection("Animation") {
            Picker("In", selection: textBinding("Animation In", \.animationIn)) {
                ForEach(TextAnimation.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Out", selection: textBinding("Animation Out", \.animationOut)) {
                ForEach(TextAnimation.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            LabeledSlider(label: "Duration", value: textBinding("Animation Duration", \.animationDuration), range: 0.1...2, unit: "s")
        }
    }
}

struct AudioInspector: View {
    @ObservedObject var session: ProjectSession
    let clip: TimelineClip
    let b: ClipBindings

    var body: some View {
        InspectorSection("Volume") {
            b.slider("Volume", \.audio.volume, range: 0...2, unit: "×")
            b.plainSlider("Gain", \.audio.gainDB, range: -24...24, format: "%.1f", unit: " dB")
            b.plainSlider("Pan", \.audio.pan, range: -1...1)
            b.plainSlider("Fade in", \.audio.fadeIn, range: 0...5, format: "%.1f", unit: "s")
            b.plainSlider("Fade out", \.audio.fadeOut, range: 0...5, format: "%.1f", unit: "s")
            ToggleRow(label: "Mute", isOn: b.value("Mute", \.audio.isMuted, fallback: false))
        }
        InspectorSection("Auto Ducking", isAI: true) {
            ToggleRow(label: "Lower under dialogue", isOn: b.value("Ducking", \.audio.duckUnderDialogue, fallback: false),
                      help: "Automatically lowers this clip (music, game audio) whenever someone speaks")
            b.plainSlider("Duck by", \.audio.duckAmountDB, range: -30...0, format: "%.0f", unit: " dB")
        }
        InspectorSection("Enhance", expanded: clip.audio.needsEnhanceRender) {
            HStack(spacing: 6) {
                Button { session.editClip(clip.id, "Voice Preset") { $0.audio.applyVoicePreset() } } label: { Label("Voice Preset", systemImage: "mic") }
                    .buttonStyle(.pulse(.secondary, compact: true))
                    .help("Rumble filter, presence, gentle compression, −14 LUFS loudness and a limiter")
                Spacer()
                ProcessingBadge(location: .local)
            }
            ToggleRow(label: "Voice enhancement", isOn: b.value("Voice Enhance", \.audio.voiceEnhance, fallback: false),
                      help: "80 Hz rumble filter, less mud, more presence and gentle compression")
            b.plainSlider("Noise reduction", \.audio.noiseReduction, range: 0...1)
            ToggleRow(label: "Normalize loudness (−14 LUFS)", isOn: b.value("Normalize", \.audio.normalize, fallback: false))
            ToggleRow(label: "Limiter (−1 dBFS)", isOn: b.value("Limiter", \.audio.limiter, fallback: false))
            ToggleRow(label: "Compressor", isOn: b.value("Compressor", \.audio.compressor.isEnabled, fallback: false))
            if clip.audio.compressor.isEnabled {
                b.plainSlider("Threshold", \.audio.compressor.thresholdDB, range: -50...0, format: "%.0f", unit: " dB")
                b.plainSlider("Ratio", \.audio.compressor.ratio, range: 1...12, format: "%.1f", unit: ":1")
                b.plainSlider("Makeup", \.audio.compressor.makeupGainDB, range: 0...18, format: "%.1f", unit: " dB")
            }
            ToggleRow(label: "EQ", isOn: b.value("EQ", \.audio.eq.isEnabled, fallback: false))
            if clip.audio.eq.isEnabled {
                b.plainSlider("Low (120 Hz)", \.audio.eq.lowGain, range: -12...12, format: "%.1f", unit: " dB")
                b.plainSlider("Mid (1.2 kHz)", \.audio.eq.midGain, range: -12...12, format: "%.1f", unit: " dB")
                b.plainSlider("High (8 kHz)", \.audio.eq.highGain, range: -12...12, format: "%.1f", unit: " dB")
                b.plainSlider("High-pass", \.audio.eq.highPassHz, range: 0...400, format: "%.0f", unit: " Hz")
            }
            Text("Rendered on this Mac into a cached copy of the clip's audio — the original file is never changed.")
                .font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ColorInspector: View {
    @ObservedObject var session: ProjectSession
    let clip: TimelineClip
    let b: ClipBindings

    var body: some View {
        InspectorSection("Color", expanded: !clip.color.isIdentity, trailing: AnyView(
            Button { session.editClip(clip.id, "Reset Color") { $0.color = .neutral } } label: { Image(systemName: "arrow.counterclockwise") }
                .buttonStyle(.plain).foregroundStyle(Theme.textTertiary).help("Reset color")
        )) {
            b.plainSlider("Exposure", \.color.exposure, range: -2...2, unit: " EV")
            b.plainSlider("Contrast", \.color.contrast, range: -1...1)
            b.plainSlider("Highlights", \.color.highlights, range: -1...0)
            b.plainSlider("Shadows", \.color.shadows, range: -1...1)
            b.plainSlider("Saturation", \.color.saturation, range: -1...1)
            b.plainSlider("Temperature", \.color.temperature, range: -1...1)
            b.plainSlider("Tint", \.color.tint, range: -1...1)
            b.plainSlider("Sharpness", \.color.sharpness, range: 0...1)
            b.plainSlider("Vignette", \.color.vignette, range: 0...1)
            HStack {
                Text(clip.color.lutPath.map { ($0 as NSString).lastPathComponent } ?? "No LUT").font(.pulseCaption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                Spacer()
                Button("Load LUT…") { pickLUT() }.buttonStyle(.pulse(.secondary, compact: true))
                if clip.color.lutPath != nil {
                    Button("Clear") { session.editClip(clip.id, "Clear LUT") { $0.color.lutPath = nil } }.buttonStyle(.pulse(.ghost, compact: true))
                }
            }
            if clip.color.lutPath != nil {
                b.plainSlider("LUT amount", \.color.lutIntensity, range: 0...1)
            }
        }
    }

    func pickLUT() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "cube") ?? .data]
        panel.message = "Choose a .cube 3D LUT"
        if panel.runModal() == .OK, let url = panel.url {
            session.editClip(clip.id, "Apply LUT") { $0.color.lutPath = url.path }
        }
    }
}

struct EffectsInspector: View {
    @ObservedObject var session: ProjectSession
    let clip: TimelineClip

    var body: some View {
        InspectorSection("Effects", expanded: !clip.effects.isEmpty, trailing: AnyView(
            Menu {
                ForEach(EffectKind.allCases, id: \.self) { kind in
                    Button { add(kind) } label: { Label(kind.displayName, systemImage: kind.symbolName) }
                }
            } label: { Image(systemName: "plus") }
                .menuStyle(.borderlessButton).frame(width: 24)
        )) {
            if clip.effects.isEmpty {
                Text("No effects. Add blur, glow, shake, zoom pulse and more — all non-destructive.").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            }
            ForEach(clip.effects) { effect in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: effect.kind.symbolName).foregroundStyle(Theme.textSecondary)
                        Text(effect.kind.displayName).font(.pulseCaption).foregroundStyle(Theme.textPrimary)
                        if effect.aiGenerated { AIBadge() }
                        Spacer()
                        Toggle("", isOn: Binding(get: { effect.isEnabled }, set: { on in update(effect.id) { $0.isEnabled = on } }))
                            .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                        Button { session.editClip(clip.id, "Remove Effect") { c in c.effects.removeAll { $0.id == effect.id } } } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).foregroundStyle(Theme.textTertiary)
                    }
                    ForEach(effect.parameters.keys.sorted(), id: \.self) { name in
                        LabeledSlider(label: name.capitalized, value: Binding(get: { effect.parameters[name]?.value ?? 0 }, set: { v in
                            update(effect.id) { $0.parameters[name] = AnimatedDouble(v) }
                        }), range: range(for: name), format: "%.2f", onEditingChanged: { if !$0 { session.commitCoalescing() } })
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 4).fill(Theme.well))
            }
        }
    }

    func range(for parameter: String) -> ClosedRange<Double> {
        switch parameter {
        case "radius": return 0...60
        case "amplitude": return 0...60
        case "frequency": return 0.1...20
        case "angle": return -180...180
        case "amount": return 0...(clip.effects.contains { $0.kind == .chromaticAberration } ? 20 : 1)
        default: return 0...2
        }
    }

    func add(_ kind: EffectKind) {
        session.editClip(clip.id, "Add \(kind.displayName)") { $0.effects.append(EffectInstance(kind: kind)) }
    }

    func update(_ id: UUID, _ body: @escaping (inout EffectInstance) -> Void) {
        session.editClip(clip.id, "Effect Setting") { c in
            if let i = c.effects.firstIndex(where: { $0.id == id }) { body(&c.effects[i]) }
        }
    }
}

struct MultiSelectionInspector: View {
    @ObservedObject var session: ProjectSession
    let count: Int

    var body: some View {
        InspectorSection("\(count) clips selected") {
            HStack {
                Button("Delete") { session.deleteSelection(ripple: false) }.buttonStyle(.pulse(.secondary, compact: true))
                Button("Ripple Delete") { session.deleteSelection(ripple: true) }.buttonStyle(.pulse(.secondary, compact: true))
                Button("Duplicate") { session.duplicateSelection() }.buttonStyle(.pulse(.secondary, compact: true))
            }
            Button("Link Clips") {
                let ids = Array(session.selectedClipIDs)
                session.editTimeline("Link Clips") { $0.link(clipIDs: ids) }
            }
            .buttonStyle(.pulse(.ghost, compact: true))
        }
    }
}

/// Inspector when nothing is selected: canvas, layout, captions, markers, AI removals.
struct TimelineInspector: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    let timeline: Timeline

    var body: some View {
        VStack(spacing: 0) {
            InspectorSection("Canvas") {
                HStack(spacing: 4) {
                    ForEach(AspectChoice.allCases, id: \.self) { choice in
                        let size = choice.size
                        let active = timeline.canvas.width == size.width && timeline.canvas.height == size.height
                        Button(choice.rawValue) {
                            var canvas = timeline.canvas
                            canvas.width = size.width
                            canvas.height = size.height
                            session.setCanvas(canvas)
                        }
                        .buttonStyle(.pulse(active ? .primary : .secondary, compact: true))
                    }
                }
                Picker("Frame rate", selection: Binding(get: { timeline.canvas.frameRate }, set: { fps in session.editTimeline("Frame Rate") { $0.canvas.frameRate = fps } })) {
                    ForEach([24.0, 25, 30, 50, 60], id: \.self) { Text("\(Int($0)) fps").tag($0) }
                }
                ColorRow(label: "Background", color: Binding(get: { timeline.canvas.backgroundColor }, set: { c in session.editTimeline("Background", coalesce: "bg") { $0.canvas.backgroundColor = c } }))
            }
            InspectorSection("Layout", isAI: timeline.layout == .dynamic) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 6)], spacing: 6) {
                    ForEach(LayoutPreset.allCases, id: \.self) { preset in
                        Button { session.applyLayout(preset) } label: {
                            VStack(spacing: 4) {
                                Image(systemName: preset.symbolName).font(.system(size: 16))
                                Text(preset.displayName).font(.system(size: 9.5, weight: .medium)).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(timeline.layout == preset ? Theme.accent : Theme.textSecondary)
                            .background(RoundedRectangle(cornerRadius: 6).fill(timeline.layout == preset ? Theme.accentSoft : Theme.control))
                        }
                        .buttonStyle(.plain)
                        .help(preset.displayName)
                    }
                }
                Text("Layouts set crops and positions on the gameplay and facecam clips. Select a clip to fine-tune it.")
                    .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            }
            InspectorSection("Captions", isAI: timeline.captions?.aiGenerated ?? false) {
                if let captions = timeline.captions {
                    ToggleRow(label: "Show captions", isOn: Binding(get: { captions.isEnabled }, set: { on in session.editTimeline("Toggle Captions") { $0.captions?.isEnabled = on } }))
                    Picker("Style", selection: Binding(get: { captions.style.presetName }, set: { name in
                        guard let preset = CaptionStyle.preset(named: name) else { return }
                        session.editTimeline("Caption Style") { t in
                            let y = t.captions?.style.positionY
                            t.captions?.style = preset
                            if t.layout == .splitScreen, let y { t.captions?.style.positionY = y }
                        }
                    })) {
                        ForEach(CaptionStyle.presets, id: \.presetName) { Text($0.presetName).tag($0.presetName) }
                        if CaptionStyle.preset(named: captions.style.presetName) == nil { Text(captions.style.presetName).tag(captions.style.presetName) }
                    }
                    Button("Open Caption Editor") { app.section = .captions }.buttonStyle(.pulse(.secondary, compact: true))
                } else {
                    Button { CaptionsWorkspace.generateCaptions(session: session) } label: { Label("Generate Captions", systemImage: "captions.bubble") }
                        .buttonStyle(.pulse(.ai, compact: true))
                }
            }
            InspectorSection("Markers", expanded: !timeline.markers.isEmpty) {
                if timeline.markers.isEmpty {
                    Text("Press M to add a marker at the playhead.").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                }
                ForEach(timeline.markers.sorted { $0.time < $1.time }) { marker in
                    HStack {
                        Circle().fill(Color(marker.color.rgba)).frame(width: 7, height: 7)
                        Text(marker.name).font(.pulseCaption).foregroundStyle(Theme.textPrimary)
                        if marker.aiGenerated { AIBadge() }
                        Spacer()
                        Button(Timecode.short(marker.time)) { session.playback.seek(to: marker.time) }.buttonStyle(.plain).font(.pulseMono).foregroundStyle(Theme.textTertiary)
                        Button { session.editTimeline("Delete Marker") { t in t.markers.removeAll { $0.id == marker.id } } } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            InspectorSection("Removed Sections", isAI: timeline.removedSections.contains { $0.aiGenerated }, expanded: !timeline.removedSections.isEmpty) {
                if timeline.removedSections.isEmpty {
                    Text("Silence, filler words and transcript deletions appear here so you can restore them.").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                }
                ForEach(timeline.removedSections) { section in
                    HStack {
                        Image(systemName: section.reason == .silence ? "waveform.path" : (section.reason == .fillerWord ? "text.badge.minus" : "scissors"))
                            .font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(section.text.map { "“\($0)”" } ?? section.reason.displayName).font(.pulseCaption).foregroundStyle(Theme.textPrimary).lineLimit(1)
                            Text("\(String(format: "%.2fs", section.sourceRange.duration)) at \(Timecode.short(section.sourceRange.start))").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                        Button("Restore") {
                            let id = section.id
                            session.editTimeline("Restore Section") { try $0.restore(removedSectionID: id) }
                        }
                        .buttonStyle(.pulse(.ghost, compact: true))
                    }
                }
            }
            InspectorSection("AI", isAI: true) {
                Button { session.makeMoreEntertaining() } label: { Label("Make More Entertaining", systemImage: "wand.and.stars").frame(maxWidth: .infinity) }
                    .buttonStyle(.pulse(.ai, compact: true))
                if let report = session.lastAIReport {
                    Text(report).font(.pulseMicro).foregroundStyle(Theme.textSecondary)
                }
                Button { session.stripAI() } label: { Label("Remove All AI Edits", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(.pulse(.ghost, compact: true))
                    .disabled(!timeline.hasAIContent)
                Text("AI never bakes edits into your media. Everything it adds is a normal clip, keyframe, caption or cut you can change.")
                    .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            }
        }
    }
}
