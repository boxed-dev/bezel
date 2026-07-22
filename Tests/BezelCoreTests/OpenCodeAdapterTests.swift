import Testing
import Foundation
import BezelCore

@Suite("OpenCodeAdapter")
struct OpenCodeAdapterTests {
    @Test func readsSessionsFromFixtureDB() throws {
        let dbURL = try makeFixtureDB()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        // Archived rows are excluded — discovery is presence for live SESSIONS only.
        let sessions = try OpenCodeAdapter.discoverSessions(databaseURL: dbURL)
        #expect(sessions.count == 1)

        let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id.rawValue, $0) })
        let app = try #require(byID["ses_app1"])
        #expect(app.source == .opencode)
        #expect(app.cwd == "/Users/x/Projects/app")
        #expect(app.title == "Ship hooks")
        #expect(byID["ses_done"] == nil)
    }

    @Test func discoverSessions_respectsLimit() throws {
        let dbURL = try makeFixtureDB(liveCount: 12)
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let sessions = try OpenCodeAdapter.discoverSessions(databaseURL: dbURL, limit: 5)
        #expect(sessions.count == 5)
        #expect(sessions.allSatisfy { $0.phase != .done })
    }

    @Test func mapsOpenCodeStatusToPhase() {
        #expect(OpenCodeAdapter.phase(status: "active") == .working)
        #expect(OpenCodeAdapter.phase(status: "idle") == .idle)
        #expect(OpenCodeAdapter.phase(status: "completed") == .done)
        #expect(OpenCodeAdapter.phase(status: "archived") == .done)
        #expect(OpenCodeAdapter.phase(status: nil) == .idle)
        #expect(OpenCodeAdapter.phase(status: "unknown-status") == .idle)
    }

    @Test func sourceIsOpenCode() throws {
        let dbURL = try makeFixtureDB()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let sessions = try OpenCodeAdapter.discoverSessions(databaseURL: dbURL)
        #expect(sessions.allSatisfy { $0.source == .opencode })
        #expect(OpenCodeAdapter.source == .opencode)

        let labeled = Session(
            id: SessionID("ses_app1"),
            source: .opencode,
            phase: .done,
            cwd: "/Users/x/Projects/app",
            title: "Ship hooks"
        )
        #expect(SessionLabel.format(session: labeled) == "OpenCode · Ship hooks · done")
    }

    // MARK: - Fixtures

    private func makeFixtureDB(liveCount: Int = 1) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bezel-opencode-\(UUID().uuidString).db")
        var sql = """
        CREATE TABLE session (
          id TEXT PRIMARY KEY,
          project_id TEXT NOT NULL,
          slug TEXT NOT NULL,
          directory TEXT NOT NULL,
          title TEXT NOT NULL,
          version TEXT NOT NULL,
          time_created INTEGER NOT NULL,
          time_updated INTEGER NOT NULL,
          time_archived INTEGER
        );
        INSERT INTO session VALUES (
          'ses_app1','proj1','app','/Users/x/Projects/app','Ship hooks','1.0',
          1700000000000,1700000100000,NULL
        );
        INSERT INTO session VALUES (
          'ses_done','proj2','api','/Users/x/Projects/api','Done work','1.0',
          1700000000000,1700000200000,1700000300000
        );
        """
        if liveCount > 1 {
            for i in 2...liveCount {
                let ts = 1700000100000 + (i * 1000)
                sql += """
                INSERT INTO session VALUES (
                  'ses_extra_\(i)','proj1','app','/tmp/p\(i)','Extra \(i)','1.0',
                  1700000000000,\(ts),NULL
                );
                """
            }
        }
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
