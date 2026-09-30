import PulseCore
import PulseEngine
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                quickActions
                HStack(alignment: .top, spacing: 18) {
                    recentProjects.frame(maxWidth: .infinity)
                    VStack(spacing: 18) {
                        activityCard
                        storageCard
                    }
                    .frame(width: 330)
                }
            }
            .padding(24)
        }
        .onAppear {
            app.refreshProjects()
            app.refreshActivity()
            app.refreshDiskInfo()
        }
    }

    var hero: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Turn long streams into shorts.")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Drop in a VOD, podcast or gameplay recording. PULSE finds the moments, builds captioned 9:16 edits — and you stay in full control.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: 560, alignment: .leading)
            }
            Spacer()
            HStack(spacing: 6) {
                ProcessingBadge(location: .local)
                Text("Runs on your Mac").font(.pulseCaption).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    var quickActions: some View {
        HStack(spacing: 12) {
            QuickActionTile(symbol: "plus.rectangle.on.folder", title: "New Project", subtitle: "Start from scratch", color: Theme.accent) {
                app.showNewProjectSheet = true
            }
            QuickActionTile(symbol: "square.and.arrow.down", title: "Import Video", subtitle: "MP4, MOV, MKV, WebM", color: Theme.info) {
                app.showImportPanel()
            }
            QuickActionTile(symbol: "sparkles", title: "Generate AI Clips", subtitle: app.session == nil ? "Open a project first" : "Find the best moments", color: Theme.ai) {
                if let session = app.session, let asset = session.document.primaryAsset {
                    session.generateCandidates(assetID: asset.id)
                } else {
                    app.showImportPanel()
                }
            }
            QuickActionTile(symbol: "folder", title: "Open Project", subtitle: "Browse .pulse projects", color: Theme.success) {
                app.showOpenPanel()
            }
            QuickActionTile(symbol: "play.rectangle.on.rectangle", title: "Sample Project", subtitle: "See PULSE in action", color: Theme.warning) {
                app.openDemoProject()
            }
        }
    }

    var recentProjects: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Projects").font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("View all") { app.section = .projects }.buttonStyle(.pulse(.ghost, compact: true))
            }
            if app.projects.isEmpty {
                Card {
                    EmptyStateView(symbol: "film.stack", title: "No projects yet",
                                   message: "Import a long recording or open the sample project to see how PULSE finds clips.",
                                   actionTitle: "Open Sample Project") { app.openDemoProject() }
                        .frame(height: 260)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14)], spacing: 14) {
                    ForEach(app.projects.prefix(8)) { project in
                        ProjectCard(project: project)
                    }
                }
            }
        }
    }

    var activityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("AI Activity").font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "sparkles").foregroundStyle(Theme.ai)
                }
                ForEach(app.jobs.running) { job in
                    HStack(spacing: 8) {
                        ProgressRing(progress: job.progress, size: 14, color: Theme.ai)
                        Text(job.title).font(.pulseCaption).foregroundStyle(Theme.textPrimary).lineLimit(1)
                        Spacer()
                        Text("\(Int(job.progress * 100))%").font(.pulseMono).foregroundStyle(Theme.textTertiary)
                    }
                }
                if app.activity.isEmpty && app.jobs.running.isEmpty {
                    Text("Transcription, clip generation, captions, rendering and exports will show up here.")
                        .font(.pulseCaption).foregroundStyle(Theme.textTertiary)
                }
                ForEach(app.activity.prefix(7)) { record in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: record.kind.symbolName).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(record.title).font(.pulseCaption).foregroundStyle(Theme.textPrimary).lineLimit(1)
                            Text("\(record.kind.displayName) · \(record.date.formatted(.relative(presentation: .named)))")
                                .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                        ProcessingBadge(location: record.location)
                    }
                }
            }
        }
    }

    var storageCard: some View {
        let info = app.diskInfo
        let f = ByteCountFormatter()
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Storage").font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button("Clear Cache") { app.clearCache() }.buttonStyle(.pulse(.ghost, compact: true))
                }
                if info.totalBytes > 0 {
                    let used = Double(info.totalBytes - info.availableBytes) / Double(info.totalBytes)
                    ThinProgressBar(progress: used, color: used > 0.9 ? Theme.danger : Theme.info)
                    Text("\(f.string(fromByteCount: info.availableBytes)) available of \(f.string(fromByteCount: info.totalBytes))")
                        .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                }
                KeyValueRow(key: "Projects", value: f.string(fromByteCount: info.projectsBytes))
                KeyValueRow(key: "Media (referenced)", value: f.string(fromByteCount: info.mediaBytes))
                KeyValueRow(key: "Cache (proxies, thumbnails)", value: f.string(fromByteCount: info.cacheBytes))
            }
        }
    }
}

struct QuickActionTile: View {
    let symbol: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(subtitle).font(.pulseCaption).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.radiusLarge).fill(hovering ? Theme.control : Theme.panelRaised))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).strokeBorder(hovering ? color.opacity(0.5) : Theme.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct ProjectCard: View {
    @EnvironmentObject var app: AppModel
    let project: ProjectSummary
    @State private var hovering = false
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Rectangle().fill(Theme.well)
                    if let thumb = project.thumbnailPath, let image = NSImage(contentsOfFile: thumb) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "film").font(.system(size: 22)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(height: 124)
                .clipped()
                HStack(spacing: 4) {
                    if project.isFavorite { Image(systemName: "star.fill").foregroundStyle(Theme.warning) }
                    TagChip(text: project.status.displayName, color: statusColor)
                }
                .font(.system(size: 10))
                .padding(8)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(project.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                HStack(spacing: 10) {
                    Label(Timecode.duration(project.duration), systemImage: "clock")
                    Label(project.resolution, systemImage: "rectangle.on.rectangle")
                    Label("\(project.clipCount)", systemImage: "sparkles")
                }
                .labelStyle(CompactLabelStyle())
                Text("Edited \(project.modifiedAt.formatted(.relative(presentation: .named)))").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            }
            .padding(10)
        }
        .background(RoundedRectangle(cornerRadius: Theme.radiusLarge).fill(Theme.panelRaised))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).strokeBorder(hovering ? Theme.borderStrong : Theme.border))
        .scaleEffect(hovering ? 1.01 : 1)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        .onTapGesture { app.openProject(project) }
        .contextMenu {
            Button("Open") { app.openProject(project) }
            Button("Rename…") { newName = project.name; renaming = true }
            Button("Duplicate") { app.duplicateProject(project) }
            Button(project.isFavorite ? "Remove from Favorites" : "Add to Favorites") { app.setFavorite(project, !project.isFavorite) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.path)]) }
            Divider()
            if project.isTrashed {
                Button("Restore") { app.setTrashed(project, false) }
                Button("Delete Permanently…", role: .destructive) { app.deleteProjectPermanently(project) }
            } else {
                Button("Move to Trash", role: .destructive) { app.setTrashed(project, true) }
            }
        }
        .alert("Rename Project", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Rename") { app.renameProject(project, to: newName) }
            Button("Cancel", role: .cancel) {}
        }
    }

    var statusColor: Color {
        switch project.status {
        case .clipsReady: return Theme.ai
        case .exported: return Theme.success
        case .editing: return Theme.info
        case .analyzing: return Theme.warning
        default: return Theme.textSecondary
        }
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 9))
            configuration.title
        }
        .font(.pulseCaption)
        .foregroundStyle(Theme.textSecondary)
    }
}
