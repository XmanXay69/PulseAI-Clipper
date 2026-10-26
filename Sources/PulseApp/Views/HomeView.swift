import PulseCore
import PulseEngine
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var app: AppModel
    @AppStorage("home.tips") private var showTips = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                heroBanner
                if showTips { tipOfTheDay }
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

    /// The welcome: headline, the two things people come here to do, on a softly lit surface.
    var heroBanner: some View {
        VStack(alignment: .leading, spacing: 18) {
            hero
            startHere
        }
        .padding(22)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusXL).fill(Theme.panelRaised)
                RoundedRectangle(cornerRadius: Theme.radiusXL)
                    .fill(RadialGradient(colors: [Theme.accent.opacity(0.2), .clear], center: .topLeading, startRadius: 0, endRadius: 560))
                RoundedRectangle(cornerRadius: Theme.radiusXL)
                    .fill(RadialGradient(colors: [Theme.ai.opacity(0.2), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 620))
            }
        )
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusXL).strokeBorder(Theme.border))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusXL).strokeBorder(Theme.edgeHighlight, lineWidth: 1))
        .elevation(3)
    }

    var hero: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Turn long streams into shorts and YouTube videos.")
                    .font(.pulseDisplay)
                    .tracking(-0.3)
                    .foregroundStyle(Theme.textPrimary)
                Text("Drop in a VOD, podcast or gameplay recording. PULSE finds the moments and builds the edit — vertical shorts or a full YouTube video — and you stay in full control.")
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

    /// The two things people come here to do, front and center.
    var startHere: some View {
        HStack(spacing: 14) {
            StartCard(symbol: "rectangle.portrait.on.rectangle.portrait.angled", title: "Make Shorts",
                      subtitle: "Find the best moments and get captioned 9:16 clips for TikTok, Shorts and Reels.",
                      step: app.session?.document.primaryAsset == nil ? "Import a video" : "Find clips", color: Theme.accent) {
                if let session = app.session, let asset = session.document.primaryAsset {
                    if session.document.visibleCandidates.isEmpty { session.generateCandidates(assetID: asset.id) } else { app.section = .aiClips }
                } else {
                    app.showImportPanel()
                }
            }
            StartCard(symbol: "film.stack", title: "Make a YouTube Video",
                      subtitle: "Cut the whole stream to 10–20 minutes with a hook, zooms, captions, memes, music and sound effects.",
                      step: app.session?.document.primaryAsset == nil ? "Import a video" : "Edit My VOD", color: Theme.ai) {
                if app.session?.document.primaryAsset != nil { app.showLongFormSheet = true } else { app.showImportPanel() }
            }
        }
    }

    /// One tip a day (#450).
    var tipOfTheDay: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb").foregroundStyle(Theme.warning)
            Text(HomeTips.tip()).font(.pulseCaption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Don't show tips") { showTips = false }.buttonStyle(.pulse(.ghost, compact: true))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Theme.radiusLarge).fill(Theme.panelRaised))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).strokeBorder(Theme.border))
    }

    var quickActions: some View {
        // Wraps onto a second row in narrower windows instead of squeezing the tiles.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
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
            QuickActionTile(symbol: "record.circle", title: "Record", subtitle: "Screen + webcam + mic", color: Theme.danger) {
                app.showRecordSheet = true
            }
            QuickActionTile(symbol: "sparkles.rectangle.stack", title: "Shorts + YouTube Video", subtitle: "Whole VOD, one click", color: Theme.ai) {
                app.runFullPipeline()
            }
            QuickActionTile(symbol: "moon.stars", title: "Overnight Batch", subtitle: "Queue several VODs", color: Theme.success) {
                app.showBatchSheet = true
            }
            QuickActionTile(symbol: "wand.and.stars", title: "Like a Reference", subtitle: "Copy an edit you love", color: Theme.ai) {
                app.showReferenceSheet = true
            }
            QuickActionTile(symbol: "slider.horizontal.3", title: "Set Up for My Stream", subtitle: app.settings.streamSetup == nil ? "Six questions, twenty settings" : "Change your answers", color: Theme.info) {
                app.showSetupWizard = true
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
                    RunningJobLine(job: job)
                }
                if app.activity.isEmpty && app.jobs.running.isEmpty {
                    Text("Transcription, clip generation, captions, rendering and exports will show up here.")
                        .font(.pulseCaption).foregroundStyle(Theme.textTertiary)
                }
                let recent = Array(app.activity.prefix(7))
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, record in
                    if index == 0 || !Calendar.current.isDate(record.date, inSameDayAs: recent[index - 1].date) {
                        Text(Calendar.current.isDateInToday(record.date) ? "Today" : (Calendar.current.isDateInYesterday(record.date) ? "Yesterday" : record.date.formatted(date: .abbreviated, time: .omitted)))
                            .font(.pulseMicro).foregroundStyle(Theme.textTertiary).textCase(.uppercase).padding(.top, index == 0 ? 0 : 4)
                    }
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

struct StartCard: View {
    let symbol: String
    let title: String
    let subtitle: String
    let step: String
    let color: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 54, height: 54)
                    .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.15)))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 4) {
                        Text(step).font(.system(size: 12, weight: .semibold))
                        Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(color)
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [color.opacity(hovering ? 0.2 : 0.12), Theme.panel.opacity(0.85)],
                                                                                startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(LinearGradient(colors: [color.opacity(hovering ? 0.9 : 0.55), color.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: 1))
            .shadow(color: color.opacity(hovering ? 0.28 : 0.12), radius: hovering ? 18 : 10, y: 6)
            .offset(y: hovering ? -2 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
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
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 9).fill(LinearGradient(colors: [color.opacity(0.3), color.opacity(0.08)],
                                                                                        startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(color.opacity(0.25)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(subtitle).font(.pulseCaption).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .raisedSurface(fill: hovering ? Theme.elevated : Theme.panelRaised, border: hovering ? color.opacity(0.5) : Theme.border)
            .elevation(hovering ? 2 : 1)
            .offset(y: hovering ? -2 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
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
                HStack(spacing: 8) {
                    Text("Edited \(project.modifiedAt.formatted(.relative(presentation: .named)))").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                    if let editing = project.editingSeconds, editing >= 60 {
                        Text("· \(Timecode.duration(editing)) at it").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                            .help("Time spent editing this project with PULSE in front (#477)")
                    }
                    if let deadline = project.deadline, project.status != .exported {
                        let overdue = deadline < Date()
                        TagChip(text: overdue ? "Overdue" : "Due \(deadline.formatted(.relative(presentation: .named)))",
                                color: overdue ? Theme.danger : (deadline.timeIntervalSinceNow < 2 * 86400 ? Theme.warning : Theme.info), symbol: "calendar")
                    }
                }
            }
            .padding(10)
        }
        .background(RoundedRectangle(cornerRadius: Theme.radiusLarge).fill(Theme.panelRaised))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).strokeBorder(hovering ? Theme.borderStrong : Theme.border))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).strokeBorder(Theme.edgeHighlight, lineWidth: 1))
        .elevation(hovering ? 2 : 1)
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
            Button("Archive with Media…") { app.archiveProject(project) }
            Menu("Deadline") {
                Button("Tomorrow") { app.setDeadline(project, Calendar.current.date(byAdding: .day, value: 1, to: Date())) }
                Button("In 3 days") { app.setDeadline(project, Calendar.current.date(byAdding: .day, value: 3, to: Date())) }
                Button("In a week") { app.setDeadline(project, Calendar.current.date(byAdding: .day, value: 7, to: Date())) }
                Button("In two weeks") { app.setDeadline(project, Calendar.current.date(byAdding: .day, value: 14, to: Date())) }
                if project.deadline != nil {
                    Divider()
                    Button("Clear Deadline") { app.setDeadline(project, nil) }
                }
            }
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

/// One running job in the AI Activity card: ring, title, time left.
struct RunningJobLine: View {
    @ObservedObject var job: BackgroundJob

    var body: some View {
        HStack(spacing: 8) {
            ProgressRing(progress: job.progress, size: 14, color: Theme.ai)
            Text(job.title).font(.pulseCaption).foregroundStyle(Theme.textPrimary).lineLimit(1)
            Spacer()
            Text(job.remainingText ?? "\(Int(job.progress * 100))%").font(.pulseMono).foregroundStyle(Theme.textTertiary)
        }
    }
}
