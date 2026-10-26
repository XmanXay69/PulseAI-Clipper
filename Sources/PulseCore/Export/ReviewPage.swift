import Foundation

/// A review page for someone who doesn't have PULSE (#471): the cut as a table with timecodes, chapters,
/// what was removed, the notes — one HTML file that works offline and prints.
public enum ReviewPage {
    public static func html(timeline: Timeline, projectName: String, assets: [MediaAsset] = [], reviewer: String = "") -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        let fps = timeline.canvas.frameRate
        let names = Dictionary(assets.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var rows = ""
        for track in timeline.tracks {
            for clip in track.clips.sorted(by: { $0.start < $1.start }) {
                let source: String
                switch clip.content {
                case .media(let id): source = "\(esc(names[id] ?? "media")) · \(Timecode.string(clip.sourceIn, fps: fps))–\(Timecode.string(clip.sourceOut, fps: fps))"
                case .text(let element): source = "text: “\(esc(element.text))”"
                case .solid: source = "colour"
                case .compound: source = "compound clip"
                }
                rows += "<tr><td>\(Timecode.string(clip.start, fps: fps))</td><td>\(Timecode.string(clip.end, fps: fps))</td><td>\(esc(track.name))</td><td>\(esc(clip.name))\(clip.aiGenerated ? " <span class=ai>AI</span>" : "")</td><td>\(source)</td><td class=c><label><input type=checkbox> ok</label></td><td><input class=note placeholder=\"note…\"></td></tr>\n"
            }
        }
        let chapters = timeline.markers.filter { $0.color == .blue }.sorted { $0.time < $1.time }
            .map { "<li><b>\(Timecode.string($0.time, fps: fps))</b> \(esc($0.name))</li>" }.joined()
        let removed = timeline.removedSections.sorted { $0.sourceRange.start < $1.sourceRange.start }.prefix(200)
            .map { "<li>\(Timecode.duration($0.sourceRange.duration)) of \(esc($0.reason.displayName.lowercased())) at source \(Timecode.string($0.sourceRange.start, fps: fps))\($0.text.map { " — “\(esc(String($0.prefix(80))))”" } ?? "")</li>" }.joined()
        let notes = timeline.notes.isEmpty ? "" : "<h2>Notes</h2><pre>\(esc(timeline.notes))</pre>"
        let report = EditReport.build(timeline: timeline, assets: assets)
        let summary = report.sections.map { "<h3>\(esc($0.title))</h3><ul>" + $0.lines.map { "<li>\(esc($0.text))</li>" }.joined() + "</ul>" }.joined()
        return """
        <!doctype html><html><head><meta charset="utf-8"><title>\(esc(projectName)) — \(esc(timeline.name)) review</title>
        <style>body{font:13px -apple-system,Helvetica,Arial;margin:28px;color:#111;max-width:1100px}h1{font-size:22px;margin:0 0 4px}h2{font-size:15px;margin:22px 0 8px}h3{font-size:12px;text-transform:uppercase;letter-spacing:.06em;color:#666;margin:14px 0 4px}
        table{border-collapse:collapse;width:100%;font-size:12px}th,td{padding:4px 6px;border-bottom:1px solid #eee;text-align:left;vertical-align:top}th{background:#f6f6f8;position:sticky;top:0}td.c{white-space:nowrap}
        .ai{font-size:10px;background:#7c5cff;color:#fff;border-radius:4px;padding:1px 4px}.note{width:100%;border:1px solid #ddd;border-radius:4px;padding:2px 4px;font:12px inherit}
        .meta{color:#666}@media print{.note{border:none}}</style></head><body>
        <h1>\(esc(timeline.name))</h1>
        <p class=meta>\(esc(projectName)) · \(Timecode.duration(timeline.duration)) · \(timeline.canvas.width)×\(timeline.canvas.height) @ \(String(format: "%g", fps)) fps · \(timeline.allClips.count) clips\(reviewer.isEmpty ? "" : " · for \(esc(reviewer))")</p>
        <p class=meta>Tick what's fine, type a note where it isn't, then print or save this page and send it back. Nothing here changes the project.</p>
        \(chapters.isEmpty ? "" : "<h2>Chapters</h2><ol>\(chapters)</ol>")
        <h2>The cut</h2>
        <table><thead><tr><th>In</th><th>Out</th><th>Track</th><th>Clip</th><th>Source</th><th>OK</th><th>Note</th></tr></thead><tbody>
        \(rows)</tbody></table>
        \(removed.isEmpty ? "" : "<h2>Removed</h2><ul>\(removed)</ul>")
        <h2>Summary</h2>\(summary)
        \(notes)
        <p class=meta>Made with PULSE</p>
        </body></html>
        """
    }
}
