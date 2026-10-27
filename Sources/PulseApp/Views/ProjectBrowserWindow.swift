import AppKit
import PulseCore
import SwiftUI
import UniformTypeIdentifiers

/// Another project beside the one you're editing (#468): its media and timelines in a window of their own.
/// Drag a file onto the main window to import it, or use the buttons to copy media or a whole timeline into
/// the current project. The other project is read, never changed.
struct ProjectBrowserWindow: View {
    @EnvironmentObject var app: AppModel
    let url: URL?
    @State private var document: ProjectDocument?
    @State private var problem: String?

    var body: some View {
        Group {
            if let document {
                content(document)
            } else if let problem {
                Text(problem).font(.pulseBody).foregroundStyle(Theme.textSecondary).padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if url == nil {
                Text("Window → Open Another Project in a Browser Window… picks the project to show here.")
                    .font(.pulseBody).foregroundStyle(Theme.textSecondary).padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                BusyLine("Opening project")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.panel)
        .task(id: url) { await load() }
    }

    @ViewBuilder
    private func content(_ document: ProjectDocument) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "folder").foregroundStyle(Theme.accent)
                Text(document.name).font(.pulseTitle)
                Spacer()
                Text("\(document.media.filter { !$0.isTrashed }.count) media · \(document.timelines.count) timelines")
                    .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            }
            .padding(14)
            Divider()
            List {
                Section("Media — drag onto the main window, or copy") {
                    ForEach(document.media.filter { !$0.isTrashed }) { asset in
                        mediaRow(asset)
                    }
                }
                Section("Timelines") {
                    ForEach(document.timelines) { timeline in
                        timelineRow(timeline, from: document)
                    }
                }
            }
            .listStyle(.inset)
            Divider()
            Text(app.session.map { "Copies go into “\($0.document.name)”." } ?? "Open a project in the main window to copy into it.")
                .font(.pulseMicro).foregroundStyle(Theme.textTertiary).padding(10)
        }
    }

    private func mediaRow(_ asset: MediaAsset) -> some View {
        let fileURL = MediaAccess.resolve(asset)
        return HStack(spacing: 8) {
            Image(systemName: asset.role.symbolName).foregroundStyle(Theme.textSecondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.name).font(.pulseBody).lineLimit(1)
                Text("\(asset.kind.displayName) · \(Timecode.short(asset.metadata.duration))").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Button("Copy") { app.importMedia([fileURL]) }
                .buttonStyle(.pulse(.ghost, compact: true))
                .disabled(app.session == nil)
                .help("Import this file into the project in the main window")
        }
        .onDrag { NSItemProvider(object: fileURL as NSURL) }
    }

    private func timelineRow(_ timeline: Timeline, from other: ProjectDocument) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "film.stack").foregroundStyle(Theme.textSecondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(timeline.name).font(.pulseBody).lineLimit(1)
                Text("\(Timecode.short(timeline.duration)) · \(timeline.allClips.count) clips").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Button("Copy Timeline") { copy(timeline, from: other) }
                .buttonStyle(.pulse(.ghost, compact: true))
                .disabled(app.session == nil)
                .help("Add this timeline and the media it uses to the project in the main window")
        }
    }

    /// The timeline, with a fresh id, plus any of its media the current project doesn't have yet.
    private func copy(_ timeline: Timeline, from other: ProjectDocument) {
        guard let session = app.session else { return }
        var copied = timeline
        copied.id = UUID()
        copied.name = timeline.name + " (from \(other.name))"
        let needed = other.media.filter { timeline.assetIDs.contains($0.id) && !session.document.media.contains(where: { $0.id == timeline.id }) }
        session.edit("Copy Timeline from \(other.name)") { doc in
            doc.media.append(contentsOf: needed.filter { a in !doc.media.contains { $0.id == a.id } })
            doc.timelines.append(copied)
            doc.activeTimelineID = copied.id
        }
        session.open(timelineID: copied.id)
        app.toast("“\(timeline.name)” copied with \(needed.count) media file\(needed.count == 1 ? "" : "s")")
    }

    private func load() async {
        guard let url else { return }
        do {
            let (loaded, _) = try app.store.load(ProjectPackage(url: url))
            document = loaded
        } catch {
            problem = "Couldn't open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}

/// Window → Open Another Project in a Browser Window… (#468).
struct OpenProjectBrowserButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(L("Open Another Project in a Browser Window…")) {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [UTType(filenameExtension: ProjectPackage.fileExtension) ?? .package]
            panel.treatsFilePackagesAsDirectories = false
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.message = "Pick a project to browse beside the one you're editing"
            if panel.runModal() == .OK, let url = panel.url { openWindow(id: "browser", value: url) }
        }
    }
}
