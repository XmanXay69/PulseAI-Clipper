import Foundation

/// The text that goes with an export: title ideas, the YouTube chapter list and music/clip credits (from the
/// timeline's notes), hashtags — written next to the video as a .txt, ready to paste into the description.
public enum ExportSidecar {
    /// The Finder comment stamped on an export (#465): Get Info and Spotlight show which project and edit it
    /// came from, and the project's path leads back to it.
    public static func finderComment(projectName: String, timelineName: String, projectPath: String?) -> String {
        var line = "PULSE · \(projectName) › \(timelineName)"
        if let projectPath, !projectPath.isEmpty { line += " · Project: \(projectPath)" }
        return line
    }

    public static func text(for timeline: Timeline, projectName: String) -> String {
        var blocks: [String] = []
        let copy = timeline.copy
        let titles = copy?.titles.filter { !$0.isEmpty } ?? []
        if !titles.isEmpty {
            blocks.append((["Title ideas"] + titles.prefix(3).map { "• " + $0 }).joined(separator: "\n"))
        } else if let title = copy?.shortsTitle, !title.isEmpty {
            blocks.append("Title\n• " + title)
        }
        let notes = timeline.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { blocks.append(notes) }
        if let caption = copy?.tiktokCaption, !caption.isEmpty { blocks.append("Caption\n" + caption) }
        if let tags = copy?.hashtags, !tags.isEmpty {
            blocks.append(tags.map { $0.hasPrefix("#") ? $0 : "#" + $0 }.joined(separator: " "))
        }
        guard !blocks.isEmpty else { return "" }
        return (["\(projectName) — \(timeline.name)", String(repeating: "—", count: 24)] + blocks).joined(separator: "\n\n") + "\n"
    }
}
