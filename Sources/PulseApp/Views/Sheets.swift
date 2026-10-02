import PulseCore
import PulseEngine
import SwiftUI

// MARK: Onboarding

/// First-run guide: the five-step workflow, then import or open the sample.
struct OnboardingView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss

    static let steps: [(symbol: String, title: String, detail: String)] = [
        ("square.and.arrow.down", "Import", "Drop a long stream, podcast or video. PULSE references it in place — nothing is copied."),
        ("waveform.and.magnifyingglass", "AI Analyze", "Speech, silence, volume spikes, scene changes and faces are analyzed on this Mac."),
        ("sparkles", "Create", "Captioned 9:16 shorts of the best moments — or Edit My VOD for a 10–20 min YouTube video."),
        ("timeline.selection", "Edit", "Every AI decision is a normal, editable clip on a pro timeline. The coach suggests what to fix."),
        ("square.and.arrow.up", "Export", "TikTok, Shorts, Reels and YouTube presets, hardware encoding, batch export queue."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: AppIcon.render(size: 128)).resizable().frame(width: 72, height: 72)
                Text("Welcome to PULSE").font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.textPrimary)
                Text("AI finds the moments. AI builds the first edit. You have total control.")
                    .font(.pulseBody).foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 30)
            .padding(.bottom, 22)

            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: step.symbol).font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(index == 2 ? Theme.ai : Theme.accent)
                                .frame(width: 24, height: 22, alignment: .leading)
                            Spacer()
                            Text("\(index + 1)").font(.pulseMono).foregroundStyle(Theme.textTertiary)
                        }
                        Text(step.title).font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
                        Text(step.detail).font(.pulseCaption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(width: 150, height: 170, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusLarge).fill(Theme.panelRaised))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).strokeBorder(Theme.border))
                }
            }
            .padding(.horizontal, 26)

            HStack(spacing: 8) {
                Image(systemName: "lock.shield").foregroundStyle(Theme.success)
                Text("Local-first: video and audio never leave your Mac. Cloud AI is optional and off by default.")
                    .font(.pulseCaption).foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 18)

            HStack(spacing: 10) {
                Button("Skip") { finish() }.buttonStyle(.pulse(.ghost))
                Spacer()
                Button { finish(); app.openDemoProject() } label: { Label("Open Sample Project", systemImage: "play.rectangle") }
                    .buttonStyle(.pulse(.secondary))
                Button { finish(); app.showImportPanel() } label: { Label("Import a Video", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.pulse(.primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(26)
        }
        .frame(width: 840)
        .background(Theme.panel)
    }

    func finish() {
        app.completeOnboarding()
        dismiss()
    }
}

// MARK: Recovery

/// Offered at launch when PULSE quit with unsaved changes.
struct RecoveryView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "lifepreserver").font(.system(size: 22)).foregroundStyle(Theme.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recovered Projects").font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
                    Text("PULSE quit before these changes were saved. Open a project to restore it, or discard the changes.")
                        .font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                }
            }
            ForEach(app.pendingRecoveries) { snapshot in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.document.name).font(.pulseBody.weight(.medium)).foregroundStyle(Theme.textPrimary)
                        Text("Unsaved changes from \(snapshot.savedAt.formatted(date: .abbreviated, time: .shortened)) · \(snapshot.document.timelines.count) timelines · \(snapshot.document.candidates.count) clips")
                            .font(.pulseCaption).foregroundStyle(Theme.textTertiary)
                        Text(snapshot.projectPath).font(.pulseMicro).foregroundStyle(Theme.textTertiary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button("Discard") { app.discardRecovery(snapshot) }.buttonStyle(.pulse(.ghost, compact: true))
                    Button("Open") { app.recover(snapshot) }.buttonStyle(.pulse(.primary, compact: true))
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.panelRaised))
            }
            HStack {
                Spacer()
                Button("Discard All") {
                    for snapshot in app.pendingRecoveries { app.discardRecovery(snapshot) }
                }
                .buttonStyle(.pulse(.secondary, compact: true))
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(Theme.panel)
    }
}

// MARK: Global search

/// ⌘F: search projects, clips, media, transcripts, captions, markers and timelines.
/// Understands "funny", "hype", "fail"… and timestamps like "42:17".
struct GlobalSearchView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    struct Row: Identifiable, Hashable {
        var id: String
        var result: SearchResult
        var otherProject: ProjectSummary?
    }

    var rows: [Row] {
        let session = app.session
        var rows = SearchEngine.search(query, projects: app.projects, document: session?.document, analyses: session?.analyses ?? [:])
            .map { Row(id: $0.id, result: $0, otherProject: nil) }
        // Transcripts of other (closed) projects come from the library's full-text index.
        if query.count >= 3, let library = app.library {
            let currentID = session?.document.id
            for hit in library.searchTranscripts(query, limit: 20) where hit.projectID != currentID {
                guard let project = app.projects.first(where: { $0.id == hit.projectID }) else { continue }
                let result = SearchResult(id: "lib-\(hit.projectID)-\(hit.assetID)-\(hit.start)", kind: .transcript, title: "“\(hit.text)”",
                                          subtitle: "\(project.name) · \(Timecode.short(hit.start))", time: hit.start,
                                          projectID: hit.projectID, assetID: hit.assetID, score: 0.5)
                rows.append(Row(id: result.id, result: result, otherProject: project))
            }
        }
        return rows
    }

    var body: some View {
        let rows = self.rows
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textTertiary)
                TextField("Search clips, transcripts, media… try “funny”, “hype” or 42:17", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($focused)
                    .onSubmit { if rows.indices.contains(highlighted) { open(rows[highlighted]) } }
                    .onChange(of: query) { _, _ in highlighted = 0 }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(14)
            Rectangle().fill(Theme.divider).frame(height: 1)
            if query.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Try")
                    HStack(spacing: 6) {
                        ForEach(["funny", "hype", "fail", "story", "42:17"], id: \.self) { s in
                            Button { query = s } label: { TagChip(text: s, color: Theme.ai, symbol: "sparkles") }.buttonStyle(.plain)
                        }
                    }
                    Text(app.session == nil ? "Open a project to search its clips, transcripts and captions." : "Searching “\(app.session?.document.name ?? "")” and all project names.")
                        .font(.pulseCaption).foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            } else if rows.isEmpty {
                Text("No results for “\(query)”").font(.pulseBody).foregroundStyle(Theme.textTertiary).padding(30)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                resultRow(row, highlighted: index == highlighted)
                                    .id(index)
                                    .onTapGesture { open(row) }
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: highlighted) { _, i in proxy.scrollTo(i) }
                }
                .frame(maxHeight: 420)
            }
        }
        .frame(width: 620)
        .background(Theme.panel)
        .onAppear { focused = true }
        .onExitCommand { dismiss() }
        .background(
            // Arrow keys move the highlight while the field keeps focus.
            Group {
                Button("") { highlighted = max(0, highlighted - 1) }.keyboardShortcut(.upArrow, modifiers: [])
                Button("") { highlighted = min(max(rows.count - 1, 0), highlighted + 1) }.keyboardShortcut(.downArrow, modifiers: [])
            }
            .opacity(0)
        )
    }

    func resultRow(_ row: Row, highlighted: Bool) -> some View {
        let r = row.result
        return HStack(spacing: 10) {
            Image(systemName: r.kind.symbolName)
                .frame(width: 22)
                .foregroundStyle(r.kind == .clip ? Theme.ai : Theme.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title).font(.pulseBody).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(r.subtitle).font(.pulseCaption).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            Spacer()
            Text(r.kind.displayName).font(.pulseMicro).foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(highlighted ? Theme.control : .clear))
        .contentShape(Rectangle())
    }

    func open(_ row: Row) {
        let r = row.result
        dismiss()
        if let other = row.otherProject {
            app.openProject(other)
        } else if r.kind == .project, let id = r.projectID, app.session?.document.id != id,
                  let summary = app.projects.first(where: { $0.id == id }) {
            app.openProject(summary)
            return
        }
        guard let session = app.session else { return }
        switch r.kind {
        case .project:
            break
        case .clip:
            if let id = r.candidateID {
                session.selectedCandidateIDs = [id]
                app.section = .aiClips
            }
        case .media:
            app.section = .media
        case .transcript:
            if let assetID = r.assetID, let time = r.time { session.reveal(sourceTime: time, assetID: assetID) }
        case .marker:
            if let id = r.timelineID { session.open(timelineID: id, at: r.time) }
        case .caption:
            if let id = r.timelineID { session.open(timelineID: id, section: .captions) }
        case .timeline:
            if let id = r.timelineID { session.open(timelineID: id) }
        }
    }
}
