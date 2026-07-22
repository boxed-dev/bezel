import Testing
import Foundation
import BezelCore

@Suite("SessionDiscovery")
struct SessionDiscoveryTests {
    @Test func mergeDiscovery_addsMissingAndKeepsHookPhase() {
        let hookOwned = Session(
            id: SessionID("shared"),
            source: .codex,
            phase: .working,
            cwd: "/tmp/old",
            title: "live"
        )
        let discovered = [
            Session(
                id: SessionID("shared"),
                source: .codex,
                phase: .idle,
                cwd: "/tmp/project",
                title: "from-jsonl"
            ),
            Session(
                id: SessionID("new-oc"),
                source: .opencode,
                phase: .idle,
                cwd: "/tmp/app",
                title: "opencode"
            ),
        ]
        let merged = AgentEventIngester.mergeDiscovery(
            discovered: discovered,
            into: [hookOwned.id: hookOwned]
        )
        #expect(merged[SessionID("shared")]?.phase == .working)
        #expect(merged[SessionID("shared")]?.cwd == "/tmp/old")
        #expect(merged[SessionID("new-oc")]?.source == .opencode)
        #expect(merged.count == 2)
    }

    @Test func mergeDiscovery_prunesStaleDiscoveryIdleSessions() {
        let stale = Session(
            id: SessionID("stale-codex"),
            source: .codex,
            phase: .idle,
            cwd: "/tmp/old"
        )
        let hookLive = Session(
            id: SessionID("hook-codex"),
            source: .codex,
            phase: .working,
            cwd: "/tmp/live"
        )
        let claude = Session(
            id: SessionID("claude-1"),
            source: .claude,
            phase: .idle,
            cwd: "/tmp/claude"
        )
        let discovered = [
            Session(
                id: SessionID("fresh-oc"),
                source: .opencode,
                phase: .idle,
                cwd: "/tmp/app"
            ),
        ]
        let merged = AgentEventIngester.mergeDiscovery(
            discovered: discovered,
            into: [
                stale.id: stale,
                hookLive.id: hookLive,
                claude.id: claude,
            ]
        )
        #expect(merged[SessionID("stale-codex")] == nil)
        #expect(merged[SessionID("hook-codex")]?.phase == .working)
        #expect(merged[SessionID("claude-1")] != nil)
        #expect(merged[SessionID("fresh-oc")]?.source == .opencode)
    }


    @Test func mergeDiscovery_skipsTombstonedIDs() {
        let ended = SessionID("ended-codex")
        let discovered = [
            Session(
                id: ended,
                source: .codex,
                phase: .idle,
                cwd: "/tmp/resurrect"
            ),
            Session(
                id: SessionID("alive-oc"),
                source: .opencode,
                phase: .idle,
                cwd: "/tmp/app"
            ),
        ]
        let merged = AgentEventIngester.mergeDiscovery(
            discovered: discovered,
            into: [:],
            tombstonedIDs: [ended]
        )
        #expect(merged[ended] == nil)
        #expect(merged[SessionID("alive-oc")]?.source == .opencode)
    }

    @Test func collect_readsCodexAndOpenCodeRoots() throws {
        let codexHome = try makeTempCodexHome()
        let dbURL = try makeTempOpenCodeDB()
        defer {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: codexHome))
            try? FileManager.default.removeItem(at: dbURL)
        }

        let found = SessionDiscovery.collect(
            codexHome: URL(fileURLWithPath: codexHome),
            openCodeDatabaseURL: dbURL
        )
        let sources = Set(found.map(\.source))
        #expect(sources.contains(.codex))
        #expect(sources.contains(.opencode))
        #expect(found.allSatisfy { $0.phase != .done })
        #expect(found.contains { $0.id.rawValue == "disc-codex-1" })
        #expect(found.contains { $0.id.rawValue == "disc-oc-1" })
        #expect(!found.contains { $0.id.rawValue == "disc-oc-done" })
    }

    // MARK: - Fixtures

    private func makeTempCodexHome() throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bezel-disc-codex-\(UUID().uuidString)", isDirectory: true)
        let day = root.appendingPathComponent("sessions/2026/07/03", isDirectory: true)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let line = #"{"timestamp":"2026-07-03T12:00:00Z","type":"session_meta","payload":{"id":"disc-codex-1","cwd":"/Users/x/Projects/api","thread_name":"api"}}"#
        try (line + "\n").write(
            to: day.appendingPathComponent("rollout-disc.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        return root.path
    }

    private func makeTempOpenCodeDB() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bezel-disc-oc-\(UUID().uuidString).db")
        let sql = """
        CREATE TABLE session (
          id TEXT PRIMARY KEY,
          directory TEXT,
          title TEXT,
          time_updated INTEGER,
          time_archived INTEGER
        );
        INSERT INTO session VALUES ('disc-oc-1','/tmp/app','app',1720000000000,NULL);
        INSERT INTO session VALUES ('disc-oc-done','/tmp/old','old',1710000000000,1720000000000);
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [url.path]
        let pipe = Pipe()
        process.standardInput = pipe
        try process.run()
        pipe.fileHandleForWriting.write(Data(sql.utf8))
        try pipe.fileHandleForWriting.close()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return url
    }
}
