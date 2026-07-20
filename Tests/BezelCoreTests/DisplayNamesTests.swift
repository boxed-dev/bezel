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


    @Test func rejectsUUIDAsSessionTitle() {
        #expect(
            DisplayNames.sessionTitle(
                sessionTitle: "98955a4b-dead-beef-cafe-0123456789ab",
                cwd: "/Users/x/Vibe",
                agentType: "Explore",
                existing: nil
            ) == "Vibe"
        )
        #expect(DisplayNames.looksLikeSessionID("98955a4b…"))
        #expect(
            DisplayNames.placeLabel(
                sessionTitle: "98955a4b…",
                cwd: nil,
                agentType: nil,
                sourceName: "Claude"
            ) == "Claude"
        )
    }

    @Test func summarizesBashPackageScript() {
        #expect(
            DisplayNames.activitySummary(
                tool: "Bash",
                detail: "cd /Users/rishabh/Vibe && bash scripts/package-bezel.sh"
            ) == "Packaging Bezel"
        )
    }

    @Test func stripsCdAndCapsLength() {
        let summary = DisplayNames.activitySummary(
            tool: "Bash",
            detail: "cd /tmp/project && " + String(repeating: "echo hello-world ", count: 20),
            maxLength: 48
        )
        #expect(summary != nil)
        #expect(!(summary?.hasPrefix("cd ") ?? true))
        #expect((summary?.count ?? 0) <= 48)
    }

    @Test func summarizesEditTool() {
        #expect(
            DisplayNames.activitySummary(
                tool: "Edit",
                detail: "/Users/x/Vibe/Sources/Bezel/NotchController.swift"
            ) == "Editing NotchController.swift"
        )
    }

    @Test func activitySummaryRejectsNullJunk() {
        #expect(DisplayNames.activitySummary(tool: nil, detail: "null") == nil)
        #expect(DisplayNames.activitySummary(tool: nil, detail: "null;") == nil)
        #expect(DisplayNames.activitySummary(tool: nil, detail: nil) == nil)
        #expect(DisplayNames.activitySummary(tool: nil, detail: "") == nil)
        #expect(DisplayNames.activitySummary(tool: nil, detail: "   ") == nil)
        #expect(DisplayNames.activitySummary(tool: nil, detail: ";") == nil)
        #expect(DisplayNames.activitySummary(tool: "Bash", detail: "null;") == "Running command")
        let junk = DisplayNames.activitySummary(tool: "Bash", detail: "null;")
        #expect(junk != "Running null;")
        #expect(junk != "Running null")
        #expect(!(junk?.contains("null") ?? false))
    }

    @Test func placeLabelPrefersCursorSourceOverClaudeBrandAgent() {
        #expect(
            DisplayNames.placeLabel(
                sessionTitle: nil,
                cwd: nil,
                agentType: "Claude",
                sourceName: "Cursor"
            ) == "Cursor"
        )
        #expect(
            DisplayNames.placeLabel(
                sessionTitle: "Claude",
                cwd: nil,
                agentType: nil,
                sourceName: "Cursor"
            ) == "Cursor"
        )
        #expect(
            DisplayNames.placeLabel(
                sessionTitle: nil,
                cwd: nil,
                agentType: nil,
                sourceName: "Cursor"
            ) == "Cursor"
        )
        #expect(
            DisplayNames.placeLabel(
                sessionTitle: nil,
                cwd: "/Users/x/Vibe",
                agentType: "Claude",
                sourceName: "Cursor"
            ) == "Vibe"
        )
    }

    @Test func sessionSecondaryLineIgnoresActivityWhenIdleOrDone() {
        #expect(
            DisplayNames.sessionSecondaryLine(
                phase: .idle,
                tool: "Bash",
                detail: "null;"
            ) == "Idle"
        )
        #expect(
            DisplayNames.sessionSecondaryLine(
                phase: .done,
                tool: "Bash",
                detail: "npm test"
            ) == "Done"
        )
        #expect(
            DisplayNames.sessionSecondaryLine(
                phase: .working,
                tool: "Bash",
                detail: "null;"
            ) == "Running command"
        )
        #expect(
            DisplayNames.sessionSecondaryLine(
                phase: .working,
                tool: nil,
                detail: "null;"
            ) == "Working"
        )
    }

    @Test func sessionTitleRejectsBrandExistingLabel() {
        #expect(
            DisplayNames.sessionTitle(
                sessionTitle: nil,
                cwd: "/Users/x/Vibe",
                agentType: "Claude",
                existing: "Claude"
            ) == "Vibe"
        )
    }

}
