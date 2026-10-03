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
    @State private var choosing = false

    var options: LongFormOptions {
        LongFormOptions(minimumLength: minMinutes * 60, maximumLength: max(maxMinutes, minMinutes) * 60, coldOpen: coldOpen,
                        cutDeadAir: true, zooms: zooms, captions: captions, memes: memes, soundEffects: soundEffects, music: music,
                        restraint: LongFormOptions.Restraint(rawValue: restraint) ?? .balanced)
    }

    var body: some View {
        if choosing {
            LongFormStoryboard(session: session, options: options, onBack: { choosing = false }) { segments, hookPayoff in
                session.editMyVOD(options: options, segments: segments, hookPayoff: hookPayoff)
                dismiss()
            }
            .frame(width: 820, height: 680)
            .background(Theme.panel)
            .preferredColorScheme(.dark)
        } else {
            settingsPage
        }
    }

    var settingsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    lengthSection
                    touchesSection
                    styleSection
                    whatHappens
                }
                .padding(20)
            }
            Divider().overlay(Theme.divider)
            footer
        }
        .frame(width: 560, height: 640)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
    }

    var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Theme.aiSoft)
                Image(systemName: "film.stack").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.ai)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("Edit My VOD").font(.pulseTitle).foregroundStyle(Theme.textPrimary)
                Text("Turn the whole stream into a YouTube video that feels produced, not a raw VOD.")
                    .font(.pulseCaption).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(20)
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
            touch("Zooms", "plus.magnifyingglass", "Punch-ins on the big reactions", $zooms)
            touch("Captions", "captions.bubble", "Clean subtitles — outlined, no box, easy to read", $captions)
            touch("Memes", "face.smiling", "Pop-up text on the funniest moments", $memes)
            touch("Sound effects", "speaker.wave.2.fill", "Whooshes, booms and comedy stings", $soundEffects)
            touch("Music", "music.note", "A quiet, calm bed under each chapter, ducked under talking", $music)
            if music {
                touch("Find music on YouTube", "globe", "Creative Commons tracks via the built-in downloader (credits go in the description)",
                      Binding(get: { app.settings.ai.onlineMusic }, set: { app.settings.ai.onlineMusic = $0 }))
                    .padding(.leading, 20)
            }
        }
    }

    func touch(_ title: String, _ symbol: String, _ detail: String, _ isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(isOn.wrappedValue ? Theme.ai : Theme.textTertiary).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.pulseBody).foregroundStyle(Theme.textPrimary)
                Text(detail).font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(Theme.ai)
        }
        .padding(.vertical, 4)
    }

    var styleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "How much editing")
            Picker("", selection: $restraint) {
                ForEach(LongFormOptions.Restraint.allCases, id: \.self) { Text($0.displayName).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(restraintNote).font(.pulseMicro).foregroundStyle(Theme.textTertiary)
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
            }
            .font(.pulseCaption).foregroundStyle(Theme.textSecondary)
        }
    }

    var footer: some View {
        HStack {
            if session.document.primaryAsset != nil {
                let analyzed = session.document.primaryAsset.flatMap { session.analyses[$0.id] } != nil
                let estimate = session.longFormEstimate(options: options) + (analyzed ? 0 : session.document.primaryAsset.map(session.analysisEstimate) ?? 0)
                Label("Takes \(DurationText.approximate(estimate))\(analyzed ? "" : " (includes analyzing)")", systemImage: "clock")
                    .font(.pulseCaption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { app.showReferenceSheet = true }
            } label: { Label("Like a Reference…", systemImage: "wand.and.stars") }
                .buttonStyle(.pulse(.ghost, compact: true))
                .help("Copy the editing style of a video you love instead")
            Button("Cancel") { dismiss() }.buttonStyle(.pulseSecondary).keyboardShortcut(.cancelAction)
            let analyzed = session.document.primaryAsset.flatMap { session.analyses[$0.id] }.map { $0.audio != nil || $0.transcript != nil } ?? false
            Button { choosing = true } label: { Label("Choose Moments…", systemImage: "square.grid.3x2") }
                .buttonStyle(.pulseSecondary)
                .disabled(!analyzed)
                .help(analyzed ? "See every moment PULSE picked, swap some out and choose the hook" : "Analyze the video first (or just press Edit My VOD)")
            Button {
                session.editMyVOD(options: options)
                dismiss()
            } label: { Label("Edit My VOD", systemImage: "wand.and.stars") }
                .buttonStyle(.pulseAI)
                .keyboardShortcut(.defaultAction)
                .disabled(session.document.primaryAsset == nil)
        }
        .padding(16)
    }
}
