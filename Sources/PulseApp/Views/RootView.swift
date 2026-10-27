import PulseCore
import PulseEngine
import SwiftUI
import UniformTypeIdentifiers

/// Main window: collapsible sidebar + top bar + section content, plus global sheets and toasts.
struct RootView: View {
    @EnvironmentObject var app: AppModel
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            Rectangle().fill(Theme.divider).frame(width: 1)
            VStack(spacing: 0) {
                TopBar()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.window)
                if app.session != nil { PageBar() }
            }
        }
        .background(Theme.window)
        .overlay(alignment: .bottom) { ToastView() }
        .overlay(alignment: .top) { RecordingHUD(recorder: app.recording) }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .background(Theme.accent.opacity(0.06))
                    .overlay(Label("Drop to import into \(app.session?.document.name ?? "a new project")", systemImage: "square.and.arrow.down")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            loadURLs(from: providers) { urls in app.importMedia(urls) }
            return true
        }
        .alert(item: $app.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $app.showOnboarding) { OnboardingView().environmentObject(app) }
        .sheet(isPresented: $app.showNewProjectSheet) { NewProjectSheet().environmentObject(app) }
        .sheet(isPresented: $app.showGlobalSearch) { GlobalSearchView().environmentObject(app) }
        .sheet(isPresented: $app.showRecordSheet) { RecordView(recorder: app.recording).environmentObject(app) }
        .sheet(isPresented: $app.showReportProblem) { ReportProblemSheet().environmentObject(app) }
        .sheet(isPresented: $app.showBatchSheet) { BatchSheet(batch: app.batch).environmentObject(app) }
        .sheet(isPresented: $app.showImportURLSheet) { ImportURLSheet().environmentObject(app) }
        .onPasteCommand(of: [UTType.plainText, UTType.url]) { _ in
            // Paste a YouTube link anywhere outside a text field to fetch the VOD (#467).
            if let text = NSPasteboard.general.string(forType: .string) { app.importPastedText(text) }
        }
        .sheet(isPresented: Binding(get: { app.updater.showSheet }, set: { app.updater.showSheet = $0 })) { UpdateSheet(updater: app.updater) }
        .sheet(isPresented: $app.showReferenceSheet) { ReferenceSheet(reference: app.reference).environmentObject(app) }
        .sheet(isPresented: $app.showSetupWizard) { SetupWizardSheet().environmentObject(app) }
        .sheet(item: $app.thumbnailRequest) { request in
            if let session = app.session { ThumbnailSheet(session: session, request: request).environmentObject(app) }
        }
        .sheet(isPresented: $app.showLongFormSheet) {
            if let session = app.session { LongFormSheet(session: session).environmentObject(app) }
        }
        .sheet(isPresented: Binding(get: { !app.pendingRecoveries.isEmpty && !app.showOnboarding }, set: { _ in })) {
            RecoveryView().environmentObject(app)
        }
    }

    @ViewBuilder
    var content: some View {
        switch app.section {
        case .home: HomeView()
        case .projects: ProjectsView()
        case .importMedia: ImportView()
        case .settings: SettingsView()
        case .templates: TemplatesView()
        case .exports: ExportsView()
        case .aiClips, .editor, .captions, .media:
            if let session = app.session {
                switch app.section {
                case .aiClips: AIClipsView(session: session)
                case .editor: EditorView(session: session)
                case .captions: CaptionsWorkspace(session: session)
                default: MediaView(session: session)
                }
            } else {
                EmptyStateView(symbol: "folder.badge.plus", title: "No project open",
                               message: "Create a project or drop a long video anywhere in this window to get started.",
                               actionTitle: "New Project") { app.showNewProjectSheet = true }
            }
        }
    }
}

/// Loads file URLs from drag providers.
func loadURLs(from providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
    let group = DispatchGroup()
    let collector = URLCollector()
    for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url { collector.append(url) }
            group.leave()
        }
    }
    group.notify(queue: .main) {
        let urls = collector.urls
        MainActor.assumeIsolated { completion(urls) }
    }
}

final class URLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []
    func append(_ url: URL) { lock.lock(); storage.append(url); lock.unlock() }
    var urls: [URL] { lock.lock(); defer { lock.unlock() }; return storage }
}

// MARK: Sidebar

struct Sidebar: View {
    @EnvironmentObject var app: AppModel
    /// The sidebar in the order you work: get footage in, create, manage, deliver.
    static let groups: [(title: String?, sections: [SidebarSection])] = [
        (nil, [.home, .projects, .importMedia]),
        ("Create", [.aiClips, .editor, .captions]),
        ("Library", [.media, .templates]),
        ("Deliver", [.exports]),
    ]
    /// On the working pages the sidebar starts as an icon rail; this remembers if you opened it there.
    @AppStorage("sidebarExpandedOnWorkspacePages") private var expandedOnWorkspace = false

    var collapsed: Bool { app.section.isWorkspace ? !expandedOnWorkspace : app.settings.sidebarCollapsed }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(nsImage: AppIcon.render(size: 64)).resizable().frame(width: 26, height: 26)
                if !collapsed {
                    Text("PULSE").font(.system(size: 15, weight: .heavy)).tracking(2).foregroundStyle(Theme.accentGradient)
                    Text(AppModel.shortVersion).font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                        .help("PULSE \(AppModel.versionString)")
                    Spacer()
                }
            }
            .padding(.horizontal, collapsed ? 13 : 14)
            .padding(.top, 34)
            .padding(.bottom, 14)

            ForEach(Array(Self.groups.enumerated()), id: \.offset) { index, group in
                if let title = group.title, !collapsed {
                    SectionLabel(text: title).padding(.horizontal, 16).padding(.top, index == 0 ? 0 : 12).padding(.bottom, 4)
                } else if index > 0 {
                    Rectangle().fill(Theme.divider).frame(height: 1).padding(.horizontal, collapsed ? 14 : 16).padding(.vertical, 6)
                }
                ForEach(group.sections) { section in
                    SidebarItem(section: section, collapsed: collapsed)
                }
            }
            if !collapsed, !app.projects.filter(\.isFavorite).isEmpty {
                SectionLabel(text: "Favorites").padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 4)
                ForEach(app.projects.filter(\.isFavorite).prefix(4)) { p in
                    Button { app.openProject(p) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Theme.warning)
                            Text(p.name).lineLimit(1).font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !collapsed, !app.projects.isEmpty {
                SectionLabel(text: "Recent").padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 4)
                ForEach(app.projects.prefix(4)) { p in
                    Button { app.openProject(p) } label: {
                        HStack(spacing: 8) {
                            Circle().fill(app.session?.document.id == p.id ? Theme.accent : Theme.textTertiary).frame(width: 5, height: 5)
                            Text(p.name).lineLimit(1).font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            SidebarItem(section: .settings, collapsed: collapsed)
            Button {
                withAnimation(Theme.motion(.easeOut(duration: 0.18))) {
                    if app.section.isWorkspace { expandedOnWorkspace.toggle() } else { app.settings.sidebarCollapsed.toggle() }
                }
            } label: {
                Image(systemName: collapsed ? "sidebar.right" : "sidebar.left")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .help(collapsed ? "Expand sidebar" : "Collapse sidebar")
        }
        .frame(width: collapsed ? 52 : 208)
        .background(Theme.panel)
    }
}

struct SidebarItem: View {
    @EnvironmentObject var app: AppModel
    let section: SidebarSection
    let collapsed: Bool
    @State private var hovering = false

    var isSelected: Bool { app.section == section }
    var disabled: Bool { section.needsProject && app.session == nil }

    var body: some View {
        Button { app.section = section } label: {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                if !collapsed {
                    Text(section.title)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    Spacer()
                    if section == .aiClips, let count = app.session?.document.visibleCandidates.count, count > 0 {
                        Text("\(count)").font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Theme.aiSoft)).foregroundStyle(Theme.ai)
                    }
                    if section == .exports, app.exports.isRunning {
                        ProgressRing(progress: app.exports.summary.overallProgress, size: 12)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(isSelected ? Theme.control : (hovering ? Theme.control.opacity(0.5) : .clear)))
            .overlay(alignment: .leading) {
                if isSelected { Capsule().fill(Theme.accentGradient).frame(width: 3, height: 16).offset(x: -3) }
            }
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.45 : 1)
        .onHover { hovering = $0 }
        .help(collapsed ? section.title : "")
    }
}

// MARK: Page bar

/// The workflow along the bottom of the window, one click per stage — Media → AI Clips → Edit →
/// Captions → Deliver — like the page bar of a pro editing suite.
struct PageBar: View {
    @EnvironmentObject var app: AppModel

    static let pages: [(SidebarSection, String, String)] = [
        (.media, "Media", "photo.stack"),
        (.aiClips, "AI Clips", "sparkles"),
        (.editor, "Edit", "timeline.selection"),
        (.captions, "Captions", "captions.bubble"),
        (.exports, "Deliver", "paperplane"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            Button { app.section = .home } label: {
                Image(systemName: "house").font(.system(size: 13)).foregroundStyle(Theme.textTertiary).frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .help("Home")
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                ForEach(Self.pages, id: \.0) { page in
                    PageBarItem(section: page.0, title: page.1, symbol: page.2)
                }
            }
            .padding(3)
            .background(Capsule().fill(Theme.well))
            .overlay(Capsule().strokeBorder(Theme.border))
            Spacer(minLength: 8)
            Button { app.showLongFormSheet = true } label: {
                Label("Edit My VOD", systemImage: "film.stack")
            }
            .buttonStyle(.pulse(.ai, compact: true))
            .padding(.trailing, 12)
            .help("Turn the whole stream into a 10–20 minute YouTube video")
        }
        .frame(height: 46)
        .background(Theme.panel)
        .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }
}

struct PageBarItem: View {
    @EnvironmentObject var app: AppModel
    let section: SidebarSection
    let title: String
    let symbol: String
    @State private var hovering = false

    var selected: Bool { app.section == section }

    var body: some View {
        Button { app.section = section } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(selected ? Theme.accent : (hovering ? Theme.textPrimary : Theme.textSecondary))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(selected ? Theme.accentSoft : (hovering ? Theme.control : .clear)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(title)
    }
}

// MARK: Top bar

struct TopBar: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                if let session = app.session {
                    Text(session.document.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textTertiary)
                }
                Text(app.section.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                if let session = app.session {
                    SaveStateBadge(session: session).padding(.leading, 4)
                }
            }
            Spacer()
            Button { app.showGlobalSearch = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text("Search projects, clips, transcript…").lineLimit(1)
                    Spacer()
                    Text("⌘F").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                }
                .font(.pulseCaption)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 10)
                .frame(width: 280, height: 26)
                .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.well))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
            }
            .buttonStyle(.plain)
            JobsIndicator(jobs: app.jobs)
            SystemStatusIndicator()
            if app.session != nil {
                Button { app.showImportPanel() } label: { Label("Import", systemImage: "plus") }
                    .buttonStyle(.pulse(.secondary, compact: true))
            }
            VersionBadge()
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .frame(height: 50)
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }
}

/// The app version, top right. Turns into "Update to x.y" when a newer release is out; click for
/// the update sheet (check, what's new, install & relaunch).
struct VersionBadge: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let update = app.updater.available
        Button { app.updater.showSheet = true } label: {
            HStack(spacing: 4) {
                if update != nil { Image(systemName: "arrow.down.circle.fill").font(.system(size: 10)) }
                Text(update.map { "Update to \($0.version.description)" } ?? (AppModel.shortVersion == "dev" ? "dev build" : "v\(AppModel.shortVersion)"))
                    .font(.system(size: update != nil ? 11 : 10, weight: update != nil ? .bold : .semibold, design: .rounded)).monospacedDigit()
            }
            .padding(.horizontal, update != nil ? 4 : 0).padding(.vertical, update != nil ? 2 : 0)
            .foregroundStyle(update != nil ? Color.white : Theme.textSecondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(update != nil ? Theme.accent : Theme.control))
        }
        .buttonStyle(.plain)
        .help(update != nil ? "A new version of PULSE is ready — click to see what's new and install" : "PULSE \(AppModel.versionString) — click to check for updates")
    }
}

/// The save state as a dot (#405): amber while there are unsaved edits, green once saved; hover for the time.
struct SaveStateBadge: View {
    @ObservedObject var session: ProjectSession
    var body: some View {
        if session.isDirty {
            Circle().fill(Theme.warning).frame(width: 7, height: 7)
                .help("Unsaved changes — PULSE autosaves")
                .accessibilityLabel("Unsaved changes")
        } else if let saved = session.lastSaved {
            Circle().fill(Theme.success).frame(width: 7, height: 7)
                .help("Saved \(saved.formatted(date: .omitted, time: .shortened))")
                .accessibilityLabel("Saved")
        }
    }
}

/// One quiet dot for the app's state (#421): processing location, memory, GPU mode and connectivity live in
/// its popover instead of a row of pills.
struct SystemStatusIndicator: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject private var memory = MemoryPressure.shared
    @State private var showPopover = false

    var location: ProcessingLocation {
        app.settings.ai.cloudProvider == .none || app.settings.ai.processingPolicy == .alwaysLocal ? .local : .cloud
    }

    var attention: Bool { memory.level != .normal || FrameRenderer.safeMode || (!Connectivity.shared.isOnline && location == .cloud) }

    var body: some View {
        let online = Connectivity.shared.isOnline
        Button { showPopover.toggle() } label: {
            HStack(spacing: 5) {
                Circle().fill(attention ? Theme.warning : Theme.success).frame(width: 7, height: 7)
                Text(location == .local ? "LOCAL" : "CLOUD").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 8).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.control))
        }
        .buttonStyle(.plain)
        .help(attention ? "Something needs a look — click for details" : "Everything's normal — click for details")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("System").font(.pulseHeadline)
                statusRow("Processing", location == .local ? "On this Mac" : "Cloud model for some steps", ok: true)
                statusRow("Memory", memory.level.displayName + " · PULSE uses " + MemoryPressure.footprintDescription, ok: memory.level == .normal)
                statusRow("Rendering", FrameRenderer.safeMode ? "Safe mode (CPU)" : "GPU", ok: !FrameRenderer.safeMode)
                statusRow("Network", online ? "Online" : "Offline — downloads and cloud steps wait", ok: online || location == .local)
                Divider()
                ProcessingBadge(location: location)
            }
            .padding(14)
            .frame(width: 320)
        }
    }

    func statusRow(_ title: String, _ detail: String, ok: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(ok ? Theme.success : Theme.warning).frame(width: 7, height: 7).padding(.top, 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.pulseCaption).foregroundStyle(Theme.textPrimary)
                Text(detail).font(.pulseMicro).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

struct JobsIndicator: View {
    @ObservedObject var jobs: JobCenter
    @State private var showPopover = false

    var body: some View {
        let running = jobs.running
        Button { showPopover.toggle() } label: {
            HStack(spacing: 6) {
                if running.isEmpty {
                    Image(systemName: "checkmark.circle").foregroundStyle(Theme.textTertiary)
                } else {
                    ProgressRing(progress: jobs.overallProgress, size: 14)
                    Text(running.count == 1 ? running[0].title : "\(running.count) tasks")
                        .lineLimit(1)
                        .font(.pulseCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: 180, alignment: .leading)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(running.isEmpty ? .clear : Theme.control))
        }
        .buttonStyle(.plain)
        .help("Background tasks")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            JobListView(jobs: jobs).frame(width: 360)
        }
    }
}

struct JobListView: View {
    @ObservedObject var jobs: JobCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader("Background Tasks") {
                Button("Clear") { jobs.clearFinished() }.buttonStyle(.pulse(.ghost, compact: true))
            }
            if jobs.jobs.isEmpty {
                Text("Nothing running. Analysis, transcription, proxies and exports appear here.")
                    .font(.pulseCaption).foregroundStyle(Theme.textTertiary).padding(14)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(jobs.jobs) { job in JobRow(job: job) }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
        .background(Theme.panel)
    }
}

struct JobRow: View {
    @ObservedObject var job: BackgroundJob

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: job.kind.symbolName).foregroundStyle(Theme.textSecondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(job.title).font(.pulseBody).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Spacer()
                    ProcessingBadge(location: job.location)
                }
                switch job.state {
                case .running:
                    ThinProgressBar(progress: job.progress)
                    HStack {
                        if !job.detail.isEmpty { Text(job.detail).font(.pulseMicro).foregroundStyle(Theme.textTertiary).lineLimit(1) }
                        Spacer(minLength: 4)
                        // Running for how long (#399).
                        Text(Timecode.duration(Date().timeIntervalSince(job.startedAt))).font(.pulseMicro).foregroundStyle(Theme.textTertiary).monospacedDigit()
                            .help("Running for this long")
                        if let left = job.remainingText { Text("· \(left)").font(.pulseMicro).foregroundStyle(Theme.textSecondary).monospacedDigit() }
                    }
                case .finished:
                    Text("Done").font(.pulseMicro).foregroundStyle(Theme.success)
                case .cancelled:
                    Text("Cancelled").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                case .failed(let message):
                    Text(message).font(.pulseMicro).foregroundStyle(Theme.danger).lineLimit(3)
                }
            }
            if job.isRunning {
                IconButton(symbol: "xmark", help: "Cancel", size: 20) { job.cancel() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }
}

// MARK: Toast

struct ToastView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        if let toast = app.toastMessage {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                Text(toast.message).font(.pulseBody).foregroundStyle(Theme.textPrimary).lineLimit(2)
                if let action = toast.action {
                    Button(action.title) { action.run(); app.toastMessage = nil }
                        .buttonStyle(.pulse(.secondary, compact: true))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(Theme.elevated))
            .overlay(Capsule().strokeBorder(Theme.borderStrong))
            .overlay(Capsule().strokeBorder(Theme.edgeHighlight, lineWidth: 1))
            .elevation(2)
            .padding(.bottom, app.session != nil ? 62 : 24) // clear of the page bar
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(toast.id)
            .animation(Theme.motion(.spring(response: 0.3, dampingFraction: 0.85)), value: toast.id)
        }
    }
}


/// File → Import from URL (#1): a YouTube link becomes a recording in the project.
struct ImportURLSheet: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var videoID: String? { YouTubeURL.videoID(from: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import a YouTube VOD").font(.pulseTitle).foregroundStyle(Theme.textPrimary)
            Text("PULSE fetches YouTube's own MP4 with sound (usually 720p) into ~/Movies/PULSE Downloads and imports it. Twitch VODs: download them with Twitch's own tools first.")
                .font(.pulseCaption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            TextField("https://www.youtube.com/watch?v=…", text: $text, onCommit: start).textFieldStyle(.roundedBorder)
            HStack {
                if !text.isEmpty, videoID == nil { Text("That doesn't look like a YouTube link").font(.pulseMicro).foregroundStyle(Theme.warning) }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.pulseSecondary).keyboardShortcut(.cancelAction)
                Button("Import") { start() }.buttonStyle(.pulsePrimary).keyboardShortcut(.defaultAction).disabled(videoID == nil)
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
        .onAppear { if let pasted = NSPasteboard.general.string(forType: .string), YouTubeURL.videoID(from: pasted) != nil { text = pasted } }
    }

    func start() {
        guard let id = videoID else { return }
        app.importFromYouTube(videoID: id)
        dismiss()
    }
}
