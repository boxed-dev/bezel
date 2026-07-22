import Foundation
import SQLite3

/// OpenCode adapter: discover sessions from `opencode.db` (SQLite).
///
/// Paths at runtime: `~/.local/share/opencode/opencode.db` or `OPENCODE_DB`.
/// Tests always pass an explicit fixture URL — never touch the live home DB.
public enum OpenCodeAdapter {
    public static let source: AgentSource = .opencode
    /// Cap SQLite scans — production DBs can be very large.
    public static let defaultDiscoveryLimit = 24

    public static func phase(status: String?) -> SessionPhase {
        guard let status else { return .idle }
        switch status.lowercased() {
        case "active", "running", "working":
            return .working
        case "idle", "paused":
            return .idle
        case "completed", "done", "archived":
            return .done
        case "error", "failed":
            return .error
        default:
            return .idle
        }
    }

    public static func discoverSessions(
        databaseURL: URL,
        limit: Int = defaultDiscoveryLimit
    ) throws -> [Session] {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            throw OpenCodeAdapterError.cannotOpen(databaseURL.path)
        }
        defer { sqlite3_close(db) }

        let capped = max(limit, 0)
        let sql = """
        SELECT id, directory, title, time_updated
        FROM session
        WHERE time_archived IS NULL
        ORDER BY time_updated DESC
        LIMIT \(capped)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw OpenCodeAdapterError.prepareFailed
        }
        defer { sqlite3_finalize(stmt) }

        var sessions: [Session] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = stringColumn(stmt, 0) ?? SessionID.unknown.rawValue
            let directory = stringColumn(stmt, 1)
            let title = stringColumn(stmt, 2)
            let updatedMs = sqlite3_column_int64(stmt, 3)
            let updatedAt = Date(timeIntervalSince1970: TimeInterval(updatedMs) / 1000.0)
            sessions.append(
                Session(
                    id: SessionID(id),
                    source: source,
                    phase: .idle,
                    cwd: directory,
                    title: DisplayNames.sessionTitle(
                        sessionTitle: title,
                        cwd: directory,
                        agentType: nil
                    ),
                    updatedAt: updatedAt
                )
            )
        }
        return sessions
    }

    /// Default DB locations (runtime probe only — tests pass explicit URLs).
    public static func defaultDatabaseURLs(home: String = NSHomeDirectory()) -> [URL] {
        let homeURL = URL(fileURLWithPath: home, isDirectory: true)
        return [
            homeURL.appendingPathComponent(".local/share/opencode/opencode.db"),
            homeURL.appendingPathComponent(".config/opencode/opencode.db"),
        ]
    }

    private static func stringColumn(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }
}

public enum OpenCodeAdapterError: Error, Equatable {
    case cannotOpen(String)
    case prepareFailed
}
