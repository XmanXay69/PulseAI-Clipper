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

    var collapsed: Bool { app.settings.sidebarCollapsed }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(nsImage: AppIcon.render(size: 64)).resizable().frame(width: 26, height: 26)
                if !collapsed {
                    Text("PULSE").font(.system(size: 15, weight: .heavy)).tracking(2).foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
            }
            .padding(.horizontal, collapsed ? 13 : 14)
            .padding(.top, 34)
            .padding(.bottom, 14)

            ForEach(SidebarSection.allCases.filter { $0 != .settings }) { section in
                SidebarItem(section: section, collapsed: collapsed)
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
                withAnimation(.easeOut(duration: 0.18)) { app.settings.sidebarCollapsed.toggle() }
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
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.45 : 1)
        .onHover { hovering = $0 }
        .help(collapsed ? section.title : "")
    }
}

// MARK: Top bar

struct TopBar: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(app.section.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                if let session = app.session {
                    HStack(spacing: 6) {
                        Text(session.document.name).font(.pulseCaption).foregroundStyle(Theme.textTertiary)
                        SaveStateBadge(session: session)
                    }
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
                .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.control))
            }
            .buttonStyle(.plain)
            JobsIndicator(jobs: app.jobs)
            ProcessingBadge(location: app.settings.ai.cloudProvider == .none || app.settings.ai.processingPolicy == .alwaysLocal ? .local : .cloud)
            if app.session != nil {
                Button { app.showImportPanel() } label: { Label("Import", systemImage: "plus") }
                    .buttonStyle(.pulse(.secondary, compact: true))
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .frame(height: 50)
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }
}

struct SaveStateBadge: View {
    @ObservedObject var session: ProjectSession
    var body: some View {
        if session.isDirty {
            Text("Edited").font(.pulseMicro).foregroundStyle(Theme.warning)
        } else if let saved = session.lastSaved {
            Text("Saved \(saved.formatted(date: .omitted, time: .shortened))").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
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
                        if let left = job.remainingText { Text(left).font(.pulseMicro).foregroundStyle(Theme.textSecondary).monospacedDigit() }
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(Theme.panelRaised).shadow(color: .black.opacity(0.4), radius: 16, y: 6))
            .overlay(Capsule().strokeBorder(Theme.borderStrong))
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(toast.id)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: toast.id)
        }
    }
}
