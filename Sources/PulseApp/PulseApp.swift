import AppKit
import PulseCore
import PulseEngine
import SwiftUI

@main
struct PulseMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppModel()

    init() {
        BundledFonts.register()
        // Build-script hook: `PULSE --render-icon <dir>` writes an .iconset and exits.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
            do {
                try AppIcon.writeIconset(to: URL(fileURLWithPath: args[i + 1], isDirectory: true))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("render-icon failed: \(error)\n".utf8))
                exit(1)
            }
        }
        // `PULSE --render-dmg-background <dir>` writes the installer window background (1× and 2× PNGs).
        if let i = args.firstIndex(of: "--render-dmg-background"), i + 1 < args.count {
            do {
                try AppIcon.writeDMGBackground(to: URL(fileURLWithPath: args[i + 1], isDirectory: true))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("render-dmg-background failed: \(error)\n".utf8))
                exit(1)
            }
        }
    }

    var body: some Scene {
        WindowGroup("PULSE", id: "main") {
            RootView()
                .environmentObject(app)
                .frame(minWidth: 1180, minHeight: 720)
                .preferredColorScheme(app.colorScheme)
                .onAppear {
                    appDelegate.app = app
                    KeyboardShortcutMonitor.shared.install(app: app)
                    UISnapshotter.runIfRequested(app: app)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands { PulseCommands(app: app) }

        Settings {
            SettingsView()
                .environmentObject(app)
                .preferredColorScheme(app.colorScheme)
                .frame(width: 720, height: 560)
        }

        // The viewer on its own, for a second monitor (#205). Same player, so it stays in sync for free.
        Window("Viewer", id: "viewer") {
            DetachedViewerWindow()
                .environmentObject(app)
                .preferredColorScheme(app.colorScheme)
                .frame(minWidth: 420, minHeight: 320)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 720, height: 560)

        // Inspector and transcript as their own windows (#429), driven by the open project.
        Window("Inspector", id: "inspector") {
            DetachedPanelWindow(panel: .inspector)
                .environmentObject(app)
                .preferredColorScheme(app.colorScheme)
                .frame(minWidth: 300, minHeight: 400)
        }
        .defaultSize(width: 340, height: 720)

        Window("Transcript", id: "transcript") {
            DetachedPanelWindow(panel: .transcript)
                .environmentObject(app)
                .preferredColorScheme(app.colorScheme)
                .frame(minWidth: 320, minHeight: 400)
        }
        .defaultSize(width: 420, height: 720)
    }
}

/// Window → Viewer / Inspector / Transcript in a separate window. Lives in a view so the command can reach `openWindow`.
struct OpenViewerWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Viewer in Separate Window") { openWindow(id: "viewer") }
            .keyboardShortcut("v", modifiers: [.command, .option, .shift])
        Button("Inspector in Separate Window") { openWindow(id: "inspector") }
            .keyboardShortcut("i", modifiers: [.command, .option, .shift])
        Button("Transcript in Separate Window") { openWindow(id: "transcript") }
            .keyboardShortcut("t", modifiers: [.command, .option, .shift])
    }
}

/// A panel of the editor on its own (#429).
struct DetachedPanelWindow: View {
    enum Panel { case inspector, transcript }
    @EnvironmentObject var app: AppModel
    let panel: Panel

    var body: some View {
        Group {
            if let session = app.session {
                switch panel {
                case .inspector: InspectorView(session: session)
                case .transcript: TranscriptPanel(session: session)
                }
            } else {
                Text("Open a project and this panel shows here")
                    .font(.pulseBody).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.panel)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var app: AppModel?

    /// Finder → Open With → PULSE, or a drop on the Dock icon (#466): projects open, media imports into the
    /// open project.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let app else { return }
        let projects = urls.filter { $0.pathExtension.lowercased() == "pulse" }
        let media = urls.filter { $0.pathExtension.lowercased() != "pulse" }
        if let project = projects.first { app.openProject(at: project) }
        guard !media.isEmpty else { return }
        if let session = app.session {
            session.importMedia(media)
        } else {
            app.pendingImportURLs = media
            app.section = .projects
            app.toast("Open or create a project and these \(media.count) file\(media.count == 1 ? "" : "s") will import into it")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSSetUncaughtExceptionHandler { exception in
            PulseLog.error("Uncaught exception: \(exception.name.rawValue) — \(exception.reason ?? "") \(exception.callStackSymbols.prefix(12).joined(separator: " | "))")
            PulseLog.flush()
        }
        app?.applyAppearance()
        NSApp.applicationIconImage = AppIcon.render(size: 512)
        // `swift run` launches as a background process; make it a regular foreground app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        PulseLog.info("PULSE quit")
        PulseLog.flush()
        MainActor.assumeIsolated { app?.applicationWillTerminate() }
    }
}

/// Menu bar commands with standard pro-editor shortcuts.
struct PulseCommands: Commands {
    @ObservedObject var app: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project…") { app.showNewProjectSheet = true }.keyboardShortcut("n")
            Button("Open Project…") { app.showOpenPanel() }.keyboardShortcut("o")
            Button("Restore Archived Project…") { app.restoreArchive() }
            Button("Import from URL…") { app.showImportURLSheet = true }.keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Highlight Reel from the Last 30 Days") { app.makeHighlightReel() }
            Button("Overnight Batch…") { app.showBatchSheet = true }.keyboardShortcut("b", modifiers: [.command, .option])
            Button("Open Sample Project") { app.openDemoProject() }
            Button("Edit Like a Reference…") { app.showReferenceSheet = true }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Button("Check Edit") { app.session?.checkEdit() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(app.session?.activeTimeline == nil)
            Button("Make Thumbnail…") { app.thumbnailRequest = ThumbnailRequest(timelineID: app.session?.selectedTimelineID) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(app.session?.document.primaryAsset == nil)
            Menu("Edit My VOD Again") {
                Button("Same Settings") { app.session?.editAgain() }
                Button("10 % Shorter") { app.session?.editAgain(lengthScale: 0.9) }
                Button("10 % Longer") { app.session?.editAgain(lengthScale: 1.1) }
                Divider()
                Button("Less Busy") { app.session?.editAgain(restraint: .subtle) }
                Button("More Busy") { app.session?.editAgain(restraint: .energetic) }
            }
            Button("Edit All Shorts Like This One") { app.session?.applyEditDecisionsToAllShorts() }.disabled(app.session?.activeTimeline == nil)
            .disabled(app.session?.lastLongFormOptions == nil)
            Button("Make a Short from Selection") { app.session?.makeShortFromSelection() }
            Button("Top 3 Shorts from This Edit") { app.session?.makeShortsFromEdit() }.disabled(app.session?.activeTimeline == nil)
                .keyboardShortcut("s", modifiers: [.command, .option, .shift])
                .disabled(app.session?.activeTimeline == nil)
            Button("Quick Export") { app.quickExport() }
                .keyboardShortcut("e")
                .disabled(app.session?.activeTimeline == nil)
            Divider()
            Button("Import Media…") { app.showImportPanel() }.keyboardShortcut(app.shortcut(.importMedia))
            Button(app.recording.isCapturing ? "Stop Recording" : "New Recording…") {
                if app.recording.isCapturing { app.recording.stop(app: app) } else { app.showRecordSheet = true }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            Button(app.recording.phase == .paused ? "Resume Recording" : "Pause Recording") { app.recording.togglePause() }
            Button("Mark Moment (Clip It)") { app.recording.markMoment() }.keyboardShortcut(app.shortcut(.markMoment)).disabled(app.recording.phase != .recording)
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!app.recording.isCapturing)
            Divider()
            Button("Close Project") { app.closeProject() }.keyboardShortcut("w", modifiers: [.command, .shift]).disabled(app.session == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { app.session?.save() }.keyboardShortcut("s").disabled(app.session == nil)
            Button("Save Version…") { app.session?.createVersion(label: nil) }.keyboardShortcut(app.shortcut(.saveVersion)).disabled(app.session == nil)
        }
        CommandGroup(replacing: .undoRedo) {
            Button(app.session?.undoLabel.map { "Undo \($0)" } ?? "Undo") { app.session?.undo() }
                .keyboardShortcut("z")
                .disabled(!(app.session?.canUndo ?? false))
            Button(app.session?.redoLabel.map { "Redo \($0)" } ?? "Redo") { app.session?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!(app.session?.canRedo ?? false))
        }
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { app.updater.showSheet = true }
        }
        CommandGroup(replacing: .help) {
            Button("Check for Updates…") { app.updater.showSheet = true }
            Button("What's New in \(AppModel.shortVersion)…") { app.openWhatsNew() }
            Button("Set Up for My Stream…") { app.showSetupWizard = true }
            Button("Report a Problem…") { app.showReportProblem = true }
            Button("Open Log Folder") { NSWorkspace.shared.open(PulseLog.directory) }
            Button(FrameRenderer.safeMode ? "Turn Off Safe Mode (CPU Rendering)" : "Use Safe Mode (CPU Rendering)") {
                FrameRenderer.safeMode.toggle()
                app.toast(FrameRenderer.safeMode ? "Safe mode on — the viewer and exports render on the CPU for edits you open from now on" : "Safe mode off — GPU rendering is back for edits you open from now on")
            }
            Divider()
            Button("PULSE on GitHub") {
                if let url = URL(string: "https://github.com/XmanXay69/PulseAI-Clipper") { NSWorkspace.shared.open(url) }
            }
        }
        CommandMenu("Timeline") {
            Button("Split at Playhead") { app.session?.splitAtPlayhead() }.keyboardShortcut(app.shortcut(.splitAtPlayhead))
            Button("Split All Tracks at Playhead") { app.session?.splitAllAtPlayhead() }.keyboardShortcut(app.shortcut(.splitAllTracks))
            Button("Add Transition") { app.session?.addDefaultTransition() }.keyboardShortcut(app.shortcut(.addTransition))
                .disabled(app.session?.activeTimeline == nil)
            Button("Copy Attributes") { app.session?.copyAttributes() }.keyboardShortcut(app.shortcut(.copyAttributes))
                .disabled(app.session?.selectedClipIDs.isEmpty ?? true)
            Button("Paste Attributes") { app.session?.pasteAttributes() }.keyboardShortcut(app.shortcut(.pasteAttributes))
                .disabled(app.session?.copiedAttributes == nil)
            Button("Paste Look Only") { app.session?.pasteAttributes(parts: .look) }.keyboardShortcut("v", modifiers: [.command, .option, .shift])
                .disabled(app.session?.copiedAttributes == nil)
            Button("Match Previous Clip") { app.session?.matchPreviousClip() }.keyboardShortcut(app.shortcut(.matchPreviousClip))
                .disabled(app.session?.selectedClipIDs.isEmpty ?? true)
            Button("Set Cover Frame at Playhead") { app.session?.setCoverFrame() }
                .disabled(app.session?.activeTimeline == nil)
            Divider()
            Button("Loop In → Out") { app.session?.toggleLoopInOut() }.keyboardShortcut(app.shortcut(.loopInOut))
            Button("Export In → Out") { app.session?.exportInOut() }.keyboardShortcut(app.shortcut(.exportInOut))
                .disabled(app.session?.inOutRange == nil)
            Button("Export Selected Clips") { app.session?.exportSelectedClips() }.keyboardShortcut(app.shortcut(.exportSelectedClips))
            Divider()
            Button(app.session?.speedEdit == true ? "Leave Speed Edit" : "Speed Edit Mode") { app.session?.toggleSpeedEdit() }
                .keyboardShortcut("e", modifiers: [.control, .shift])
                .disabled(app.session?.activeTimeline == nil)
                .disabled(app.session?.selectedClipIDs.isEmpty ?? true)
            Button("Export Final Cut Pro XML…") { app.session?.exportFCPXML() }
                .disabled(app.session?.activeTimeline == nil)
            Button("Export Review Page…") { app.session?.exportReviewPage() }
                .disabled(app.session?.activeTimeline == nil)
            Button("Export Chapter Art…") { app.session?.exportChapterArt() }
                .disabled(app.session?.activeTimeline == nil)
            Divider()
            Button("Project Settings…") { app.session?.showProjectSettings = true }
                .disabled(app.session == nil)
            Menu("Snapshots") {
                Button("Take Snapshot") { app.session?.takeSnapshot() }.keyboardShortcut(app.shortcut(.takeSnapshot))
                    .disabled(app.session?.activeTimeline == nil)
                if let session = app.session, let timeline = session.activeTimeline {
                    let list = session.document.snapshots(for: timeline.id)
                    if !list.isEmpty {
                        Divider()
                        ForEach(list) { snapshot in
                            Menu("\(snapshot.name) · \(snapshot.summary)") {
                                Button("Restore") { session.restoreSnapshot(snapshot.id) }
                                Button("Compare with Current") { session.compareSnapshot(snapshot.id) }
                                Button("Delete", role: .destructive) { session.deleteSnapshot(snapshot.id) }
                            }
                        }
                    }
                }
            }
            Divider()
            Button("Ripple Delete") { app.session?.deleteSelection(ripple: true) }.keyboardShortcut(.delete, modifiers: [.shift])
            Button("Duplicate") { app.session?.duplicateSelection() }.keyboardShortcut(app.shortcut(.duplicate))
            Button("Detach Audio") { app.session?.detachAudio() }.keyboardShortcut(app.shortcut(.detachAudio))
            Button("Ripple Delete In → Out") { app.session?.rippleDeleteInOut() }.keyboardShortcut(.delete, modifiers: [.command, .option])
            Button("Close All Gaps") { app.session?.closeAllGaps() }.disabled(app.session?.activeTimeline == nil)
            Button("Freeze Frame") { app.session?.freezeFrame() }.keyboardShortcut(app.shortcut(.freezeFrame)).disabled(app.session?.activeTimeline == nil)
            // ⌥ so typing a comma in a text field never moves a clip.
            Button("Nudge Left a Frame") { app.session?.nudgeSelection(frames: -1) }.keyboardShortcut(",", modifiers: [.option])
            Button("Nudge Right a Frame") { app.session?.nudgeSelection(frames: 1) }.keyboardShortcut(".", modifiers: [.option])
            Button("Nudge Left 10 Frames") { app.session?.nudgeSelection(frames: -10) }.keyboardShortcut(",", modifiers: [.option, .shift])
            Button("Nudge Right 10 Frames") { app.session?.nudgeSelection(frames: 10) }.keyboardShortcut(".", modifiers: [.option, .shift])
            Menu("Trim Modes") {
                Button("Slip Left a Frame") { app.session?.slipSelection(frames: -1) }.keyboardShortcut(",", modifiers: [.control])
                Button("Slip Right a Frame") { app.session?.slipSelection(frames: 1) }.keyboardShortcut(".", modifiers: [.control])
                Button("Slide Left a Frame") { app.session?.slideSelection(frames: -1) }.keyboardShortcut(",", modifiers: [.control, .option])
                Button("Slide Right a Frame") { app.session?.slideSelection(frames: 1) }.keyboardShortcut(".", modifiers: [.control, .option])
                Button("Roll Cut Left a Frame") { app.session?.rollSelection(frames: -1) }.keyboardShortcut(",", modifiers: [.control, .shift])
                Button("Roll Cut Right a Frame") { app.session?.rollSelection(frames: 1) }.keyboardShortcut(".", modifiers: [.control, .shift])
                Divider()
                Button("Slip Left 10 Frames") { app.session?.slipSelection(frames: -10) }
                Button("Slip Right 10 Frames") { app.session?.slipSelection(frames: 10) }
                Button("Slide Left 10 Frames") { app.session?.slideSelection(frames: -10) }
                Button("Slide Right 10 Frames") { app.session?.slideSelection(frames: 10) }
                Button("Roll Cut Left 10 Frames") { app.session?.rollSelection(frames: -10) }
                Button("Roll Cut Right 10 Frames") { app.session?.rollSelection(frames: 10) }
            }
            Divider()
            Button("Zoom In") { app.session?.zoomTimeline(by: 1.5) }.keyboardShortcut(app.shortcut(.zoomIn))
            Button("Zoom Out") { app.session?.zoomTimeline(by: 1 / 1.5) }.keyboardShortcut(app.shortcut(.zoomOut))
            Button("Zoom to Fit") { app.session?.zoomTimelineToFit() }.keyboardShortcut(app.shortcut(.zoomToFit))
            Divider()
            Button("Add Text") { app.session?.addText() }.keyboardShortcut("t", modifiers: [.command, .option])
            Menu("Add Shape") {
                ForEach(ProjectSession.ShapeKind.allCases, id: \.self) { kind in
                    Button(kind.displayName) { app.session?.addShape(kind) }
                }
            }
            Divider()
            Button("New Compound Clip") { app.session?.createCompoundClip() }
                .keyboardShortcut("g", modifiers: [.option])
                .disabled(app.session?.selectedClipIDs.isEmpty ?? true)
            Button("Break Apart Compound Clip") { app.session?.breakApartCompound() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button("Exit Compound Clip") { app.session?.exitCompound() }
                .disabled(!(app.session?.isInsideCompound ?? false))
            Button("Add Marker") { app.session?.addMarker() }
            Button("Add Music Drop Marker") { app.session?.addDropMarker() }
                .help("A marker named “Drop” — the music pulls out for a beat there when you apply drops")
            Button("Apply Music Drops") { app.session?.applyDropMarkers() }
            Button((app.session?.activeTimeline).map { ProgressBar.isPresent($0) } == true ? "Remove Progress Bar" : "Add Progress Bar") { app.session?.toggleProgressBar() }
                .disabled(app.session?.activeTimeline == nil)
            Divider()
            Button("Make More Entertaining") { app.session?.makeMoreEntertaining() }.keyboardShortcut("e", modifiers: [.command, .option])
            Button("AI Switch Multicam Angles") { app.session?.autoSwitchActiveTimeline() }.disabled(app.session?.activeMulticamGroup == nil)
            Button("Remove All AI Edits") { app.session?.stripAI() }
            Divider()
            Button(app.settings.snapping ? "Turn Snapping Off" : "Turn Snapping On") { app.settings.snapping.toggle() }
            Button(app.settings.magneticTimeline ? "Turn Magnetic Timeline Off" : "Turn Magnetic Timeline On") { app.settings.magneticTimeline.toggle() }
        }
        CommandMenu("Go") {
            ForEach(SidebarSection.allCases.filter { $0 != .settings }) { section in
                if let key = section.shortcut {
                    Button(section.title) { app.section = section }.keyboardShortcut(key, modifiers: [.command])
                } else {
                    Button(section.title) { app.section = section }
                }
            }
            Divider()
            Button("Search…") { app.showGlobalSearch = true }.keyboardShortcut("f")
            Button("Command Palette…") { app.showGlobalSearch = true }.keyboardShortcut("p", modifiers: [.command, .option])
        }
        CommandGroup(after: .sidebar) {
            Button(app.settings.sidebarCollapsed ? "Show Sidebar" : "Hide Sidebar") { app.settings.sidebarCollapsed.toggle() }
                .keyboardShortcut("0", modifiers: [.command, .control])
            Menu("Workspace") {
                ForEach(WorkspacePreset.allCases, id: \.self) { preset in
                    Button(preset.displayName) { app.settings.currentWorkspace = preset }
                }
            }
            OpenViewerWindowButton()
            MiniViewerToggle()
        }
    }
}

/// View → Mini Viewer (#196): the floating viewer on the AI Clips and Media pages.
struct MiniViewerToggle: View {
    @AppStorage("viewer.pip") private var enabled = true

    var body: some View {
        Toggle("Mini Viewer on AI Clips & Media", isOn: $enabled)
    }
}

/// Single-key editor shortcuts (Space, I, O, B, A, M, J/K/L, arrows, Delete). They're ignored while
/// a text field has focus, so typing captions or titles never triggers edits.
@MainActor
final class KeyboardShortcutMonitor {
    static let shared = KeyboardShortcutMonitor()
    private var monitor: Any?
    private weak var app: AppModel?

    func install(app: AppModel) {
        self.app = app
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated { self.handle(event) }
            return handled ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let app, let session = app.session else { return false }
        guard app.section == .editor || app.section == .captions else { return false }
        if let responder = NSApp.keyWindow?.firstResponder, responder is NSText || responder is NSTextView {
            return false
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.subtracting([.shift, .numericPad, .function]).isEmpty else { return false }
        let playback = session.playback
        switch event.keyCode {
        case 49: playback.togglePlayPause(); return true                        // Space
        case 123: playback.step(frames: modifiers.contains(.shift) ? -10 : -1); app.tick(); return true   // ←
        case 124: playback.step(frames: modifiers.contains(.shift) ? 10 : 1); app.tick(); return true     // →
        case 51, 117:                                                           // Delete / Fwd Delete
            session.deleteSelection(ripple: modifiers.contains(.shift))
            return true
        case 115: playback.goToStart(); return true                             // Home
        case 119: playback.goToEnd(); return true                               // End
        default: break
        }
        // Speed Edit (#500) takes a few keys while it's on; the rest fall through to the editor.
        if session.speedEdit {
            switch event.keyCode {
            case 53: session.toggleSpeedEdit(); return true                        // Escape
            case 36, 76: session.exportInOut(); return true                        // Return / Enter
            default: break
            }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "n": session.speedEditNext(); return true
            case "p": session.speedEditPrevious(); return true
            case "x": session.speedEditMakeShort(); return true
            case "d": session.speedEditDismiss(); return true
            default: break
            }
        }
        guard let chars = event.charactersIgnoringModifiers?.lowercased() else { return false }
        // 1–9 cut to multicam angle N at the playhead (works while playing).
        if modifiers.isEmpty, let digit = Int(chars), (1...9).contains(digit), session.activeMulticamGroup != nil {
            session.cutToAngle(digit - 1)
            return true
        }
        switch chars {
        case "i": session.inPoint = playback.currentTime; return true
        case "o": session.outPoint = playback.currentTime; return true
        case "b": session.tool = .blade; return true
        case "a": session.tool = .select; return true
        case "m": session.addMarker(); return true
        case "s" where modifiers.isEmpty: app.settings.snapping.toggle(); app.toast(app.settings.snapping ? "Snapping on" : "Snapping off"); return true
        case "j": playback.shuttle(-1); return true    // backwards, faster on each press
        case "k": playback.shuttle(0); return true     // stop
        case "?": app.section = .settings; app.toast("Settings → Shortcuts lists every key"); return true
        case "l": playback.shuttle(1); return true     // forwards: 1×, 2×, 4×, 8×
        case "=", "+": session.pixelsPerSecond = min(session.pixelsPerSecond * 1.3, 600); return true
        case "-": session.pixelsPerSecond = max(session.pixelsPerSecond / 1.3, 2); return true
        default: return false
        }
    }
}
