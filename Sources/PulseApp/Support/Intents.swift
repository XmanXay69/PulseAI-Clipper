import AppIntents
import Foundation

/// Shortcuts and scripting (#462, #463): the main flows as App Intents, so a Shortcut or a Finder quick action
/// can hand PULSE a recording.
enum PulseIntentError: Error, CustomLocalizedStringResourceConvertible {
    case appNotReady
    case noFile

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotReady: return "PULSE isn't ready yet — open it and try again"
        case .noFile: return "That file couldn't be read"
        }
    }
}

struct MakeShortsIntent: AppIntent {
    static var title: LocalizedStringResource { "Make Shorts and a YouTube Edit" }
    static var description: IntentDescription? { IntentDescription("Analyzes a recording, builds its best shorts and a YouTube edit with your saved answers.") }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Recording", supportedTypeIdentifiers: ["public.movie", "public.audio"])
    var recording: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let app = AppModel.current else { throw PulseIntentError.appNotReady }
        guard let url = recording.fileURL else { throw PulseIntentError.noFile }
        app.batch.options.makeYouTubeEdit = true
        app.batch.add([url])
        app.showBatchSheet = true
        app.batch.start()
        return .result()
    }
}

struct ImportMediaIntent: AppIntent {
    static var title: LocalizedStringResource { "Import into PULSE" }
    static var description: IntentDescription? { IntentDescription("Imports a recording into the open project, or a new project named after it.") }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "File", supportedTypeIdentifiers: ["public.movie", "public.audio", "public.image"])
    var file: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let app = AppModel.current else { throw PulseIntentError.appNotReady }
        guard let url = file.fileURL else { throw PulseIntentError.noFile }
        app.importMedia([url])
        return .result()
    }
}

struct ImportLinkIntent: AppIntent {
    static var title: LocalizedStringResource { "Import a YouTube VOD" }
    static var description: IntentDescription? { IntentDescription("Downloads a YouTube VOD by link and imports it.") }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Link")
    var link: String

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let app = AppModel.current else { throw PulseIntentError.appNotReady }
        app.importPastedText(link)
        return .result()
    }
}

struct PulseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: MakeShortsIntent(), phrases: ["Make shorts with \(.applicationName)"], shortTitle: "Make Shorts", systemImageName: "sparkles")
        AppShortcut(intent: ImportMediaIntent(), phrases: ["Import into \(.applicationName)"], shortTitle: "Import Media", systemImageName: "square.and.arrow.down")
    }
}
