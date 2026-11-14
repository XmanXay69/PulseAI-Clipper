import AppKit
import Foundation
import PulseCore
import UniformTypeIdentifiers

extension ProjectSession {
    // MARK: Posting plan (#906)

    /// What there is to post: every edit in the project (long video or short, by the rule the coach and the
    /// export presets use), and, when asked, the clip cards worth turning into shorts that haven't been yet.
    func postingItems(includeCards: Bool) -> [PostingItem] {
        var items: [PostingItem] = []
        for timeline in document.timelines where timeline.duration > 1 {
            let card = document.candidates.first { $0.timelineID == timeline.id }
            let isLong = EditFormat.of(timeline) == .longForm
            var assetID = card?.assetID
            if assetID == nil {
                for clip in timeline.allClips {
                    if case .media(let id) = clip.content, document.asset(id: id)?.kind == .video { assetID = id; break }
                }
            }
            items.append(PostingItem(id: timeline.id, title: timeline.name, isLong: isLong, potential: card?.potential ?? 50,
                                     source: isLong ? nil : card?.range, assetID: assetID, isBuilt: true))
        }
        if includeCards {
            for card in document.candidates where card.timelineID == nil && card.status == .new && card.preliminary != true
                && (card.isFavorite || card.potential >= 70) {
                items.append(PostingItem(id: card.id, title: card.title, potential: card.potential, source: card.range,
                                         assetID: card.assetID, isBuilt: false))
            }
        }
        return items
    }

    // MARK: Review comments (#1181)

    /// Timeline → Export Watch-and-Comment Page: one HTML file next to the exported video, to send with it.
    func exportCommentPage() {
        guard let timeline = activeTimeline else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.message = "Choose the exported video of “\(timeline.name)”. The page is saved next to it; send both."
        panel.prompt = "Make Page"
        // Start where this edit was last exported to, when that file is still there.
        let last = app.exports.jobs.filter { $0.timelineID == timeline.id }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
            .compactMap(\.outputPath).first { FileManager.default.fileExists(atPath: $0) }
        if let last {
            panel.directoryURL = URL(fileURLWithPath: last).deletingLastPathComponent()
            panel.nameFieldStringValue = (last as NSString).lastPathComponent
        }
        guard panel.runModal() == .OK, let video = panel.url else { return }
        let page = video.deletingLastPathComponent().appendingPathComponent(ReviewComments.pageName(forVideo: video.lastPathComponent))
        let html = ReviewComments.page(timeline: timeline, projectName: document.name, videoFileName: video.lastPathComponent)
        do {
            try html.write(to: page, atomically: true, encoding: .utf8)
            app.logActivity(.export, title: "Watch-and-comment page for “\(timeline.name)”", detail: page.lastPathComponent)
            app.toast("Saved \(page.lastPathComponent) next to the video. Send both; comments come back with Import Review Comments.")
            NSWorkspace.shared.activateFileViewerSelecting([page, video])
        } catch {
            app.present(error, title: "Couldn't write the page")
        }
    }

    /// Timeline → Import Review Comments: the page's comments file, or any text with timecodes.
    func importReviewComments() {
        guard let timeline = activeTimeline else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .plainText, .text]
        panel.message = "Choose the comments file a reviewer sent back for “\(timeline.name)”, or a text file of notes with timecodes"
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .utf16)) else {
            app.presentMessage(title: "That file couldn't be read", message: "PULSE reads the comments file the review page saves, and plain text.")
            return
        }
        addReviewComments(from: text, source: url.lastPathComponent)
    }

    /// Timeline → Paste Review Comments: what a reviewer pasted into a message, from the clipboard.
    func pasteReviewComments() {
        guard activeTimeline != nil else { return }
        guard let text = NSPasteboard.general.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            app.toast("Copy the reviewer's comments first, then choose this again")
            return
        }
        addReviewComments(from: text, source: "the clipboard")
    }

    private func addReviewComments(from text: String, source: String) {
        guard let timeline = activeTimeline else { return }
        let notes = ReviewComments.parse(text, frameRate: timeline.canvas.frameRate)
        guard !notes.comments.isEmpty else {
            app.presentMessage(title: "No comments with a timecode",
                               message: "PULSE looked in \(source) for the review page's comments, or for lines that start with a time, like “0:42 the music is too loud here”, and found none.")
            return
        }
        var report = ReviewComments.Report(added: 0, repeated: 0, pastEnd: 0, warning: nil)
        editTimeline("Add Review Comments") { report = ReviewComments.apply(notes, to: &$0) }
        app.toast(report.summary)
        if report.added > 0 {
            let who = notes.reviewer.isEmpty ? "" : " from \(notes.reviewer)"
            app.logActivity(.importMedia, title: "\(report.added) review comment\(report.added == 1 ? "" : "s")\(who) on “\(timeline.name)”", detail: report.warning ?? "As orange markers")
        }
    }
}
