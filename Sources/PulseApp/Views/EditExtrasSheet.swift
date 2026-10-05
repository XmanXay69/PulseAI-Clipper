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

    var analysis: MediaAnalysis? { session.document.primaryAsset.flatMap { session.analyses[$0.id] } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.aiSoft)
                    Image(systemName: "questionmark.bubble").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.ai)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Any extras for this edit?").font(.pulseTitle).foregroundStyle(Theme.textPrimary)
                    Text("Nothing below happens unless you tick it. PULSE remembers your answers for next time.")
                        .font(.pulseCaption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            Divider().overlay(Theme.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: "While editing")
                    row("Facecam punch-ins", "person.crop.square", facecamDetail, \.facecamPunchIns)
                    row("B-roll cutaways", "film", "Short Creative Commons meme and reaction clips cut in on the funniest moments, downloaded from YouTube. Credits go in the description.",
                        \.brollClips)
                    row("Beat-synced music & zooms", "metronome", musicOn ? "Music starts on a beat and the zooms land on beats." : "Needs music; music is off for this edit.",
                        \.beatSync, enabled: musicOn)
                    row("Speaker-aware cuts", "person.2.wave.2", speakerDetail, \.speakerAware)
                    row("Retention title cards", "text.badge.star", "Short “THEN THIS HAPPENED…” or “20 MINUTES LATER…” cards where the video jumps ahead.",
                        \.titleCards)
                    if offerApproveCut {
                        SectionLabel(text: "Before building").padding(.top, 10)
                        row("Approve the cut", "checklist", "Review every section first: preview it, keep or drop it, move its start and end. Nothing is built until you approve.",
                            \.approveCut)
                    }
                    SectionLabel(text: "When exporting").padding(.top, 10)
                    row("Loudness check", "speaker.wave.3", "Measures the finished mix (YouTube plays everything at −14 LUFS) and asks before changing anything.",
                        \.loudnessCheck)
                }
                .padding(20)
            }
            Divider().overlay(Theme.divider)
            HStack {
                Button("Untick All") { extras = EditExtras() }
                    .buttonStyle(.pulse(.ghost, compact: true))
                Spacer()
                Button("Back") { onCancel() }.buttonStyle(.pulseSecondary).keyboardShortcut(.cancelAction)
                Button {
                    var answer = extras
                    if !offerApproveCut { answer.approveCut = app.settings.ai.editExtras.approveCut }
                    app.settings.ai.editExtras = answer
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
        .frame(width: 540, height: 600)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
        .onAppear { extras = app.settings.ai.editExtras }
    }

    var facecamDetail: String {
        let base = "Big reactions zoom into your facecam instead of the middle of the game."
        guard let analysis else { return base + " Used when PULSE finds a facecam." }
        return analysis.profile == .gameplayWithFacecam && analysis.webcam != nil
            ? base : base + " No facecam was found in this video, so it won't change anything here."
    }

    var speakerDetail: String {
        let base = "Sections start and end on whole sentences — nobody gets cut off mid-thought."
        let labelled = analysis?.transcript?.words.contains { $0.speaker != nil } ?? false
        return base + (labelled ? " Stretches where people talk over each other are trimmed."
                                : " Crosstalk trimming also needs speaker labels (Detect Speakers in Settings → AI).")
    }

    func row(_ title: String, _ symbol: String, _ detail: String, _ key: WritableKeyPath<EditExtras, Bool>, enabled: Bool = true) -> some View {
        let isOn = Binding(get: { extras[keyPath: key] && enabled }, set: { extras[keyPath: key] = $0 })
        return Toggle(isOn: isOn) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol).foregroundStyle(isOn.wrappedValue ? Theme.ai : Theme.textTertiary).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.pulseBody).foregroundStyle(enabled ? Theme.textPrimary : Theme.textTertiary)
                    Text(detail).font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 4)
        }
        .toggleStyle(.checkbox)
        .disabled(!enabled)
        .padding(.vertical, 5)
    }

    func describe(_ e: EditExtras) -> String {
        let on = [("facecam", e.facecamPunchIns), ("b-roll", e.brollClips), ("beat sync", e.beatSync), ("speaker-aware", e.speakerAware),
                  ("approve cut", e.approveCut), ("title cards", e.titleCards), ("loudness check", e.loudnessCheck)].filter { $0.1 }.map { $0.0 }
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
