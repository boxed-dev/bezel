import Testing
import Foundation
import BezelCore

@Suite("DisplayNames")
struct DisplayNamesTests {
    @Test func humanizesKebabAndPluginAgent() {
        #expect(DisplayNames.humanizeAgent("regression-guard") == "Regression Guard")
        #expect(DisplayNames.humanizeAgent("my-plugin:reviewer") == "Reviewer")
        #expect(DisplayNames.humanizeAgent("Explore") == "Explore")
    }

    @Test func prefersSessionTitleThenCwdThenAgent() {
        #expect(
            DisplayNames.sessionTitle(
                sessionTitle: "Ship hooks",
                cwd: "/Users/x/Vibe",
                agentType: "regression-guard",
                existing: nil
            ) == "Ship hooks"
        )
        #expect(
            DisplayNames.sessionTitle(
                sessionTitle: nil,
                cwd: "/Users/x/Vibe",
                agentType: "regression-guard",
                existing: nil
            ) == "Vibe"
        )
        #expect(
            DisplayNames.sessionTitle(
                sessionTitle: nil,
                cwd: nil,
                agentType: "regression-guard",
                existing: nil
            ) == "Regression Guard"
        )
    }

    @Test func payloadParsesAgentAndToolDetail() throws {
        let json = #"""
        {
          "hook_event_name":"PermissionRequest",
          "session_id":"abc-123",
          "cwd":"/Users/x/Vibe",
          "agent_type":"regression-guard",
          "session_title":"Hook polish",
          "tool_name":"Bash",
          "tool_input":{"command":"rtk ls supabase/migrations/ | tail -20"}
        }
        """#
        let p = try HookPayload.parse(Data(json.utf8))
        #expect(p.agentType == "regression-guard")
        #expect(p.sessionTitle == "Hook polish")
        #expect(p.toolDetail?.contains("rtk ls") == true)
        let s = SessionReducer.seed(from: p)
        #expect(s.title == "Hook polish")
        #expect(s.agentType == "regression-guard")
        #expect(s.lastToolDetail?.contains("rtk ls") == true)
    }

    @Test func permissionWithoutTitleUsesCwd() throws {
        let json = #"""
        {
          "hook_event_name":"PermissionRequest",
          "session_id":"58956517-dead-beef",
          "cwd":"/Users/x/my-app",
          "agent_type":"regression-guard",
          "tool_name":"Bash",
          "tool_input":{"command":"echo hi"}
        }
        """#
        let s = SessionReducer.seed(from: try HookPayload.parse(Data(json.utf8)))
        #expect(s.title == "my-app")
        #expect(s.agentType == "regression-guard")
    }
}
