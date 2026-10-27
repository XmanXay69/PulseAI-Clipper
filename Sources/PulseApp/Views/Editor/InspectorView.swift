import AppKit
import PulseCore
import PulseEngine
import SwiftUI
import UniformTypeIdentifiers

/// Your saved grades (#317): apply with a click, save the current one by name, remove with ⌥-click.
struct GradePresetsRow: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    let clip: TimelineClip
    @State private var naming = false
    @State private var name = ""

    var body: some View {
        HStack(spacing: 5) {
            ForEach(app.settings.gradePresets) { preset in
                Button(preset.name) {
                    if NSEvent.modifierFlags.contains(.option) {
                        app.settings.gradePresets.removeAll { $0.id == preset.id }
                    } else {
                        session.editClip(clip.id, "Grade: \(preset.name)") { $0.color = preset.adjustments }
                    }
                }
                .buttonStyle(.pulse(clip.color == preset.adjustments ? .primary : .secondary, compact: true))
                .help("Apply “\(preset.name)” · ⌥-click removes it")
            }
            Button { name = ""; naming = true } label: { Label("Save grade", systemImage: "plus") }
                .buttonStyle(.pulse(.ghost, compact: true))
                .disabled(clip.color.isIdentity)
                .help("Keep this grade under a name to reuse on any clip")
                .popover(isPresented: $naming, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Save this grade as").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                        TextField("Warm webcam", text: $name, onCommit: save).textFieldStyle(.roundedBorder).frame(width: 200)
                        HStack {
                            Spacer()
                            Button("Save") { save() }.buttonStyle(.pulse(.primary, compact: true)).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(12)
                }
        }
    }

    func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var grade = clip.color
        grade.bypass = false
        app.settings.gradePresets.save(trimmed, adjustments: grade)
        naming = false
        app.toast("Grade “\(trimmed)” saved — it's in the Color section of every clip")
    }
}

struct InspectorView: View {
    @ObservedObject var session: ProjectSession
    @ObservedObject var playback: PlaybackController
    @State private var query = ""

    init(session: ProjectSession) {
        self.session = session
        self.playback = session.playback
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader("Inspector", subtitle: subtitle)
            TextField("Find a control (opac, duck, lut…)", text: $query)
                .textFieldStyle(.roundedBorder)
                .font(.pulseCaption)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .help("Type part of a control's name; only the sections that have it stay, opened (#224)")
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        if let timeline = session.activeTimeline {
                            let clips = session.selectedClips
                            if let clip = clips.first, let track = timeline.track(containingClip: clip.id) {
                                if clips.count > 1 { MultiSelectionInspector(session: session, count: clips.count) }
                                ClipInspector(session: session, playback: playback, clip: clip, track: track)
                            } else {
                                TimelineInspector(session: session, timeline: timeline)
                            }
                        }
                    }
                    // Lay everything out at the column's real width so rows never run past its edge.
                    .frame(width: geo.size.width)
                    .environment(\.inspectorQuery, query.trimmingCharacters(in: .whitespaces).lowercased())
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

    /// A change made with several clips selected applies to all of them (#225); a rename stays on this clip.
    func value<T>(_ label: String, _ keyPath: WritableKeyPath<TimelineClip, T>, fallback: T) -> Binding<T> {
        Binding(get: { clip?[keyPath: keyPath] ?? fallback },
                set: { newValue in
                    if label == "Rename" {
                        session.editClip(clipID, label) { $0[keyPath: keyPath] = newValue }
                    } else {
                        session.editSelectedClips(primary: clipID, label) { $0[keyPath: keyPath] = newValue }
                    }
                })
    }

    func animated(_ label: String, _ keyPath: WritableKeyPath<TimelineClip, AnimatedDouble>) -> Binding<Double> {
        let t = local
        return Binding(get: { clip?[keyPath: keyPath].value(at: t) ?? 0 },
                       set: { v in
                           session.editSelectedClips(primary: clipID, label) { c in
                               if c[keyPath: keyPath].isAnimated { c[keyPath: keyPath].setKeyframe(at: t, value: v) } else { c[keyPath: keyPath].value = v }
                           }
                       })
    }

    /// Jump the playhead to the previous / next keyframe of a property (#209).
    func jumpKeyframe(_ keyPath: WritableKeyPath<TimelineClip, AnimatedDouble>, direction: Int) {
        guard let clip, clip[keyPath: keyPath].isAnimated else { return }
        let times = clip[keyPath: keyPath].keyframes.map(\.time).sorted()
        let target = direction < 0 ? times.last { $0 < local - 1.0 / 60 } : times.first { $0 > local + 1.0 / 60 }
        if let target { session.playback.seek(to: clip.start + target) }
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

    /// A clip with every property at its default: where "reset" takes a value back to (#206).
    static let pristine = TimelineClip(name: "", content: .media(assetID: UUID()), start: 0, sourceDuration: 1)

    /// Slider with keyframe diamond and a reset arrow (resetting an animated value also clears its keyframes).
    func slider(_ label: String, _ keyPath: WritableKeyPath<TimelineClip, AnimatedDouble>, range: ClosedRange<Double>, format: String = "%.2f", unit: String = "") -> some View {
        LabeledSlider(label: label, value: animated(label, keyPath), range: range, format: format, unit: unit,
                      keyframed: hasKeyframe(keyPath), onKeyframe: { toggleKeyframe(label, keyPath) },
                      onEditingChanged: { editing in if !editing { session.commitCoalescing() } },
                      defaultValue: Self.pristine[keyPath: keyPath].value(at: 0),
                      onReset: { session.editClip(clipID, "Reset \(label)", coalesce: nil) { $0[keyPath: keyPath] = Self.pristine[keyPath: keyPath] } },
                      animated: clip?[keyPath: keyPath].isAnimated ?? false,
                      onPreviousKeyframe: { jumpKeyframe(keyPath, direction: -1) },
                      onNextKeyframe: { jumpKeyframe(keyPath, direction: 1) },
                      curve: curveSamples(keyPath, range: range),
                      curveProgress: clip.map { $0.duration > 0 ? local / $0.duration : 0 } ?? 0)
    }

    /// 24 samples of an animated value across the clip, normalized to the slider's range (#211); nil when static.
    func curveSamples(_ keyPath: WritableKeyPath<TimelineClip, AnimatedDouble>, range: ClosedRange<Double>) -> [Double]? {
        guard let clip, clip[keyPath: keyPath].isAnimated, clip.duration > 0 else { return nil }
        let span = max(range.upperBound - range.lowerBound, 1e-6)
        return (0..<24).map { i in
            let t = clip.duration * Double(i) / 23
            return (clip[keyPath: keyPath].value(at: t) - range.lowerBound) / span
        }
    }

    func plainSlider(_ label: String, _ keyPath: WritableKeyPath<TimelineClip, Double>, range: ClosedRange<Double>, format: String = "%.2f", unit: String = "") -> some View {
        LabeledSlider(label: label, value: value(label, keyPath, fallback: 0), range: range, format: format, unit: unit,
                      onEditingChanged: { editing in if !editing { session.commitCoalescing() } },
                      defaultValue: Self.pristine[keyPath: keyPath],
                      onReset: { session.editClip(clipID, "Reset \(label)", coalesce: nil) { $0[keyPath: keyPath] = Self.pristine[keyPath: keyPath] } })
    }
}

struct ClipInspector: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    @ObservedObject var playback: PlaybackController
    let clip: TimelineClip
    let track: Track

    var b: ClipBindings { ClipBindings(session: session, clipID: clip.id, local: max(0, playback.currentTime - clip.start)) }

    var body: some View { ClockObserving(clock: playback.slowClock) { clockedBody } }

    @ViewBuilder var clockedBody: some View {
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
                ClipLabelRow(session: session, current: clip.labelColor)
                if let why = clip.aiPassDescription {
                    Text(why).font(.pulseMicro).foregroundStyle(Theme.ai).fixedSize(horizontal: false, vertical: true)
                }
                if clip.hasAIMarks {
                    Button("Make Mine") { session.editClip(clip.id, "Make Mine") { $0.stripAIFlags() } }
                        .buttonStyle(.pulse(.ghost, compact: true))
                        .help("Keep every value and keyframe; drop the AI flags so later AI passes leave this clip alone")
                }
                if session.selectedClipIDs.count > 1 {
                    Text("Changes apply to all \(session.selectedClipIDs.count) selected clips").font(.pulseMicro).foregroundStyle(Theme.ai)
                }
                if clip.role == .music, let asset = clip.assetID.flatMap({ session.document.asset(id: $0) }) {
                    MusicTrackRow(path: asset.path)
                }
            }
            if clip.isVisual, let id = clip.assetID, let group = session.activeMulticamGroup, group.angle(id) != nil {
                MulticamAngleInspector(session: session, clip: clip, group: group)
            }
            switch clip.content {
            case .text(let element):
                TextInspector(session: session, clip: clip, element: element, b: b)
                transformSection(showCrop: false)
            case .solid:
                transformSection(showCrop: false)
            case .compound(let nestedID):
                InspectorSection("Compound Clip") {
                    KeyValueRow(key: "Contains", value: "\(session.document.timeline(id: nestedID)?.allClips.count ?? 0) clips")
                    HStack {
                        Button { session.openCompound(clipID: clip.id) } label: { Label("Open", systemImage: "square.stack.3d.up") }
                            .buttonStyle(.pulse(.secondary, compact: true))
                        Button { session.breakApartCompound(clipID: clip.id) } label: { Label("Break Apart", systemImage: "square.stack.3d.down.right") }
                            .buttonStyle(.pulse(.ghost, compact: true))
                    }
                }
                transformSection(showCrop: true)
                styleSection
                speedSection
                ColorInspector(session: session, clip: clip, b: b)
                EffectsInspector(session: session, clip: clip)
                transitionsSection
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

    /// "16:9 · 1.78" for the crop as it stands, from the source's pixel size (#227).
    var cropAspectReadout: String? {
        guard let id = clip.assetID, let asset = session.document.asset(id: id), asset.metadata.width > 0, asset.metadata.height > 0 else { return nil }
        let crop = clip.transform.crop
        let w = Double(asset.metadata.width) * crop.width
        let h = Double(asset.metadata.height) * crop.height
        guard w > 0, h > 0 else { return nil }
        let ratio = w / h
        let known: [(Double, String)] = [(9.0 / 16.0, "9:16"), (3.0 / 4.0, "3:4"), (4.0 / 5.0, "4:5"), (1, "1:1"), (4.0 / 3.0, "4:3"), (3.0 / 2.0, "3:2"), (16.0 / 9.0, "16:9"), (21.0 / 9.0, "21:9")]
        let name = known.first { abs($0.0 - ratio) / $0.0 < 0.015 }?.1
        let pixels = "\(Int(w.rounded()))×\(Int(h.rounded()))"
        return (name.map { "\($0) · " } ?? "") + String(format: "%.2f · ", ratio) + pixels
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
                    if let readout = cropAspectReadout {
                        HStack {
                            Text("Crop aspect").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text(readout).font(.pulseMono).foregroundStyle(Theme.textTertiary)
                        }
                        .help("Width ÷ height of the cropped picture, in source pixels (#227)")
                    }
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

    @ViewBuilder
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
            LabeledSlider(label: "Feather", value: optionalStyle("Feather", \.style.feather, fallback: 0), range: 0...0.25,
                          onEditingChanged: { if !$0 { session.commitCoalescing() } }, defaultValue: 0)
                .help("Soft edge on the mask — a circle facecam that fades into the game (#220)")
        }
        InspectorSection("Chroma Key", expanded: clip.style.chromaKey?.enabled == true) {
            ToggleRow(label: "Key out a colour", isOn: Binding(get: { clip.style.chromaKey?.enabled ?? false }, set: { on in
                session.editSelectedClips(primary: clip.id, "Chroma Key") { c in
                    if on { var key = c.style.chromaKey ?? .green; key.enabled = true; c.style.chromaKey = key } else { c.style.chromaKey?.enabled = false }
                }
            }), help: "Green-screen facecams and B-roll: the colour goes transparent (#221)")
            if clip.style.chromaKey?.enabled == true {
                HStack(spacing: 4) {
                    Button("Green") { setKey { $0.hue = 120 } }.buttonStyle(.pulse(abs((clip.style.chromaKey?.hue ?? 0) - 120) < 1 ? .primary : .secondary, compact: true))
                    Button("Blue") { setKey { $0.hue = 225 } }.buttonStyle(.pulse(abs((clip.style.chromaKey?.hue ?? 0) - 225) < 1 ? .primary : .secondary, compact: true))
                    Spacer()
                }
                LabeledSlider(label: "Hue", value: keyValue("Key Hue", \.hue), range: 0...359, format: "%.0f", unit: "°",
                              onEditingChanged: { if !$0 { session.commitCoalescing() } })
                LabeledSlider(label: "Tolerance", value: keyValue("Key Tolerance", \.tolerance), range: 0.05...0.6,
                              onEditingChanged: { if !$0 { session.commitCoalescing() } })
                LabeledSlider(label: "Softness", value: keyValue("Key Softness", \.softness), range: 0...0.4,
                              onEditingChanged: { if !$0 { session.commitCoalescing() } })
                LabeledSlider(label: "Spill", value: keyValue("Key Spill", \.spill), range: 0...1,
                              onEditingChanged: { if !$0 { session.commitCoalescing() } })
                LabeledSlider(label: "Min. colour", value: keyValue("Key Minimum", \.minimumSaturation), range: 0...0.6,
                              onEditingChanged: { if !$0 { session.commitCoalescing() } })
                    .help("Pixels greyer than this are never keyed — keeps hair and shadows")
            }
        }
    }

    /// A binding for an optional style value, written as nil when it's back at the fallback.
    func optionalStyle(_ label: String, _ keyPath: WritableKeyPath<TimelineClip, Double?>, fallback: Double) -> Binding<Double> {
        Binding(get: { session.activeTimeline?.clip(id: clip.id)?[keyPath: keyPath] ?? fallback },
                set: { v in session.editSelectedClips(primary: clip.id, label) { $0[keyPath: keyPath] = abs(v - fallback) < 1e-6 ? nil : v } })
    }

    func keyValue(_ label: String, _ keyPath: WritableKeyPath<ChromaKey, Double>) -> Binding<Double> {
        Binding(get: { (session.activeTimeline?.clip(id: clip.id)?.style.chromaKey ?? .green)[keyPath: keyPath] },
                set: { v in setKey(label) { $0[keyPath: keyPath] = v } })
    }

    func setKey(_ label: String = "Chroma Key", _ body: @escaping (inout ChromaKey) -> Void) {
        session.editSelectedClips(primary: clip.id, label) { c in
            var key = c.style.chromaKey ?? .green
            body(&key)
            c.style.chromaKey = key
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
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    let clip: TimelineClip
    let element: TextElement
    let b: ClipBindings

    static let fonts = ["TikTok Sans", "SF Pro Display", "SF Pro Rounded", "New York", "Helvetica Neue", "Avenir Next", "Futura", "Impact", "Arial Black", "Georgia", "Menlo", "Marker Felt", "Chalkboard SE"]

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
            TextStylePreview(element: element)
            HStack(spacing: 6) {
                Menu {
                    Section("Built in") {
                        ForEach(TextTemplates.builtIn) { template in
                            Button(template.name) { session.editClip(clip.id, "Apply \(template.name)") { template.apply(to: &$0) } }
                        }
                    }
                    if !app.settings.textTemplates.isEmpty {
                        Section("Yours") {
                            ForEach(app.settings.textTemplates) { template in
                                Button(template.name) { session.editClip(clip.id, "Apply \(template.name)") { template.apply(to: &$0) } }
                            }
                            Divider()
                            ForEach(app.settings.textTemplates) { template in
                                Button("Delete “\(template.name)”", role: .destructive) { app.settings.textTemplates.removeAll { $0.id == template.id } }
                            }
                        }
                    }
                } label: { Label("Templates", systemImage: "square.on.square") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help("Lower third, callout, meme, big title, subtitle — or one you saved (#217). The words stay.")
                Button {
                    let name = String(element.text.split(separator: "\n").first ?? "Text look").prefix(24)
                    if let template = TextTemplate.capture(clip, name: String(name)) {
                        app.settings.textTemplates.append(template)
                        app.toast("Saved “\(name)” as a text template")
                    }
                } label: { Label("Save Look", systemImage: "plus.square.on.square") }
                    .buttonStyle(.pulse(.ghost, compact: true))
                    .help("Keeps this font, colours, box, animation and position as a template")
            }
            Picker("Font", selection: textBinding("Font", \.style.fontName)) {
                if !app.settings.recentFonts.isEmpty {
                    Section("Recent") {
                        ForEach(app.settings.recentFonts.filter { Self.fonts.contains($0) }, id: \.self) { Text($0).font(.custom($0, size: 12)).tag($0) }
                    }
                }
                Section("All") {
                    ForEach(Self.fonts, id: \.self) { Text($0).font(.custom($0, size: 12)).tag($0) }
                }
            }
            .onChange(of: element.style.fontName) { _, name in app.settings.noteRecentFont(name) }
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
            if clip.audio.fadeIn > 0 || clip.audio.fadeOut > 0 || clip.transitionIn != nil || clip.transitionOut != nil {
                Picker("Fade shape", selection: b.value("Fade Shape", \.audio.fadeShape, fallback: .linear)) {
                    ForEach(FadeShape.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Equal power keeps a crossfade at one loudness through the middle; linear dips about 3 dB there (#169)")
            }
            if abs(clip.speed - 1) > 0.001 {
                ToggleRow(label: "Keep pitch at this speed", isOn: b.value("Pitch", \.audio.preservePitch, fallback: true),
                          help: "On: voices stay at their pitch when slowed or sped up. Off: tape-style varispeed — chipmunk fast, deep slow")
            }
            ToggleRow(label: "Mute", isOn: b.value("Mute", \.audio.isMuted, fallback: false))
        }
        InspectorSection("Auto Ducking", isAI: true) {
            ToggleRow(label: "Lower under dialogue", isOn: b.value("Ducking", \.audio.duckUnderDialogue, fallback: false),
                      help: "Automatically lowers this clip (music, game audio) whenever someone speaks")
            b.plainSlider("Duck by", \.audio.duckAmountDB, range: -30...0, format: "%.0f", unit: " dB")
            b.plainSlider("Attack", \.audio.duckAttack, range: 0.02...1, format: "%.2f", unit: " s")
            b.plainSlider("Release", \.audio.duckRelease, range: 0.05...3, format: "%.2f", unit: " s")
        }
        InspectorSection("Enhance", expanded: clip.audio.needsEnhanceRender) {
            EnhancePreviewRow(session: session, clip: clip)
            HStack(spacing: 6) {
                Button { session.editClip(clip.id, "Voice Preset") { $0.audio.applyVoicePreset() } } label: { Label("Voice Preset", systemImage: "mic") }
                    .buttonStyle(.pulse(.secondary, compact: true))
                    .help("Rumble filter, presence, gentle compression, −14 LUFS loudness and a limiter")
                Spacer()
                ProcessingBadge(location: .local)
            }
            ToggleRow(label: "Voice enhancement", isOn: b.value("Voice Enhance", \.audio.voiceEnhance, fallback: false),
                      help: "80 Hz rumble filter, less mud, more presence and gentle compression")
            ToggleRow(label: "Hum removal", isOn: b.value("Hum Removal", \.audio.humRemoval, fallback: false),
                      help: "Notches out 50/60 Hz mains hum and its first harmonics (cheap power supplies, long cables)")
            HStack(spacing: 6) {
                Text("Channels").font(.pulseCaption).foregroundStyle(Theme.textSecondary).frame(width: 74, alignment: .leading)
                Picker("", selection: Binding(get: { clip.audio.monoSource }, set: { v in session.editClip(clip.id, "Channels") { $0.audio.monoSource = v } })) {
                    ForEach(MonoSource.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().frame(width: 150)
            }
            .help("When only one side has sound, play it through both ears (#272)")
            ToggleRow(label: "De-esser", isOn: b.value("De-esser", \.audio.deEss, fallback: false),
                      help: "Tames harsh s and sh sounds: the band above 5 kHz comes down while it dominates")
            b.plainSlider("Noise reduction", \.audio.noiseReduction, range: 0...1)
            if clip.audio.noiseReduction > 0.001 {
                Picker("Method", selection: Binding(get: { clip.audio.noiseMethod },
                                                    set: { method in session.editClip(clip.id, "Noise Method") { $0.audio.noiseMethod = method } })) {
                    ForEach(NoiseReductionMethod.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .font(.pulseCaption)
                Text(noiseMethodHelp)
                    .font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
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
                HStack(spacing: 5) {
                    ForEach(EQSettings.presets, id: \.name) { preset in
                        Button(preset.name) { session.editClip(clip.id, "EQ \(preset.name)") { $0.audio.eq = preset.settings } }
                            .buttonStyle(.pulse(clip.audio.eq == preset.settings ? .primary : .secondary, compact: true))
                    }
                    Text("Warm, clear or radio voice").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                }
            }
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

extension AudioInspector {
    var noiseMethodHelp: String {
        switch clip.audio.noiseMethod {
        case .voiceIsolation:
            return VoiceIsolation.isAvailable
                ? "On-device neural voice isolation: keeps speech, removes keyboard, music, crowd and fans. The slider sets how much background stays."
                : "AI voice isolation needs macOS 13 or later on this Mac; Classic is used instead."
        case .spectral:
            return "Removes steady noise (hiss, hum, fans) and quiets gaps between words. Best when you want the room to stay natural."
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
            ToggleRow(label: "Bypass grade", isOn: b.value("Bypass Grade", \.color.bypass, fallback: false),
                      help: "Keep the values, render none of them — flip it to compare before and after")
            // One-click looks: a gentle starting point you can then tune below.
            HStack(spacing: 5) {
                ForEach(ColorAdjustments.Look.allCases, id: \.self) { look in
                    Button(look.displayName) { session.editClip(clip.id, "Look: \(look.displayName)") { $0.color = ColorAdjustments.look(look) } }
                        .buttonStyle(.pulse(clip.color == ColorAdjustments.look(look) ? .primary : .secondary, compact: true))
                        .help(look.detail)
                }
            }
            GradePresetsRow(session: session, clip: clip)
            if session.previousVisualClip(before: clip.id) != nil {
                Button {
                    session.matchGrade(of: clip.id, toClipBefore: true)
                } label: { Label("Match grade to previous clip", systemImage: "wand.and.rays") }
                    .buttonStyle(.pulse(.secondary, compact: true))
                    .help("Sets exposure, saturation and temperature so this clip's average look lands where the clip before it sits (#311)")
            }
            b.plainSlider("Exposure", \.color.exposure, range: -2...2, unit: " EV")
            b.plainSlider("Contrast", \.color.contrast, range: -1...1)
            b.plainSlider("Highlights", \.color.highlights, range: -1...0)
            b.plainSlider("Shadows", \.color.shadows, range: -1...1)
            b.plainSlider("Saturation", \.color.saturation, range: -1...1)
            b.plainSlider("Temperature", \.color.temperature, range: -1...1)
            b.plainSlider("Tint", \.color.tint, range: -1...1)
            b.plainSlider("Sharpness", \.color.sharpness, range: 0...1)
            b.plainSlider("Vignette", \.color.vignette, range: 0...1)
            b.plainSlider("Grain", \.color.grain, range: 0...1)
            if clip.color.grain > 0 {
                b.plainSlider("Grain size", \.color.grainSize, range: 0.5...3, format: "%.1f", unit: "×")
            }
            ToggleRow(label: "Protect skin tones", isOn: b.value("Protect Skin", \.color.protectSkin, fallback: false),
                      help: "Saturation boosts use vibrance, which leaves faces alone and lifts the rest (#308)")
            ToggleRow(label: "Auto white balance", isOn: b.value("Auto White Balance", \.color.autoWhiteBalance, fallback: false),
                      help: "Neutralises this layer's colour cast from its own average — for the facecam, not the game (#307)")
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
            if let review = session.activeReview { CoachSection(session: session, review: review) }
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
                ToggleRow(label: "Blur fill background", isOn: Binding(get: { timeline.canvas.blurFill }, set: { on in session.editTimeline("Blur Fill") { $0.canvas.backgroundBlur = on } }),
                          help: "Fill empty areas with a blurred copy of the video instead of a flat color")
                HStack {
                    Text("Brand kit").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button("Apply") { session.applyBrandKit(to: timeline.id) }
                        .buttonStyle(.pulse(.secondary, compact: true))
                        .help("Add your logo, intro/outro and caption look (Settings → Brand Kit)")
                }
                HStack {
                    Text("Thumbnail").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button("Make…") { app.thumbnailRequest = ThumbnailRequest(timelineID: timeline.id) }
                        .buttonStyle(.pulse(.secondary, compact: true))
                        .help("PULSE picks this edit's best reaction frames and opens them as designs in Thumbnail Studio (⇧⌘T)")
                }
            }
            InspectorSection("Layout", isAI: timeline.layout == .dynamic) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], spacing: 6) {
                    ForEach(LayoutPreset.allCases, id: \.self) { preset in
                        Button { session.applyLayout(preset) } label: {
                            VStack(spacing: 4) {
                                Image(systemName: preset.symbolName).font(.system(size: 16))
                                Text(preset.displayName).font(.system(size: 9.5, weight: .medium)).lineLimit(2)
                                    .multilineTextAlignment(.center).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
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
                if let main = session.document.primaryAsset, let webcam = session.analyses[main.id]?.webcam {
                    KeyValueRow(key: "Facecam", value: "found in \(Int((webcam.persistence * 100).rounded())) % of sampled frames · \(Int((webcam.region.width * 100).rounded())) × \(Int((webcam.region.height * 100).rounded())) % of the picture")
                        .help("How sure the analysis is about the facecam overlay (#45); move or resize the facecam clip on the canvas to override it")
                }
                LayoutChangesEditor(session: session, timeline: timeline)
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

/// Layout changes over time: morph to another layout at the playhead; list, jump to, re-time, remove.
struct LayoutChangesEditor: View {
    @ObservedObject var session: ProjectSession
    let timeline: Timeline
    @AppStorage("layoutMorphLength") private var morph = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Change over time")
            HStack(spacing: 6) {
                Menu {
                    ForEach([LayoutPreset.splitScreen, .facecamCorner, .circleFacecam, .facecamDominant, .fullFrame], id: \.self) { preset in
                        Button { session.addLayoutChange(preset, duration: morph) } label: { Label(preset.displayName, systemImage: preset.symbolName) }
                    }
                } label: {
                    Label("Morph at Playhead", systemImage: "wand.and.rays").font(.pulseCaption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("From the playhead, animate the gameplay and facecam into another layout")
                Spacer()
                Picker("", selection: $morph) {
                    Text("Cut").tag(0.0)
                    Text("0.3 s").tag(0.3)
                    Text("0.5 s").tag(0.5)
                    Text("1 s").tag(1.0)
                }
                .labelsHidden()
                .frame(width: 74)
                .help("Length of the morph")
            }
            ForEach(timeline.layoutChanges.sorted { $0.time < $1.time }) { change in
                HStack(spacing: 6) {
                    Button { session.playback.seek(to: change.time) } label: {
                        Text(Timecode.short(change.time)).font(.pulseMono).foregroundStyle(Theme.info)
                    }
                    .buttonStyle(.plain)
                    .help("Jump to this change")
                    Image(systemName: change.preset.symbolName).foregroundStyle(Theme.textSecondary)
                    Text(change.preset.displayName).lineLimit(1).foregroundStyle(Theme.textPrimary)
                    if change.aiGenerated { Image(systemName: "sparkles").font(.system(size: 9)).foregroundStyle(Theme.ai) }
                    Spacer(minLength: 2)
                    Menu(change.duration < 0.02 ? "cut" : String(format: "%.1f s", change.duration)) {
                        ForEach([0.0, 0.3, 0.5, 1.0, 1.5], id: \.self) { d in
                            Button(d == 0 ? "Cut" : String(format: "%.1f s", d)) { session.setLayoutChangeDuration(change.id, d) }
                        }
                    }
                    .menuStyle(.borderlessButton).fixedSize().font(.pulseMicro)
                    Button { session.removeLayoutChange(change.id) } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                        .buttonStyle(.plain).foregroundStyle(Theme.textTertiary).help("Remove this change")
                }
                .font(.pulseCaption)
            }
            if timeline.layoutChanges.isEmpty {
                Text("Same layout throughout. Move the playhead and morph to switch layouts smoothly — nothing gets cut.")
                    .font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }
}

/// A Creative Commons bed's library controls (#292, #304): favourite it, never hear it again, or open its
/// YouTube page to check the license yourself.
struct MusicTrackRow: View {
    @EnvironmentObject var app: AppModel
    let path: String
    @State private var track: OnlineTrack?

    var body: some View {
        Group {
            if let track {
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.credit).font(.pulseMicro).foregroundStyle(Theme.textTertiary).lineLimit(2)
                    HStack(spacing: 6) {
                        let favorite = app.settings.ai.favoriteTrackIDs.contains(track.videoID)
                        Button { toggleFavorite(track) } label: { Label(favorite ? "Favourite" : "Favourite", systemImage: favorite ? "star.fill" : "star") }
                            .buttonStyle(.pulse(favorite ? .primary : .secondary, compact: true))
                            .help("Picked first for this mood next time")
                        Button { block(track) } label: { Label("Never again", systemImage: "hand.raised") }
                            .buttonStyle(.pulse(.ghost, compact: true))
                            .help("Never picked again (undo in Settings → Transcription → Music)")
                        Button { NSWorkspace.shared.open(track.url) } label: { Label("YouTube", systemImage: "play.rectangle") }
                            .buttonStyle(.pulse(.ghost, compact: true))
                            .help("The track's page — check the license yourself")
                    }
                }
            }
        }
        .task(id: path) { track = await OnlineMusicLibrary.shared.track(forPath: path) }
    }

    func toggleFavorite(_ track: OnlineTrack) {
        if let i = app.settings.ai.favoriteTrackIDs.firstIndex(of: track.videoID) {
            app.settings.ai.favoriteTrackIDs.remove(at: i)
        } else {
            app.settings.ai.favoriteTrackIDs.append(track.videoID)
            app.settings.ai.blockedTrackIDs.removeAll { $0 == track.videoID }
        }
    }

    func block(_ track: OnlineTrack) {
        if !app.settings.ai.blockedTrackIDs.contains(track.videoID) { app.settings.ai.blockedTrackIDs.append(track.videoID) }
        app.settings.ai.favoriteTrackIDs.removeAll { $0 == track.videoID }
        app.toast("“\(track.title)” won't be picked again")
    }
}

/// Colour label dots for the selected clips (#177).
struct ClipLabelRow: View {
    @ObservedObject var session: ProjectSession
    let current: MarkerColor?

    var body: some View {
        HStack(spacing: 6) {
            Text("Label").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
            Spacer()
            Button { session.setLabel(nil) } label: {
                Image(systemName: "slash.circle").font(.system(size: 11)).foregroundStyle(current == nil ? Theme.textPrimary : Theme.textTertiary)
            }
            .buttonStyle(.plain).help("No label").accessibilityLabel("No label")
            ForEach(MarkerColor.allCases, id: \.self) { color in
                Button { session.setLabel(color) } label: {
                    Circle().fill(Color(color.rgba)).frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(.white, lineWidth: current == color ? 2 : 0))
                }
                .buttonStyle(.plain)
                .help(color.displayName)
                .accessibilityLabel("\(color.displayName) label")
                .accessibilityAddTraits(current == color ? [.isSelected] : [])
            }
        }
    }
}


/// "Hear 10 s": raw against processed for the clip's enhance settings (#261).
struct EnhancePreviewRow: View {
    @ObservedObject var session: ProjectSession
    let clip: TimelineClip
    @StateObject private var preview = EnhancePreview()

    var body: some View {
        HStack(spacing: 8) {
            if preview.isPlaying {
                Picker("", selection: $preview.hearing) {
                    Text("Raw").tag(EnhancePreview.Hearing.raw)
                    Text("Processed").tag(EnhancePreview.Hearing.processed)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 150)
                Button("Stop") { preview.stop() }.buttonStyle(.pulse(.ghost, compact: true))
            } else {
                Button {
                    guard let id = clip.assetID, let asset = session.document.asset(id: id) else { return }
                    session.playback.pause()
                    let local = max(0, min(session.playhead - clip.start, clip.duration))
                    preview.start(sourceURL: session.url(for: asset), clip: clip, sourceTime: clip.sourceTime(atTimeline: clip.start + local))
                } label: {
                    Label(preview.isRendering ? "Rendering…" : "Hear 10 s raw vs processed", systemImage: "ear")
                }
                .buttonStyle(.pulse(.secondary, compact: true))
                .disabled(preview.isRendering || !clip.audio.needsProcessing)
                .help(clip.audio.needsProcessing ? "Plays ten seconds around the playhead with and without these settings — flip between them while it plays (#261)"
                                                 : "Turn on an enhance setting first")
            }
            if let error = preview.error { Text(error).font(.pulseMicro).foregroundStyle(Theme.warning).lineLimit(1) }
        }
        .onDisappear { preview.stop() }
    }
}


/// The text look as the renderer draws it (#214): stroke, shadow, box and animation-free, updated as sliders move.
struct TextStylePreview: View {
    let element: TextElement
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            CheckerboardBackground()
            if let image {
                Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fit).padding(8)
            }
        }
        .frame(height: 64)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
        .task(id: element.style.hashValue ^ element.text.hashValue ^ Int(element.maxWidth * 1000)) {
            var sample = element
            if sample.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { sample.text = "Your text" }
            sample.text = String(sample.text.split(separator: "\n").first ?? "Your text")
            let rendered = await Task.detached(priority: .userInitiated) { TextRenderer.renderText(sample, renderScale: 0.5, canvasWidth: 1080) }.value
            image = rendered?.image
        }
    }
}

struct CheckerboardBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let cell: CGFloat = 8
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let dark = (Int(x / cell) + Int(y / cell)) % 2 == 0
                    ctx.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)), with: .color(dark ? Color(white: 0.16) : Color(white: 0.22)))
                    x += cell
                }
                y += cell
            }
        }
    }
}
