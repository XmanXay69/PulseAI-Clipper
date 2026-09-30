import Foundation
import PulseCore
import SQLite3

/// One entry in the "AI Activity" feed.
public struct ActivityRecord: Hashable, Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case transcription, clipGeneration, captions, rendering, export, analysis, proxy, autoEdit, importMedia

        public var displayName: String {
            switch self {
            case .transcription: return "Transcription"
            case .clipGeneration: return "Clip generation"
            case .captions: return "Captions"
            case .rendering: return "Rendering"
            case .export: return "Export"
            case .analysis: return "Analysis"
            case .proxy: return "Proxy"
            case .autoEdit: return "Auto Edit"
            case .importMedia: return "Import"
            }
        }

        public var symbolName: String {
            switch self {
            case .transcription: return "waveform"
            case .clipGeneration: return "sparkles"
            case .captions: return "captions.bubble"
            case .rendering: return "cpu"
            case .export: return "square.and.arrow.up"
            case .analysis: return "chart.xyaxis.line"
            case .proxy: return "rectangle.compress.vertical"
            case .autoEdit: return "wand.and.stars"
            case .importMedia: return "square.and.arrow.down"
            }
        }
    }

    public var id: Int64
    public var date: Date
    public var kind: Kind
    public var title: String
    public var detail: String
    public var location: ProcessingLocation
    public var projectID: UUID?
}

/// Global transcript search hit (across all projects).
public struct TranscriptSearchHit: Hashable, Sendable {
    public var projectID: UUID
    public var assetID: UUID
    public var start: Seconds
    public var text: String
}

public enum LibraryDatabaseError: Error, LocalizedError {
    case openFailed(String)
    case statementFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let m): return "PULSE couldn't open its library database: \(m)"
        case .statementFailed(let m): return "Library database error: \(m)"
        }
    }
}

/// SQLite index of projects, media metadata, clip candidates, AI activity and transcripts (FTS5).
/// Project packages remain the source of truth; this index makes Home, search and stats instant.
/// Media binaries are never stored here — only references.
public final class LibraryDatabase: @unchecked Sendable {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "app.pulse.library-db")
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw LibraryDatabaseError.openFailed(message)
        }
        db = handle
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    public static func defaultURL() -> URL {
        PulseDirectories.applicationSupport.appendingPathComponent("Library.sqlite")
    }

    private func migrate() throws {
        try execute("""
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS projects (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, path TEXT NOT NULL, modified REAL, created REAL,
            duration REAL, resolution TEXT, clip_count INTEGER, timeline_count INTEGER, status TEXT,
            thumbnail TEXT, favorite INTEGER DEFAULT 0, trashed INTEGER DEFAULT 0);
        CREATE TABLE IF NOT EXISTS media (
            id TEXT PRIMARY KEY, project_id TEXT NOT NULL, name TEXT, path TEXT, kind TEXT, role TEXT,
            duration REAL, width INTEGER, height INTEGER, fps REAL, size INTEGER);
        CREATE TABLE IF NOT EXISTS clips (
            id TEXT PRIMARY KEY, project_id TEXT NOT NULL, asset_id TEXT, title TEXT, start REAL, end REAL,
            potential INTEGER, tags TEXT);
        CREATE TABLE IF NOT EXISTS activity (
            id INTEGER PRIMARY KEY AUTOINCREMENT, date REAL, kind TEXT, title TEXT, detail TEXT,
            location TEXT, project_id TEXT);
        CREATE VIRTUAL TABLE IF NOT EXISTS transcript_fts USING fts5(project_id UNINDEXED, asset_id UNINDEXED, start UNINDEXED, text);
        CREATE INDEX IF NOT EXISTS media_project ON media(project_id);
        CREATE INDEX IF NOT EXISTS clips_project ON clips(project_id);
        """)
    }

    // MARK: Low level

    private func execute(_ sql: String) throws {
        try queue.sync {
            var error: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
                let message = error.map { String(cString: $0) } ?? "unknown"
                sqlite3_free(error)
                throw LibraryDatabaseError.statementFailed(message)
            }
        }
    }

    private enum Value {
        case text(String?)
        case double(Double)
        case int(Int64)
    }

    private func run(_ sql: String, _ values: [Value]) throws {
        try queue.sync {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw LibraryDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }
            bind(statement, values)
            let rc = sqlite3_step(statement)
            guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
                throw LibraryDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    private func query<T>(_ sql: String, _ values: [Value], map: (OpaquePointer) -> T?) -> [T] {
        queue.sync {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
            defer { sqlite3_finalize(statement) }
            bind(statement, values)
            var rows: [T] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let row = map(statement) { rows.append(row) }
            }
            return rows
        }
    }

    private func bind(_ statement: OpaquePointer?, _ values: [Value]) {
        for (i, value) in values.enumerated() {
            let index = Int32(i + 1)
            switch value {
            case .text(let s):
                if let s { sqlite3_bind_text(statement, index, s, -1, LibraryDatabase.transient) } else { sqlite3_bind_null(statement, index) }
            case .double(let d):
                sqlite3_bind_double(statement, index, d)
            case .int(let n):
                sqlite3_bind_int64(statement, index, n)
            }
        }
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let c = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: c)
    }

    // MARK: Projects

    /// Indexes a project (summary, media, candidates) after every save.
    public func index(_ document: ProjectDocument, path: String, thumbnailPath: String?) {
        let s = document.summary
        try? run("""
        INSERT OR REPLACE INTO projects (id, name, path, modified, created, duration, resolution, clip_count, timeline_count, status, thumbnail, favorite, trashed)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
        """, [.text(s.id.uuidString), .text(s.name), .text(path), .double(s.modifiedAt.timeIntervalSince1970), .double(s.createdAt.timeIntervalSince1970),
              .double(s.duration), .text(s.resolution), .int(Int64(s.clipCount)), .int(Int64(s.timelineCount)), .text(s.status.rawValue),
              .text(thumbnailPath), .int(s.isFavorite ? 1 : 0), .int(s.isTrashed ? 1 : 0)])
        try? run("DELETE FROM media WHERE project_id = ?", [.text(s.id.uuidString)])
        for m in document.media {
            try? run("INSERT OR REPLACE INTO media (id, project_id, name, path, kind, role, duration, width, height, fps, size) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                     [.text(m.id.uuidString), .text(s.id.uuidString), .text(m.name), .text(m.path), .text(m.kind.rawValue), .text(m.role.rawValue),
                      .double(m.metadata.duration), .int(Int64(m.metadata.width)), .int(Int64(m.metadata.height)), .double(m.metadata.frameRate),
                      .int(m.metadata.fileSize)])
        }
        try? run("DELETE FROM clips WHERE project_id = ?", [.text(s.id.uuidString)])
        for c in document.visibleCandidates {
            try? run("INSERT OR REPLACE INTO clips (id, project_id, asset_id, title, start, end, potential, tags) VALUES (?,?,?,?,?,?,?,?)",
                     [.text(c.id.uuidString), .text(s.id.uuidString), .text(c.assetID.uuidString), .text(c.title), .double(c.range.start),
                      .double(c.range.end), .int(Int64(c.potential)), .text(c.tags.map(\.rawValue).joined(separator: ","))])
        }
    }

    public func removeProject(id: UUID) {
        for table in ["projects", "media", "clips"] {
            let column = table == "projects" ? "id" : "project_id"
            try? run("DELETE FROM \(table) WHERE \(column) = ?", [.text(id.uuidString)])
        }
        try? run("DELETE FROM transcript_fts WHERE project_id = ?", [.text(id.uuidString)])
    }

    public func projects(includeTrashed: Bool = false) -> [ProjectSummary] {
        query("SELECT id, name, path, modified, created, duration, resolution, clip_count, timeline_count, status, thumbnail, favorite, trashed FROM projects ORDER BY modified DESC", []) { st in
            guard let idText = LibraryDatabase.text(st, 0), let id = UUID(uuidString: idText) else { return nil }
            let trashed = sqlite3_column_int(st, 12) != 0
            if trashed && !includeTrashed { return nil }
            return ProjectSummary(id: id, name: LibraryDatabase.text(st, 1) ?? "Untitled", path: LibraryDatabase.text(st, 2) ?? "",
                                  modifiedAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 3)),
                                  createdAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 4)),
                                  duration: sqlite3_column_double(st, 5), resolution: LibraryDatabase.text(st, 6) ?? "—",
                                  clipCount: Int(sqlite3_column_int(st, 7)), timelineCount: Int(sqlite3_column_int(st, 8)),
                                  status: ProjectStatus(rawValue: LibraryDatabase.text(st, 9) ?? "") ?? .empty,
                                  thumbnailPath: LibraryDatabase.text(st, 10), isFavorite: sqlite3_column_int(st, 11) != 0, isTrashed: trashed)
        }
    }

    /// Totals for the Home dashboard.
    public func stats() -> (projects: Int, clips: Int, mediaBytes: Int64) {
        let p = query("SELECT COUNT(*) FROM projects WHERE trashed = 0", []) { Int(sqlite3_column_int64($0, 0)) }.first ?? 0
        let c = query("SELECT COUNT(*) FROM clips", []) { Int(sqlite3_column_int64($0, 0)) }.first ?? 0
        let m = query("SELECT COALESCE(SUM(size),0) FROM media", []) { sqlite3_column_int64($0, 0) }.first ?? 0
        return (p, c, m)
    }

    // MARK: Activity

    @discardableResult
    public func logActivity(kind: ActivityRecord.Kind, title: String, detail: String = "", location: ProcessingLocation = .local, projectID: UUID? = nil) -> Bool {
        (try? run("INSERT INTO activity (date, kind, title, detail, location, project_id) VALUES (?,?,?,?,?,?)",
                  [.double(Date().timeIntervalSince1970), .text(kind.rawValue), .text(title), .text(detail), .text(location.rawValue), .text(projectID?.uuidString)])) != nil
    }

    public func recentActivity(limit: Int = 30) -> [ActivityRecord] {
        query("SELECT id, date, kind, title, detail, location, project_id FROM activity ORDER BY date DESC LIMIT ?", [.int(Int64(limit))]) { st in
            ActivityRecord(id: sqlite3_column_int64(st, 0), date: Date(timeIntervalSince1970: sqlite3_column_double(st, 1)),
                           kind: ActivityRecord.Kind(rawValue: LibraryDatabase.text(st, 2) ?? "") ?? .analysis,
                           title: LibraryDatabase.text(st, 3) ?? "", detail: LibraryDatabase.text(st, 4) ?? "",
                           location: ProcessingLocation(rawValue: LibraryDatabase.text(st, 5) ?? "") ?? .local,
                           projectID: LibraryDatabase.text(st, 6).flatMap(UUID.init(uuidString:)))
        }
    }

    // MARK: Transcripts

    public func indexTranscript(_ transcript: Transcript, projectID: UUID, assetID: UUID) {
        try? run("DELETE FROM transcript_fts WHERE project_id = ? AND asset_id = ?", [.text(projectID.uuidString), .text(assetID.uuidString)])
        try? execute("BEGIN")
        for sentence in transcript.sentences() {
            try? run("INSERT INTO transcript_fts (project_id, asset_id, start, text) VALUES (?,?,?,?)",
                     [.text(projectID.uuidString), .text(assetID.uuidString), .double(sentence.start), .text(sentence.text)])
        }
        try? execute("COMMIT")
    }

    public func searchTranscripts(_ query: String, limit: Int = 50) -> [TranscriptSearchHit] {
        let terms = query.split(separator: " ").map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"*" }.joined(separator: " ")
        guard !terms.isEmpty else { return [] }
        return self.query("SELECT project_id, asset_id, start, text FROM transcript_fts WHERE transcript_fts MATCH ? LIMIT ?", [.text(terms), .int(Int64(limit))]) { st in
            guard let p = LibraryDatabase.text(st, 0).flatMap(UUID.init(uuidString:)),
                  let a = LibraryDatabase.text(st, 1).flatMap(UUID.init(uuidString:)) else { return nil }
            return TranscriptSearchHit(projectID: p, assetID: a, start: sqlite3_column_double(st, 2), text: LibraryDatabase.text(st, 3) ?? "")
        }
    }
}
