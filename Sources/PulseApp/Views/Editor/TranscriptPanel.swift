import PulseCore
import PulseEngine
import SwiftUI

/// Simple flow layout for word chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 3
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 300
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

struct TranscriptPanel: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    @ObservedObject var playback: PlaybackController
    @State private var query = ""
    @State private var selection: ClosedRange<Int>?
    @State private var anchor: Int?
    @State private var wholeRecording = false
    @State private var showFillers = true

    init(session: ProjectSession) {
        self.session = session
        self.playback = session.playback
    }

    var assetID: UUID? {
        session.activeTimeline?.origin?.assetID ?? session.activeTimeline?.assetIDs.first ?? session.document.primaryAsset?.id
    }

    var transcript: Transcript? { assetID.flatMap { session.analyses[$0]?.transcript } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                TextField("Search transcript", text: $query).textFieldStyle(.roundedBorder).controlSize(.small)
                Toggle(isOn: $showFillers) { Image(systemName: "text.badge.minus") }
                    .toggleStyle(.button).controlSize(.small).help("Highlight filler words")
                Toggle(isOn: $wholeRecording) { Image(systemName: "text.justify") }
                    .toggleStyle(.button).controlSize(.small).help("Show the whole recording, not just this clip")
                if let assetID { speakersMenu(assetID: assetID) }
            }
            .padding(8)
            if let transcript, let assetID {
                if let selection { selectionBar(transcript: transcript, assetID: assetID, selection: selection) }
                content(transcript: transcript, assetID: assetID)
            } else {
                EmptyStateView(symbol: "text.quote", title: "No transcript",
                               message: "Analyze the recording to transcribe it, or import an SRT/VTT file from the Import page.",
                               actionTitle: session.document.primaryAsset == nil ? nil : "Transcribe Now") {
                    if let id = assetID { session.analyze(assetID: id, generateClips: false) }
                }
            }
        }
    }

    func content(transcript: Transcript, assetID: UUID) -> some View {
        let timeline = session.activeTimeline
        let bounds: TimeRange? = wholeRecording ? nil : timeline?.origin?.sourceRange.expanded(by: 8)
        let sentences = transcript.sentences().filter { s in bounds.map { $0.overlaps(s.range) } ?? true }
        let fillers: Set<Int> = showFillers ? Set(FillerWordDetector.detect(in: transcript, range: bounds).flatMap { Array($0.firstWord...$0.lastWord) }) : []
        let visibleClips = (timeline?.allClips ?? []).filter { $0.assetID == assetID }
        let hits: Set<Int> = query.isEmpty ? [] : Set(transcript.search(query).flatMap { hit in Array(hit.wordIndex..<min(transcript.words.count, hit.wordIndex + max(1, query.split(separator: " ").count))) })
        let currentWord = currentSourceTime(visibleClips).flatMap { transcript.wordIndex(at: $0) }
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(sentences) { sentence in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(Timecode.short(sentence.start)).font(.pulseMono).foregroundStyle(Theme.textTertiary)
                                if let name = transcript.speakerName(sentence.speaker), transcript.speakerIDs.count > 1 {
                                    Text(name).font(.pulseMicro.weight(.semibold)).foregroundStyle(Theme.speakerColor(sentence.speaker ?? 0))
                                }
                            }
                            FlowLayout {
                                ForEach(sentence.firstWord...sentence.lastWord, id: \.self) { index in
                                    wordView(index: index, transcript: transcript, visibleClips: visibleClips, filler: fillers.contains(index), hit: hits.contains(index), current: index == currentWord)
                                }
                            }
                        }
                        .id(sentence.firstWord)
                        .contextMenu {
                            Button("Create Clip from Sentence") { session.createClip(fromSource: sentence.range.expanded(by: 0.3), assetID: assetID) }
                            Button("Select Sentence") { selection = sentence.firstWord...sentence.lastWord }
                            if let s = sentence.speaker {
                                Button("Rename Speaker…") { renameSpeaker(s, assetID: assetID) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 20)
            }
            .onChange(of: currentWord) { _, word in
                guard playback.isPlaying, let word, let sentence = sentences.last(where: { $0.firstWord <= word }) else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(sentence.firstWord, anchor: .center) }
            }
        }
    }

    func currentSourceTime(_ clips: [TimelineClip]) -> Seconds? {
        let t = playback.currentTime
        guard let clip = clips.first(where: { $0.timelineRange.contains(t) }) else { return nil }
        return clip.sourceTime(atTimeline: t)
    }

    func timelineTime(for word: TranscriptWord, clips: [TimelineClip]) -> Seconds? {
        let mid = (word.start + word.end) / 2
        guard let clip = clips.first(where: { $0.sourceRange.contains(mid) }) else { return nil }
        return clip.timelineTime(atSource: max(word.start, clip.sourceIn))
    }

    func wordView(index: Int, transcript: Transcript, visibleClips: [TimelineClip], filler: Bool, hit: Bool, current: Bool) -> some View {
        let word = transcript.words[index]
        let time = timelineTime(for: word, clips: visibleClips)
        let inTimeline = time != nil || session.activeTimeline == nil
        let selected = selection?.contains(index) ?? false
        return Text(word.text)
            .font(.system(size: 12.5, weight: current ? .semibold : .regular))
            .strikethrough(!inTimeline, color: Theme.textTertiary)
            .underline(filler, color: Theme.warning)
            .foregroundStyle(current ? Theme.accent : (inTimeline ? Theme.textPrimary : Theme.textTertiary))
            .padding(.horizontal, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(selected ? Theme.info.opacity(0.35) : (hit ? Theme.warning.opacity(0.3) : .clear)))
            .onTapGesture {
                if NSEvent.modifierFlags.contains(.shift), let a = anchor {
                    selection = min(a, index)...max(a, index)
                } else {
                    anchor = index
                    selection = nil
                    if let time { playback.seek(to: time) }
                }
            }
            .help(filler ? "Likely filler word" : Timecode.short(word.start))
    }

    func selectionBar(transcript: Transcript, assetID: UUID, selection: ClosedRange<Int>) -> some View {
        let words = transcript.words[selection]
        let range = TimeRange(start: words.first!.start - 0.02, end: words.last!.end + 0.02)
        let text = words.map(\.text).joined(separator: " ")
        return HStack(spacing: 6) {
            Text("\(selection.count) words").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
            Spacer()
            Button { session.deleteTranscriptRange(range, assetID: assetID, text: text); self.selection = nil } label: { Label("Delete", systemImage: "scissors") }
                .buttonStyle(.pulse(.secondary, compact: true))
                .help("Removes this speech from the timeline (restorable)")
            Button { session.createClip(fromSource: range.expanded(by: 0.3), assetID: assetID) } label: { Label("Clip", systemImage: "sparkles") }
                .buttonStyle(.pulse(.ai, compact: true))
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.pulse(.ghost, compact: true))
            Button { self.selection = nil } label: { Image(systemName: "xmark") }.buttonStyle(.pulse(.ghost, compact: true))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.panelRaised)
        .onDeleteCommand { session.deleteTranscriptRange(range, assetID: assetID, text: text); self.selection = nil }
    }

    /// Speakers: detect (auto or a fixed count), rename, merge.
    func speakersMenu(assetID: UUID) -> some View {
        let ids = transcript?.speakerIDs ?? []
        return Menu {
            Section("Detect Speakers") {
                Button("Automatic") { session.detectSpeakers(assetID: assetID) }
                ForEach(2...5, id: \.self) { n in
                    Button("\(n) speakers") { session.detectSpeakers(assetID: assetID, count: n) }
                }
            }
            if ids.count > 1 {
                Section("Speakers") {
                    ForEach(ids, id: \.self) { id in
                        Menu(transcript?.speakerName(id) ?? "Speaker \(id + 1)") {
                            Button("Rename…") { renameSpeaker(id, assetID: assetID) }
                            ForEach(ids.filter { $0 != id }, id: \.self) { other in
                                Button("Merge into \(transcript?.speakerName(other) ?? "Speaker \(other + 1)")") {
                                    session.mergeSpeaker(id, into: other, assetID: assetID)
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            Label(ids.count > 1 ? "\(ids.count)" : "", systemImage: "person.2.wave.2")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(ids.count > 1 ? "\(ids.count) speakers — detect again, rename or merge" : "Detect who's talking")
    }

    func renameSpeaker(_ id: Int, assetID: UUID) {
        let alert = NSAlert()
        alert.messageText = "Rename Speaker"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = transcript?.speakerName(id) ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, var analysis = session.analyses[assetID], var t = analysis.transcript else { return }
        t.renameSpeaker(id: id, to: field.stringValue)
        analysis.transcript = t
        session.setAnalysis(analysis)
    }
}
