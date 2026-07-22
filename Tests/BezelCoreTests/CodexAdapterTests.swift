import Testing
import Foundation
import BezelCore

@Suite("CodexAdapter")
struct CodexAdapterTests {
    @Test func normalizesCodexEventNames() throws {
        let cases: [(String, String)] = [
            ("session_start", "SessionStart"),
            ("SessionStart", "SessionStart"),
            ("pre_tool_use", "PreToolUse"),
            ("permission_request", "PermissionRequest"),
            ("stop", "Stop"),
            ("user_prompt_submit", "UserPromptSubmit"),
        ]
        for (raw, expected) in cases {
            let json = #"{"hook_event_name":"\#(raw)","session_id":"s1","cwd":"/tmp/api"}"#
            let payload = try CodexAdapter.normalizeHookJSON(Data(json.utf8))
            #expect(payload.hookEventName == expected)
            #expect(payload.source == "codex")
            #expect(payload.sessionID == "s1")
        }
    }

    @Test func discoversSessionsUnderCodexHome() throws {
        let home = try makeTempCodexHome()
        defer { try? FileManager.default.removeItem(atPath: home) }

        let sessions = try CodexAdapter.discoverSessions(codexHome: URL(fileURLWithPath: home))
        #expect(sessions.count == 2)

        let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id.rawValue, $0) })
        #expect(byID["019f2801-aaaa-bbbb-cccc-ddddeeeeffff"] != nil)
        #expect(byID["019f2801-1111-2222-3333-444455556666"] != nil)

        let api = try #require(byID["019f2801-aaaa-bbbb-cccc-ddddeeeeffff"])
        #expect(api.source == .codex)
        #expect(api.cwd == "/Users/x/Projects/api")
        #expect(api.phase == .idle)
    }

    @Test func discoverSessions_capsToRecentLimit() throws {
        let home = try makeTempCodexHome(extraRollouts: 40)
        defer { try? FileManager.default.removeItem(atPath: home) }

        let sessions = try CodexAdapter.discoverSessions(
            codexHome: URL(fileURLWithPath: home),
            limit: 8
        )
        #expect(sessions.count == 8)
    }

    @Test func labelsCodexSession() throws {
        let session = Session(
            id: SessionID("c1"),
            source: .codex,
            phase: .working,
            cwd: "/Users/x/Projects/api"
        )
        #expect(SessionLabel.format(session: session) == "Codex · api · working")
        #expect(CodexAdapter.source == .codex)
    }

    @Test func mergeHooksJSON_emitsCodexSourceCommand() throws {
        let hook = HookDispatcher.commandLine(
            source: .codex,
            hookPath: "$HOME/.bezel/bezel-hook.sh"
        )
        let merged = try CodexAdapter.mergeHooksJSON(existing: nil, hookCommand: hook)
        let root = try JSONSerialization.jsonObject(with: merged) as? [String: Any]
        let hooks = root?["hooks"] as? [String: Any]
        let start = hooks?["SessionStart"] as? [[String: Any]]
        let cmd = ((start?.first?["hooks"] as? [[String: Any]])?.first)?["command"] as? String
        #expect(cmd?.contains("BEZEL_SOURCE=codex") == true)
        let twice = try CodexAdapter.mergeHooksJSON(existing: merged, hookCommand: hook)
        let root2 = try JSONSerialization.jsonObject(with: twice) as? [String: Any]
        let hooks2 = root2?["hooks"] as? [String: Any]
        let start2 = hooks2?["SessionStart"] as? [[String: Any]]
        #expect(start2?.count == 1)
    }

    // MARK: - Fixtures

    private func makeTempCodexHome(extraRollouts: Int = 0) throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bezel-codex-\(UUID().uuidString)", isDirectory: true)
        let day = root
            .appendingPathComponent("sessions/2026/07/03", isDirectory: true)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)

        let a = """
        {"timestamp":"2026-07-03T12:43:47.040Z","type":"session_meta","payload":{"id":"019f2801-aaaa-bbbb-cccc-ddddeeeeffff","cwd":"/Users/x/Projects/api","cli_version":"0.140.0"}}
        {"timestamp":"2026-07-03T12:43:47.043Z","type":"event_msg","payload":{"type":"task_started"}}
        """
        let b = """
        {"timestamp":"2026-07-03T13:00:00.000Z","type":"session_meta","payload":{"id":"019f2801-1111-2222-3333-444455556666","cwd":"/Users/x/Vibe","cli_version":"0.140.0"}}
        """
        try a.write(
            to: day.appendingPathComponent("rollout-2026-07-03T18-13-47-019f2801-aaaa-bbbb-cccc-ddddeeeeffff.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        try b.write(
            to: day.appendingPathComponent("rollout-2026-07-03T18-14-00-019f2801-1111-2222-3333-444455556666.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        for i in 0..<extraRollouts {
            let id = String(format: "019f2801-%04d-0000-0000-000000000000", i)
            let line = #"{"timestamp":"2026-07-03T14:00:00.000Z","type":"session_meta","payload":{"id":"\#(id)","cwd":"/tmp/p\#(i)"}}"#
            try (line + "\n").write(
                to: day.appendingPathComponent("rollout-extra-\(i).jsonl"),
                atomically: true,
                encoding: .utf8
            )
        }
        return root.path
    }
}
