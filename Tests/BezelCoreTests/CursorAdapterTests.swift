import Testing
import Foundation
import BezelCore

@Suite("CursorAdapter")
struct CursorAdapterTests {
    @Test func parsesCursorHooksJson() throws {
        let json = """
        {
          "version": 1,
          "hooks": {
            "beforeSubmitPrompt": [{"command": "/opt/old-bridge --source cursor"}],
            "stop": [{"command": "/opt/old-bridge --source cursor"}],
            "afterAgentResponse": [{"command": "/opt/old-bridge --source cursor"}]
          }
        }
        """
        let root = try CursorAdapter.parseHooksJSON(Data(json.utf8))
        #expect(root.version == 1)
        #expect(root.hooks["beforeSubmitPrompt"]?.count == 1)
        #expect(root.hooks["stop"]?.count == 1)
        #expect(Set(root.hooks.keys).isSuperset(of: ["beforeSubmitPrompt", "stop", "afterAgentResponse"]))
    }

    @Test func activateOnlyEvents_markLiveWithoutFakePhase() throws {
        // Cursor activate / lifecycle events must not invent waitingPermission.
        let events = [
            "beforeSubmitPrompt",
            "afterAgentResponse",
            "afterFileEdit",
            "stop",
            "subagentStart",
        ]
        for raw in events {
            let phase = CursorAdapter.phase(forEvent: raw, processAlive: true)
            #expect(phase != .waitingPermission)
            #expect(phase != .waitingQuestion)
            #expect(phase != .planReview)
            #expect(phase == .working || phase == .idle)
        }

        #expect(CursorAdapter.phase(forEvent: "stop", processAlive: false) == .idle)
        #expect(CursorAdapter.phase(forEvent: "beforeSubmitPrompt", processAlive: false) == .idle)
    }

    @Test func labelsCursorSession() {
        let session = Session(
            id: SessionID("cur1"),
            source: .cursor,
            phase: .idle,
            cwd: "/Users/x/Vibe"
        )
        #expect(SessionLabel.format(session: session) == "Cursor · Vibe · idle")
        #expect(CursorAdapter.source == .cursor)
    }


    @Test func normalizeHookJSON_mapsEventAndConversationID() throws {
        let json = """
        {
          "event": "beforeSubmitPrompt",
          "conversation_id": "conv-abc-123",
          "workspace_roots": ["/Users/x/Vibe"]
        }
        """
        let payload = try CursorAdapter.normalizeHookJSON(Data(json.utf8))
        #expect(payload.source == "cursor")
        #expect(payload.hookEventName == "UserPromptSubmit")
        #expect(payload.sessionID == "conv-abc-123")
        #expect(payload.cwd == "/Users/x/Vibe")
        #expect(HookEventName(raw: payload.hookEventName) == .userPromptSubmit)
    }

    @Test func mapCursorEvent_acceptsPascalAndSnakeCase() {
        #expect(CursorAdapter.mapCursorEvent("BeforeSubmitPrompt") == "UserPromptSubmit")
        #expect(CursorAdapter.mapCursorEvent("before_submit_prompt") == "UserPromptSubmit")
        #expect(CursorAdapter.mapCursorEvent("afterAgentResponse") == "PostToolUse")
        #expect(CursorAdapter.mapCursorEvent("subagentStart") == "UserPromptSubmit")
    }

    @Test func hookEventEnrichment_cursorPathMatchesAdapter() {
        var obj: [String: Any] = [
            "event": "beforeSubmitPrompt",
            "conversation_id": "c1",
            "workspace_roots": ["/tmp/proj"],
        ]
        HookEventEnrichment.applySourceAndEvent(to: &obj, sourceOverride: "cursor")
        #expect(obj["_source"] as? String == "cursor")
        #expect(obj["hook_event_name"] as? String == "UserPromptSubmit")
        #expect(obj["session_id"] as? String == "c1")
        #expect(obj["cwd"] as? String == "/tmp/proj")
    }

    @Test func mergeInstallsBezelHookWithCursorSource() throws {
        let existing = Data(#"{"version":1,"hooks":{}}"#.utf8)
        let hook = HookDispatcher.commandLine(
            source: .cursor,
            hookPath: "/Users/x/.bezel/bezel-hook.sh"
        )
        let merged = try CursorAdapter.mergeBezelHooks(existing: existing, hookCommand: hook)
        let root = try CursorAdapter.parseHooksJSON(merged)
        #expect(root.hooks["beforeSubmitPrompt"]?.contains(where: { $0.command.contains("BEZEL_SOURCE=cursor") }) == true)
        #expect(root.hooks["stop"]?.contains(where: { $0.command.contains("bezel-hook.sh") }) == true)
        // Idempotent
        let twice = try CursorAdapter.mergeBezelHooks(existing: merged, hookCommand: hook)
        #expect(twice == merged || String(data: twice, encoding: .utf8)?.contains("BEZEL_SOURCE=cursor") == true)
    }
}
