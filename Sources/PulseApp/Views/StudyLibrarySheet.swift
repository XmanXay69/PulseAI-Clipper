import AppKit
import PulseCore
import SwiftUI

/// The study library: per genre, the videos about editing it, which have been studied, and the rules they
/// agree on. Studying downloads a video, measures it, asks the language model what it teaches, and deletes
/// the download.
struct StudyLibrarySheet: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var library: StudyLibraryController
    @State private var genre: VideoGenre = .gamingVideo
    @State private var link = ""

    var videos: [LibraryVideo] { library.library.videos(in: genre) }
    var waiting: Int { library.library.count(in: genre, state: .queued) }
    var studied: Int { library.library.count(in: genre, state: .studied) }
    var failed: Int { library.library.count(in: genre, state: .failed) }
    var waitingEverywhere: Int { library.library.videos.filter { $0.state == .queued }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader("Study Library", symbol: "books.vertical",
                        subtitle: "The most-watched videos about editing each kind of video. PULSE fetches one, studies it, deletes the download and keeps what it taught.")
            Divider().overlay(Theme.divider)
            genreBar
            Divider().overlay(Theme.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if library.isBusy { progressCard }
                    if let problem = library.problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill").font(.pulseCaption).foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    learnedCard
                    listHeader
                    LazyVStack(spacing: 4) {
                        ForEach(videos) { video in row(video) }
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().overlay(Theme.divider)
            footer
        }
        .frame(width: 780, height: 700)
        .background(Theme.panel)
        .preferredColorScheme(AppModel.current?.colorScheme)
        .onAppear { if let project = app.session?.document.genre { genre = project } }
    }

    // MARK: Genres

    /// Every genre in view at once: four to a row, like the genre buttons in Edit My VOD.
    var genreBar: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(VideoGenre.allCases, id: \.self) { item in genreButton(item) }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    func genreButton(_ item: VideoGenre) -> some View {
        let total = library.library.count(in: item)
        let done = library.library.count(in: item, state: .studied)
        let selected = genre == item
        return Button { genre = item } label: {
            HStack(spacing: 6) {
                Image(systemName: item.symbol).font(.system(size: 11))
                Text(item.displayName).font(.pulseCaption).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                Text("\(done)/\(total)").font(.pulseMicro).foregroundStyle(selected ? Theme.textSecondary : Theme.textTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
            .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(selected ? Theme.accent.opacity(0.18) : Theme.panelRaised))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(item.blurb) \(done) of \(total) studied.")
    }

    // MARK: Progress and what was learned

    var progressCard: some View {
        HStack(spacing: 10) {
            if library.isStudying {
                ProgressView(value: library.progress).frame(width: 120)
            } else {
                ProgressView().controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(library.status).font(.pulseCaption).foregroundStyle(Theme.textPrimary).lineLimit(1)
                if !library.detail.isEmpty {
                    Text(library.detail).font(.pulseMicro).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
        }
        .card(padding: 12)
    }

    @ViewBuilder var learnedCard: some View {
        if let learned = library.library.knowledge(for: genre) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "What the videos in “\(genre.displayName)” agree on")
                VStack(alignment: .leading, spacing: 10) {
                    if !learned.summary.isEmpty {
                        Text(learned.summary).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(learned.rules) { rule in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: rule.topic.symbol).font(.system(size: 12)).foregroundStyle(Theme.ai).frame(width: 18).padding(.top, 1)
                                .help(rule.topic.displayName)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.rule).font(.system(size: 12)).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                                Text(support(rule, of: learned.videoCount)).font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    Text("Merged by \(learned.writtenBy) from the rules drawn out of \(learned.videoCount) video\(learned.videoCount == 1 ? "" : "s"). The model read what was said, the text on the frames and PULSE's measurements; it did not see the picture or hear the sound. Plan with the model follows the rules about openings, pacing and story in a project of this genre. The automatic editor's own numbers are not changed by this.")
                        .font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                }
                .card(padding: 14)
            }
        }
    }

    func support(_ rule: GenreKnowledge.Rule, of total: Int) -> String {
        var text = "Taught by \(rule.support) of \(total) video\(total == 1 ? "" : "s")"
        if !rule.sources.isEmpty { text += ": " + rule.sources.joined(separator: "; ") }
        return text
    }

    // MARK: The videos

    var listHeader: some View {
        HStack(spacing: 8) {
            SectionLabel(text: summary)
            Spacer(minLength: 8)
            if failed > 0, !library.isBusy {
                Button("Try Those Again") { library.retryFailed(in: genre) }
                    .buttonStyle(.pulse(.ghost, compact: true))
                    .help("Puts the videos that couldn't be studied back in the queue")
            }
        }
    }

    var summary: String {
        var parts = ["\(videos.count) video\(videos.count == 1 ? "" : "s")"]
        if studied > 0 { parts.append("\(studied) studied") }
        if waiting > 0 { parts.append("\(waiting) waiting") }
        if failed > 0 { parts.append("\(failed) couldn't be studied") }
        return parts.joined(separator: " · ")
    }

    func row(_ video: LibraryVideo) -> some View {
        let isCurrent = library.currentID == video.videoID
        return HStack(alignment: .top, spacing: 10) {
            stateIcon(video, isCurrent: isCurrent).frame(width: 18).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(video.title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(caption(video)).font(.pulseMicro).foregroundStyle(Theme.textTertiary).lineLimit(1)
                if isCurrent, !library.detail.isEmpty {
                    Text(library.detail).font(.pulseMicro).foregroundStyle(Theme.ai).lineLimit(1)
                } else if let failure = video.failure {
                    Text(failure).font(.pulseMicro).foregroundStyle(Theme.warning).lineLimit(2)
                } else if let lessons = video.lessons, !lessons.summary.isEmpty {
                    Text(lessons.summary).font(.pulseMicro).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let lessons = video.lessons {
                TagChip(text: "\(lessons.lessons.count) rule\(lessons.lessons.count == 1 ? "" : "s")", color: Theme.success)
            }
            Menu {
                Button("Open on YouTube") { NSWorkspace.shared.open(video.url) }
                Button("Remove from the Library") { library.remove(video) }.disabled(isCurrent)
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(Theme.textTertiary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.panelRaised))
    }

    @ViewBuilder func stateIcon(_ video: LibraryVideo, isCurrent: Bool) -> some View {
        if isCurrent {
            ProgressView().controlSize(.small)
        } else {
            switch video.state {
            case .studied:
                Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(Theme.success).help("Studied; the download is deleted")
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(Theme.warning).help("Couldn't be studied")
            case .queued:
                Image(systemName: "circle").font(.system(size: 13)).foregroundStyle(Theme.textTertiary).help("Waiting to be studied")
            }
        }
    }

    func caption(_ video: LibraryVideo) -> String {
        var parts: [String] = []
        if !video.channel.isEmpty { parts.append(video.channel) }
        if let views = video.viewsText { parts.append(views) }
        if let duration = video.duration { parts.append(Timecode.short(duration)) }
        switch video.origin {
        case .shipped: break
        case .found: parts.append("found by a search on this Mac")
        case .added: parts.append("added by you")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Footer

    var footer: some View {
        HStack(spacing: 8) {
            TextField("Paste a YouTube link to add it", text: $link)
                .textFieldStyle(.roundedBorder)
                .frame(width: 210)
                .onSubmit { addLink() }
            Button("Add") { addLink() }
                .buttonStyle(.pulse(.ghost, compact: true))
                .disabled(YouTubeURL.videoID(from: link) == nil)
            Button("Find More") { library.findTop(for: genre) }
                .buttonStyle(.pulse(.secondary, compact: true))
                .disabled(library.isBusy)
                .help("Searches YouTube from this Mac for the most-watched videos that teach this kind of editing, until “\(genre.displayName)” holds \(StudyLibrary.perGenre)")
            Spacer(minLength: 8)
            Button("Close") { app.showStudyLibrary = false }.buttonStyle(.pulseSecondary)
            if library.isStudying {
                Button("Stop") { library.stop() }
                    .buttonStyle(.pulseSecondary)
                    .help("Stops after the video being studied. What is done stays done.")
            } else {
                Menu {
                    Button("Study Every Genre (\(waitingEverywhere) waiting)") { library.study(nil) }.disabled(waitingEverywhere == 0)
                    Button("Merge What These Teach Again") { library.merge(genre) }.disabled(studied == 0)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 28)
                .disabled(library.isBusy)
                Button { library.study(genre) } label: {
                    Label(waiting > 0 ? "Study \(waiting) Video\(waiting == 1 ? "" : "s")" : "All Studied", systemImage: "graduationcap")
                }
                .buttonStyle(.pulsePrimary)
                .disabled(waiting == 0 || library.isBusy)
                .help("Downloads each waiting video, measures it, asks the language model what it teaches, and deletes the download")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    func addLink() {
        if library.add(link: link, to: genre) { link = "" }
    }
}
