import PulseCore
import PulseEngine
import SwiftUI

/// The question PULSE asks before every Edit My VOD: which of the optional extras to use. Nothing here is
/// applied unless it's ticked; the answers are remembered as next time's starting point.
struct EditExtrasSheet: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    /// Offer "Approve the cut" (not when the moments were already chosen, or for a reference edit).
    var offerApproveCut = true
    /// Music is on for this edit (beat sync needs it).
    var musicOn = true
    let onCancel: () -> Void
    let onDone: (EditExtras) -> Void

    @State private var extras = EditExtras()
    @State private var fineTune = false
    @State private var phrasesText = ""

    var analysis: MediaAnalysis? { session.document.primaryAsset.flatMap { session.analyses[$0.id] } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader("Any extras for this edit?", symbol: "questionmark.bubble",
                        subtitle: "Nothing below happens unless you tick it. PULSE remembers your answers for next time.")
            Divider().overlay(Theme.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Start from").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                        ForEach(EditExtras.Preset.allCases, id: \.self) { preset in
                            Button(preset.displayName) { extras.apply(preset) }
                                .buttonStyle(.pulse(EditExtras.Preset.matching(extras) == preset ? .primary : .secondary, compact: true))
                        }
                        Spacer()
                    }
                    .padding(.bottom, 8)
                    .help("Sensible answers for a kind of stream — change anything after")
                    SectionLabel(text: "While editing")
                    row("Facecam punch-ins", "person.crop.square", facecamDetail, \.facecamPunchIns, enabled: hasFacecam, preview: .punchIns)
                    row("B-roll cutaways", "film", "Short Creative Commons meme and reaction clips cut in on the funniest moments, downloaded from YouTube. Credits go in the description. Adds about a minute.",
                        \.brollClips, preview: .broll)
                    row("Beat-synced music & zooms", "metronome", musicOn ? "Music starts on a beat and the zooms land on beats. Adds a few seconds." : "Needs music; music is off for this edit.",
                        \.beatSync, enabled: musicOn, preview: .beatSync)
                    row("Speaker-aware cuts", "person.2.wave.2", speakerDetail, \.speakerAware, preview: .speakers)
                    row("Retention title cards", "text.badge.star", "Short “THEN THIS HAPPENED…” or “20 MINUTES LATER…” cards where the video jumps ahead.",
                        \.titleCards, preview: .titleCards)
                    row("Instant replays", "arrow.counterclockwise.circle", replayDetail, \.instantReplays, enabled: isGameplay, preview: .replays)
                    if offerApproveCut {
                        SectionLabel(text: "Before building").padding(.top, 10)
                        row("Approve the cut", "checklist", "Review every section first: preview it, keep or drop it, move its start and end. Nothing is built until you approve.",
                            \.approveCut)
                    }
                    SectionLabel(text: "When exporting").padding(.top, 10)
                    row("Loudness check", "speaker.wave.3", "Measures the finished mix (YouTube plays everything at −14 LUFS) and asks before changing anything. About 10 s per 20 minutes of video.",
                        \.loudnessCheck)
                    DisclosureGroup(isExpanded: $fineTune) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text("Replay speed").font(.pulseCaption).foregroundStyle(Theme.textSecondary).frame(width: 110, alignment: .leading)
                                Picker("", selection: $extras.replaySpeed) {
                                    Text("0.5×").tag(0.5)
                                    Text("0.35×").tag(0.35)
                                    Text("0.25×").tag(0.25)
                                }
                                .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                                TextField("REPLAY", text: $extras.replayTag).textFieldStyle(.roundedBorder).frame(width: 110)
                                    .help("The tag over a replay")
                            }
                            HStack(spacing: 14) {
                                Toggle("Whoosh into replays", isOn: $extras.replaySting).toggleStyle(.checkbox).font(.pulseCaption)
                                Toggle("Slightly desaturated", isOn: $extras.replayDesaturate).toggleStyle(.checkbox).font(.pulseCaption)
                            }
                            HStack(spacing: 8) {
                                Text("Punch-in hold").font(.pulseCaption).foregroundStyle(Theme.textSecondary).frame(width: 110, alignment: .leading)
                                Slider(value: $extras.punchInHold, in: 0.8...4, step: 0.1).frame(width: 160)
                                Text(String(format: "%.1f s", extras.punchInHold)).font(.pulseMono).foregroundStyle(Theme.textSecondary)
                                Stepper(value: $extras.punchInsPerVideo, in: 0...20) {
                                    Text(extras.punchInsPerVideo == 0 ? "PULSE decides how many" : "at most \(extras.punchInsPerVideo) per video").font(.pulseCaption)
                                }
                            }
                            HStack(alignment: .top, spacing: 8) {
                                Text("Card phrases").font(.pulseCaption).foregroundStyle(Theme.textSecondary).frame(width: 110, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    TextField("HERE WE GO, AND THEN…", text: $phrasesText, onCommit: commitPhrases)
                                        .textFieldStyle(.roundedBorder)
                                    Text("Your own title-card lines, comma-separated, used in turn when the streamer's words don't make a card.")
                                        .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                                }
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Text("Fine-tune the extras").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.top, 12)
                }
                .padding(20)
            }
            Divider().overlay(Theme.divider)
            HStack {
                Button("Untick All") { extras = EditExtras() }
                    .buttonStyle(.pulse(.ghost, compact: true))
                Toggle("Ask once per project", isOn: $app.settings.ai.askExtrasOncePerProject)
                    .toggleStyle(.checkbox).font(.pulseCaption)
                    .help("After this, Edit My VOD in this project uses these answers without asking; Settings → AI Features turns it back on")
                Spacer()
                Button("Back") { onCancel() }.buttonStyle(.pulseSecondary).keyboardShortcut(.cancelAction)
                Button {
                    commitPhrases()
                    var answer = extras
                    if !offerApproveCut { answer.approveCut = app.settings.ai.editExtras.approveCut }
                    app.settings.ai.editExtras = answer
                    session.edit("Answer Extras") { $0.extrasAnswered = true }
                    PulseLog.info("Edit extras: \(describe(extras))")
                    onDone(extras.with(approveCut: offerApproveCut && extras.approveCut))
                } label: {
                    Label(offerApproveCut && extras.approveCut ? "Review the Cut…" : "Edit My VOD", systemImage: "wand.and.stars")
                }
                .buttonStyle(.pulseAI)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 540, height: 660)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
        .onAppear {
            extras = app.settings.ai.editExtras
            phrasesText = extras.titleCardPhrases.joined(separator: ", ")
            fineTune = extras.replaySpeed != 0.5 || extras.punchInsPerVideo != 0 || !extras.titleCardPhrases.isEmpty
        }
    }

    /// Unknown until analyzed → offered; analyzed and absent → greyed out with the reason in the text.
    var hasFacecam: Bool { analysis.map { $0.profile == .gameplayWithFacecam && $0.webcam != nil } ?? true }
    var isGameplay: Bool { analysis.map { $0.profile == .gameplay || $0.profile == .gameplayWithFacecam } ?? true }

    var facecamDetail: String {
        let base = "Big reactions zoom into your facecam instead of the middle of the game."
        guard let analysis else { return base + " Used when PULSE finds a facecam." }
        return analysis.profile == .gameplayWithFacecam && analysis.webcam != nil
            ? base : base + " No facecam was found in this video, so it won't change anything here."
    }

    var replayDetail: String {
        let base = "The biggest plays again in slow motion right after they land, with a “REPLAY” tag and a whoosh."
        guard let analysis else { return base + " Gameplay videos only." }
        return analysis.profile == .gameplay || analysis.profile == .gameplayWithFacecam
            ? base : base + " This video isn't gameplay, so it won't change anything here."
    }

    var speakerDetail: String {
        let base = "Sections start and end on whole sentences — nobody gets cut off mid-thought."
        let labelled = analysis?.transcript?.words.contains { $0.speaker != nil } ?? false
        return base + (labelled ? " Stretches where people talk over each other are trimmed."
                                : " Crosstalk trimming also needs speaker labels (Detect Speakers in Settings → AI).")
    }

    func row(_ title: String, _ symbol: String, _ detail: String, _ key: WritableKeyPath<EditExtras, Bool>, enabled: Bool = true,
             preview: ExtraPreview.Kind? = nil) -> some View {
        let isOn = Binding(get: { extras[keyPath: key] && enabled }, set: { extras[keyPath: key] = $0 })
        return Toggle(isOn: isOn) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol).foregroundStyle(isOn.wrappedValue ? Theme.ai : Theme.textTertiary).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.pulseBody).foregroundStyle(enabled ? Theme.textPrimary : Theme.textTertiary)
                    Text(detail).font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                // What it looks like (#126), so the choice is visual.
                if let preview { ExtraPreview(kind: preview).opacity(enabled ? 1 : 0.4) }
            }
            .padding(.leading, 4)
        }
        .toggleStyle(.checkbox)
        .disabled(!enabled)
        .padding(.vertical, 5)
    }

    func commitPhrases() {
        extras.titleCardPhrases = phrasesText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    func describe(_ e: EditExtras) -> String {
        let on = [("facecam", e.facecamPunchIns), ("b-roll", e.brollClips), ("beat sync", e.beatSync), ("speaker-aware", e.speakerAware),
                  ("approve cut", e.approveCut), ("title cards", e.titleCards), ("loudness check", e.loudnessCheck),
                  ("instant replays", e.instantReplays)].filter { $0.1 }.map { $0.0 }
        return on.isEmpty ? "none" : on.joined(separator: ", ")
    }
}

extension EditExtras {
    func with(approveCut: Bool) -> EditExtras {
        var copy = self
        copy.approveCut = approveCut
        return copy
    }
}
