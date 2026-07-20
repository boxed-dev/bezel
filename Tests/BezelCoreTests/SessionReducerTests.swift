import Testing
import Foundation
import BezelCore

@Suite("SessionReducer")
struct SessionReducerTests {
    @Test func sessionStartGoesWorking() throws {
        let env = try payload(#"{"hook_event_name":"SessionStart","session_id":"s1","cwd":"/Users/x/proj"}"#)
        let s = SessionReducer.seed(from: env)
        #expect(s.phase == .working)
        #expect(s.title == "proj")
        #expect(s.id.rawValue == "s1")
    }

    @Test func permissionRequestWaits() throws {
        var s = Session(id: SessionID("s1"), phase: .working)
        let env = try payload(#"{"hook_event_name":"PermissionRequest","session_id":"s1","tool_name":"Bash"}"#)
        s = SessionReducer.apply(session: s, envelope: env)
        #expect(s.phase == .waitingPermission)
        #expect(s.lastTool == "Bash")
    }

    @Test func askUserQuestionWaits() throws {
        var s = Session(id: SessionID("s1"), phase: .working)
        let env = try payload(#"{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"AskUserQuestion"}"#)
        s = SessionReducer.apply(session: s, envelope: env)
        #expect(s.phase == .waitingQuestion)
    }

    @Test func exitPlanModeIsPlanReview() throws {
        var s = Session(id: SessionID("s1"), phase: .working)
        let env = try payload(#"{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"ExitPlanMode"}"#)
        s = SessionReducer.apply(session: s, envelope: env)
        #expect(s.phase == .planReview)
    }

    @Test func stopGoesIdleKeepsSessionVisible() throws {
        var s = Session(id: SessionID("s1"), phase: .working)
        let env = try payload(#"{"hook_event_name":"Stop","session_id":"s1"}"#)
        s = SessionReducer.apply(session: s, envelope: env)
        #expect(s.phase == .idle)
    }

    @Test func stopDoesNotClearWaitingPermission() throws {
        var s = Session(id: SessionID("s1"), phase: .waitingPermission)
        let env = try payload(#"{"hook_event_name":"Stop","session_id":"s1"}"#)
        s = SessionReducer.apply(session: s, envelope: env)
        #expect(s.phase == .waitingPermission)
    }

    @Test func sessionEndGoesDone() throws {
        var s = Session(id: SessionID("s1"), phase: .working)
        let env = try payload(#"{"hook_event_name":"SessionEnd","session_id":"s1"}"#)
        s = SessionReducer.apply(session: s, envelope: env)
        #expect(s.phase == .done)
    }

    @Test func doneIsNotResurrectedByLatePreToolUse() throws {
        var s = Session(id: SessionID("s1"), phase: .done)
        let env = try payload(#"{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"Bash"}"#)
        s = SessionReducer.apply(session: s, envelope: env)
        #expect(s.phase == .done)
    }

    @Test func doneIsNotResurrectedByStopOrPostToolUse() throws {
        var s = Session(id: SessionID("s1"), phase: .done)
        s = SessionReducer.apply(
            session: s,
            envelope: try payload(#"{"hook_event_name":"Stop","session_id":"s1"}"#)
        )
        #expect(s.phase == .done)
        s = SessionReducer.apply(
            session: s,
            envelope: try payload(#"{"hook_event_name":"PostToolUse","session_id":"s1","tool_name":"Bash"}"#)
        )
        #expect(s.phase == .done)
    }

    @Test func sessionStartRevivesDoneSession() throws {
        var s = Session(id: SessionID("s1"), phase: .done, cwd: "/Users/x/proj")
        let env = try payload(#"{"hook_event_name":"SessionStart","session_id":"s1","cwd":"/Users/x/proj"}"#)
        s = SessionReducer.apply(session: s, envelope: env)
        #expect(s.phase == .working)
    }

    @Test func afterDecisionReturnsWorking() {
        let s = Session(id: SessionID("s1"), phase: .waitingPermission)
        let next = SessionReducer.afterDecision(session: s)
        #expect(next.phase == .working)
    }

    @Test func waitingNotOverwrittenByGenericPreTool() throws {
        var s = Session(id: SessionID("s1"), phase: .waitingPermission)
        let env = try payload(#"{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"Bash"}"#)
        s = SessionReducer.apply(session: s, envelope: env)
        #expect(s.phase == .waitingPermission)
    }

    @Test func missingSessionIdUsesUnknown() throws {
        let env = try payload(#"{"hook_event_name":"SessionStart","cwd":"/tmp"}"#)
        let s = SessionReducer.seed(from: env)
        #expect(s.id == SessionID.unknown)
        #expect(s.id.rawValue == "unknown")
    }

    @Test func cursorShellHookIsNotLabeledClaude() throws {
        let env = try payload(#"""
        {
          "hook_event_name":"beforeShellExecution",
          "conversation_id":"conv-cursor-1",
          "command":"null;",
          "workspace_roots":["/Users/x/Vibe"]
        }
        """#)
        let s = SessionReducer.seed(from: env)
        #expect(s.source == .cursor)
        #expect(s.id.rawValue == "conv-cursor-1")
        #expect(s.cwd == "/Users/x/Vibe")
        #expect(s.lastToolDetail == nil)
        #expect(s.title == "Vibe")
        #expect(
            DisplayNames.placeLabel(
                sessionTitle: s.title,
                cwd: s.cwd,
                agentType: s.agentType,
                sourceName: "Cursor"
            ) == "Vibe"
        )
        #expect(DisplayNames.activitySummary(tool: s.lastTool, detail: s.lastToolDetail) == nil)
    }

    @Test func cursorShapedEventWinsOverClaudeSourceStamp() throws {
        let env = try payload(#"""
        {
          "hook_event_name":"beforeShellExecution",
          "conversation_id":"c1",
          "command":"echo hi",
          "agent_type":"Claude",
          "_source":"claude"
        }
        """#)
        let s = SessionReducer.seed(from: env)
        #expect(s.source == .cursor)
        #expect(s.agentType == nil)
        #expect(s.lastToolDetail == "echo hi")
        #expect(
            DisplayNames.placeLabel(
                sessionTitle: s.title,
                cwd: s.cwd,
                agentType: s.agentType,
                sourceName: "Cursor"
            ) != "Claude"
        )
    }

    @Test func deadCursorSessionDoesNotShowRunningNull() throws {
        let env = try payload(#"""
        {
          "hook_event_name":"beforeShellExecution",
          "conversation_id":"dead-1",
          "command":"null;",
          "agent_type":"Claude",
          "workspace_roots":["/Users/x/Vibe"],
          "_source":"claude"
        }
        """#)
        var s = SessionReducer.seed(from: env)
        #expect(s.source == .cursor)
        #expect(s.phase == .working)
        #expect(s.lastToolDetail == nil)

        // Simulate turn finished / stale row.
        s.phase = .idle
        s.lastToolDetail = "null;" // leftover junk from an older build
        s.agentType = "Claude"

        let primary = DisplayNames.placeLabel(
            sessionTitle: s.title,
            cwd: s.cwd,
            agentType: s.agentType,
            sourceName: "Cursor"
        )
        #expect(primary == "Vibe")
        #expect(primary != "Claude")

        let secondary = DisplayNames.sessionSecondaryLine(
            phase: s.phase,
            tool: "Bash",
            detail: s.lastToolDetail
        )
        #expect(secondary == "Idle")
        #expect(!secondary.lowercased().contains("running"))
        #expect(!secondary.lowercased().contains("null"))

        s.phase = .done
        #expect(
            DisplayNames.sessionSecondaryLine(
                phase: s.phase,
                tool: "Bash",
                detail: "null;"
            ) == "Done"
        )
    }

    private func payload(_ json: String) throws -> HookPayload {
        try HookPayload.parse(Data(json.utf8))
    }
}
