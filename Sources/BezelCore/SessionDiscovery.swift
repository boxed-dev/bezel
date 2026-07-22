import Foundation

/// Runtime discovery roots for Codex JSONL + OpenCode SQLite.
/// Hooks remain phase truth; this only fills presence for SESSIONS.
public enum SessionDiscovery {
    /// Collect discovery-only rows. Skips `.done`. Missing roots → empty contribution.
    public static func collect(
        codexHome: URL?,
        openCodeDatabaseURL: URL?,
        limit: Int = CodexAdapter.defaultDiscoveryLimit
    ) -> [Session] {
        var found: [Session] = []
        if let codexHome {
            if let rows = try? CodexAdapter.discoverSessions(codexHome: codexHome, limit: limit) {
                found.append(contentsOf: rows.filter { $0.phase != .done })
            }
        }
        if let openCodeDatabaseURL {
            if let rows = try? OpenCodeAdapter.discoverSessions(
                databaseURL: openCodeDatabaseURL,
                limit: limit
            ) {
                found.append(contentsOf: rows.filter { $0.phase != .done })
            }
        }
        return found
    }

    /// Probe default home paths. Tests pass explicit URLs instead.
    /// Safe to call off the main actor — pure filesystem/SQLite I/O.
    public nonisolated static func collectFromHome(
        _ home: String = NSHomeDirectory()
    ) -> [Session] {
        let homeURL = URL(fileURLWithPath: home, isDirectory: true)
        let codexHome = homeURL.appendingPathComponent(".codex", isDirectory: true)
        let openCodeDB = OpenCodeAdapter.defaultDatabaseURLs(home: home)
            .first { FileManager.default.fileExists(atPath: $0.path) }
        return collect(
            codexHome: FileManager.default.fileExists(atPath: codexHome.path) ? codexHome : nil,
            openCodeDatabaseURL: openCodeDB
        )
    }
}
