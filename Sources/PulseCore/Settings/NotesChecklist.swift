import Foundation

/// Checklists inside project notes (#476): lines like "- [ ] grade the intro" and "- [x] export".
public enum NotesChecklist {
    public struct Item: Hashable, Identifiable, Sendable {
        public var id: Int { line }
        /// Line number in the notes.
        public var line: Int
        public var text: String
        public var done: Bool
    }

    static let open = "- [ ] "
    static let closed = "- [x] "

    public static func items(in notes: String) -> [Item] {
        var out: [Item] = []
        for (i, raw) in notes.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix(closed) {
                out.append(Item(line: i, text: String(line.dropFirst(closed.count)), done: true))
            } else if line.hasPrefix(open) {
                out.append(Item(line: i, text: String(line.dropFirst(open.count)), done: false))
            }
        }
        return out
    }

    /// The notes with that line's box flipped.
    public static func toggle(_ notes: String, line: Int) -> String {
        var lines = notes.components(separatedBy: "\n")
        guard lines.indices.contains(line) else { return notes }
        let raw = lines[line]
        let indent = raw.prefix { $0 == " " || $0 == "\t" }
        let body = raw.dropFirst(indent.count)
        if body.lowercased().hasPrefix(closed) {
            lines[line] = indent + open + body.dropFirst(closed.count)
        } else if body.hasPrefix(open) {
            lines[line] = indent + closed + body.dropFirst(open.count)
        }
        return lines.joined(separator: "\n")
    }

    /// Appends an unticked item.
    public static func add(_ text: String, to notes: String) -> String {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return notes }
        return notes.isEmpty ? open + t : notes + (notes.hasSuffix("\n") ? "" : "\n") + open + t
    }

    public static func progress(in notes: String) -> (done: Int, total: Int) {
        let all = items(in: notes)
        return (all.filter(\.done).count, all.count)
    }
}
