import AppKit
import PulseCore
import PulseEngine

/// Builds a "Report a Problem" bundle: the app log, system info, recent activity, a summary of the open
/// project (names and settings — no media, transcripts or keys) and recent PULSE crash reports.
@MainActor
enum ProblemReporter {
    static let issuesURL = "https://github.com/XmanXay69/PulseAI-Clipper/issues/new"

    static var machineModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    static func systemSummary(app: AppModel) -> String {
        let p = ProcessInfo.processInfo
        var lines = [
            "PULSE \(AppModel.versionString)",
            "macOS \(p.operatingSystemVersionString)",
            "\(machineModel) · \(p.activeProcessorCount) cores · \(p.physicalMemory / 1_073_741_824) GB RAM",
            "Free disk: \(ByteCountFormatter.string(fromByteCount: app.diskInfo.availableBytes, countStyle: .file))",
            "Transcription: \(TranscriptionEngineFactory.friendlyStatus(settings: app.settings.ai).text)",
            "Analysis speed (s per media-minute): audio \(String(format: "%.2f", app.settings.ai.analysisSpeed.audio)), "
                + "speech \(String(format: "%.2f", app.settings.ai.analysisSpeed.transcription)), video \(String(format: "%.2f", app.settings.ai.analysisSpeed.video))",
            "Cloud AI: \(app.settings.ai.cloudProvider.displayName)",
        ]
        if let session = app.session {
            let doc = session.document
            lines.append("")
            lines.append("Open project: \(doc.timelines.count) timelines, \(doc.candidates.count) clips, \(doc.media.count) media")
            for asset in doc.media.prefix(12) {
                let m = asset.metadata
                lines.append("  • \(asset.kind.rawValue) \(asset.role.rawValue) \(Timecode.short(m.duration)) \(m.width)×\(m.height) "
                    + "\(Int(m.frameRate)) fps \(m.videoCodec ?? "-") audio:\(m.hasAudio) analysis:\(asset.preparation.analysisState)")
            }
            for t in doc.timelines.prefix(12) {
                lines.append("  ▸ timeline \(Timecode.short(t.duration)) \(t.canvas.width)×\(t.canvas.height) "
                    + "\(t.tracks.count) tracks \(t.allClips.count) clips captions:\(t.captions != nil)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Writes the bundle as a .zip next to the user's Desktop and returns it.
    static func makeReport(app: AppModel, description: String) throws -> URL {
        PulseLog.info("Report a Problem: building bundle")
        PulseLog.flush()
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        let folderName = "PULSE Report \(stamp)"
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.removeItem(at: work)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let what = description.trimmingCharacters(in: .whitespacesAndNewlines)
        try ("What happened:\n\(what.isEmpty ? "(not described)" : what)\n\n" + systemSummary(app: app))
            .write(to: work.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
        let activity = app.activity.prefix(60).map { "\($0.date) [\($0.kind.displayName)] \($0.title) — \($0.detail)" }.joined(separator: "\n")
        try activity.write(to: work.appendingPathComponent("activity.txt"), atomically: true, encoding: .utf8)
        for log in [PulseLog.fileURL, PulseLog.previousFileURL] where FileManager.default.fileExists(atPath: log.path) {
            try? FileManager.default.copyItem(at: log, to: work.appendingPathComponent(log.lastPathComponent))
        }
        // Recent crash reports for PULSE (last two weeks).
        let reports = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!.appendingPathComponent("Logs/DiagnosticReports")
        let files = (try? FileManager.default.contentsOfDirectory(at: reports, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let recent = files.filter { $0.lastPathComponent.hasPrefix("PULSE") }
            .compactMap { url -> (URL, Date)? in
                guard let d = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      d > Date().addingTimeInterval(-14 * 86400) else { return nil }
                return (url, d)
            }
            .sorted { $0.1 > $1.1 }.prefix(3)
        for (url, _) in recent { try? FileManager.default.copyItem(at: url, to: work.appendingPathComponent(url.lastPathComponent)) }

        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let zip = desktop.appendingPathComponent(folderName + ".zip")
        try? FileManager.default.removeItem(at: zip)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", work.path, zip.path]
        try ditto.run()
        ditto.waitUntilExit()
        try? FileManager.default.removeItem(at: work)
        guard ditto.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        return zip
    }

    /// A new GitHub issue, pre-filled; the zip is attached by dragging it in.
    static func issueURL(description: String) -> URL? {
        let title = description.split(separator: "\n").first.map { String($0.prefix(80)) } ?? "Problem report"
        let body = """
        **What happened**
        \(description.isEmpty ? "(describe what you did and what went wrong)" : description)

        **Version:** PULSE \(AppModel.versionString) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · \(machineModel)

        _Drag the "PULSE Report….zip" from your Desktop into this box._
        """
        var c = URLComponents(string: issuesURL)
        c?.queryItems = [URLQueryItem(name: "title", value: title.isEmpty ? "Problem report" : title), URLQueryItem(name: "body", value: body)]
        return c?.url
    }
}
