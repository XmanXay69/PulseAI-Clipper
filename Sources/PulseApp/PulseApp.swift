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
                .preferredColorScheme(.dark)
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
                .preferredColorScheme(.dark)
                .frame(width: 720, height: 560)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var app: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSSetUncaughtExceptionHandler { exception in
            PulseLog.error("Uncaught exception: \(exception.name.rawValue) — \(exception.reason ?? "") \(exception.callStackSymbols.prefix(12).joined(separator: " | "))")
            PulseLog.flush()
        }
        NSApp.appearance = NSAppearance(named: .darkAqua)
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
            Button("Overnight Batch…") { app.showBatchSheet = true }.keyboardShortcut("b", modifiers: [.command, .option])
            Button("Open Sample Project") { app.openDemoProject() }
            Button("Edit Like a Reference…") { app.showReferenceSheet = true }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Button("Make Thumbnail…") { app.thumbnailRequest = ThumbnailRequest(timelineID: app.session?.selectedTimelineID) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(app.session?.document.primaryAsset == nil)
            Divider()
            Button("Import Media…") { app.showImportPanel() }.keyboardShortcut("i")
            Button(app.recording.isCapturing ? "Stop Recording" : "New Recording…") {
                if app.recording.isCapturing { app.recording.stop(app: app) } else { app.showRecordSheet = true }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            Button(app.recording.phase == .paused ? "Resume Recording" : "Pause Recording") { app.recording.togglePause() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!app.recording.isCapturing)
            Divider()
            Button("Close Project") { app.closeProject() }.keyboardShortcut("w", modifiers: [.command, .shift]).disabled(app.session == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { app.session?.save() }.keyboardShortcut("s").disabled(app.session == nil)
            Button("Save Version…") { app.session?.createVersion(label: nil) }.keyboardShortcut("s", modifiers: [.command, .option]).disabled(app.session == nil)
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
            Button("Report a Problem…") { app.showReportProblem = true }
            Button("Open Log Folder") { NSWorkspace.shared.open(PulseLog.directory) }
            Divider()
            Button("PULSE on GitHub") {
                if let url = URL(string: "https://github.com/XmanXay69/PulseAI-Clipper") { NSWorkspace.shared.open(url) }
            }
        }
        CommandMenu("Timeline") {
            Button("Split at Playhead") { app.session?.splitAtPlayhead() }.keyboardShortcut("k")
            Button("Ripple Delete") { app.session?.deleteSelection(ripple: true) }.keyboardShortcut(.delete, modifiers: [.shift])
            Button("Duplicate") { app.session?.duplicateSelection() }.keyboardShortcut("d")
            Button("Detach Audio") { app.session?.detachAudio() }.keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Ripple Delete In → Out") { app.session?.rippleDeleteInOut() }.keyboardShortcut(.delete, modifiers: [.command, .option])
            Divider()
            Button("Add Text") { app.session?.addText() }.keyboardShortcut("t", modifiers: [.command, .option])
            Divider()
            Button("New Compound Clip") { app.session?.createCompoundClip() }
                .keyboardShortcut("g", modifiers: [.option])
                .disabled(app.session?.selectedClipIDs.isEmpty ?? true)
            Button("Break Apart Compound Clip") { app.session?.breakApartCompound() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button("Exit Compound Clip") { app.session?.exitCompound() }
                .disabled(!(app.session?.isInsideCompound ?? false))
            Button("Add Marker") { app.session?.addMarker() }
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
        }
        CommandGroup(after: .sidebar) {
            Button(app.settings.sidebarCollapsed ? "Show Sidebar" : "Hide Sidebar") { app.settings.sidebarCollapsed.toggle() }
                .keyboardShortcut("0", modifiers: [.command, .control])
            Menu("Workspace") {
                ForEach(WorkspacePreset.allCases, id: \.self) { preset in
                    Button(preset.displayName) { app.settings.currentWorkspace = preset }
                }
            }
        }
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
        case 123: playback.step(frames: modifiers.contains(.shift) ? -10 : -1); return true   // ←
        case 124: playback.step(frames: modifiers.contains(.shift) ? 10 : 1); return true     // →
        case 51, 117:                                                           // Delete / Fwd Delete
            session.deleteSelection(ripple: modifiers.contains(.shift))
            return true
        case 115: playback.goToStart(); return true                             // Home
        case 119: playback.goToEnd(); return true                               // End
        default: break
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
        case "j": playback.shuttle(rate: -2); return true
        case "k": playback.pause(); return true
        case "l": playback.shuttle(rate: playback.isPlaying ? 2 : 1); return true
        case "=", "+": session.pixelsPerSecond = min(session.pixelsPerSecond * 1.3, 600); return true
        case "-": session.pixelsPerSecond = max(session.pixelsPerSecond / 1.3, 2); return true
        default: return false
        }
    }
}
