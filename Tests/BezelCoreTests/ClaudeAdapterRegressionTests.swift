import Testing
import Foundation
import BezelCore

/// B4 — Claude hooks path regressions (SessionStart/End/Stop/PreToolUse phase truth).
@Suite("Claude adapter harden")
struct ClaudeAdapterRegressionTests {
    @Test func sessionPresence_claudeHookUpdatesPhase() throws {
        let start = try payload(#"{"hook_event_name":"SessionStart","session_id":"s1","cwd":"/Users/x/Vibe"}"#)
        #expect(SessionPresence.shouldCreateSession(
            event: .sessionStart,
            routeKind: start.routeKind,
            isTombstoned: false
        ))
        var session = AgentEventIngester.apply(envelope: start, existing: nil)
        #expect(session.source == .claude)
        #expect(session.phase == .working)
        #expect(SessionLabel.format(session: session) == "Claude · Vibe · working")

        session = AgentEventIngester.apply(
            envelope: try payload(#"{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"Bash"}"#),
            existing: session
        )
        #expect(session.phase == .working)

        session = AgentEventIngester.apply(
            envelope: try payload(#"{"hook_event_name":"PermissionRequest","session_id":"s1","tool_name":"Bash"}"#),
            existing: session
        )
        #expect(session.phase == .waitingPermission)
        #expect(SessionLabel.format(session: session) == "Claude · Vibe · waiting")

        session = SessionReducer.afterDecision(session: session)
        #expect(session.phase == .working)

        session = AgentEventIngester.apply(
            envelope: try payload(#"{"hook_event_name":"Stop","session_id":"s1"}"#),
            existing: session
        )
        #expect(session.phase == .idle)

        session = AgentEventIngester.apply(
            envelope: try payload(#"{"hook_event_name":"SessionEnd","session_id":"s1"}"#),
            existing: session
        )
        #expect(session.phase == .done)
    }

    @Test func claudeHookCommand_staysBareWithoutSourceEnv() {
        let cmd = HookDispatcher.commandLine(
            source: .claude,
            hookPath: ClaudeSettingsMerger.hookCommandPortable
        )
        #expect(cmd == ClaudeSettingsMerger.hookCommandPortable)
        #expect(ClaudeSettingsMerger.isBezelHookCommand(cmd))
    }

    @Test func claudeScript_defaultsSourceClaude() {
        let script = HookDispatcher.script(bridgePath: "/Users/x/.bezel/bezel-bridge")
        #expect(script.contains("SOURCE=\"${BEZEL_SOURCE:-claude}\""))
        #expect(script.contains("--source \"$SOURCE\""))
    }

    @Test func lateStopAfterSessionEndDoesNotResurrect() throws {
        var session = Session(id: SessionID("s1"), source: .claude, phase: .done, cwd: "/tmp/Vibe")
        session = AgentEventIngester.apply(
            envelope: try payload(#"{"hook_event_name":"Stop","session_id":"s1"}"#),
            existing: session
        )
        #expect(session.phase == .done)
        #expect(!SessionPresence.shouldCreateSession(
            event: .stop,
            routeKind: .event,
            isTombstoned: true
        ))
    }

    private func payload(_ json: String) throws -> HookPayload {
        try HookPayload.parse(Data(json.utf8))
    }
}
