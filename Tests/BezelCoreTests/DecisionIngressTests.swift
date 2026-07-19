import Testing
import Foundation
import BezelCore

@Suite("DecisionIngress")
struct DecisionIngressTests {
    @Test func permissionRequest() throws {
        let p = try HookPayload.parse(Data(#"{"hook_event_name":"PermissionRequest","session_id":"s1","tool_name":"Bash"}"#.utf8))
        let a = DecisionIngress.attention(for: p)
        #expect(a?.kind == .permission)
        #expect(a?.toolName == "Bash")
    }

    @Test func askUserQuestion() throws {
        let json = #"""
        {"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Ship?","options":[{"label":"Yes"}]}]}}
        """#
        let p = try HookPayload.parse(Data(json.utf8))
        let a = DecisionIngress.attention(for: p)
        #expect(a?.kind == .question)
        #expect(a?.questions.first?.question == "Ship?")
    }

    @Test func exitPlanMode() throws {
        let json = #"""
        {"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"ExitPlanMode","tool_input":{"plan":"Do it"}}
        """#
        let p = try HookPayload.parse(Data(json.utf8))
        let a = DecisionIngress.attention(for: p)
        #expect(a?.kind == .planReview)
        #expect(a?.plan?.plan == "Do it")
    }

    @Test func sessionStartIsNil() throws {
        let p = try HookPayload.parse(Data(#"{"hook_event_name":"SessionStart","session_id":"s1"}"#.utf8))
        #expect(DecisionIngress.attention(for: p) == nil)
    }

    @Test func notificationWithQuestionIsNil() throws {
        let json = #"""
        {"hook_event_name":"Notification","session_id":"s1","question":"Claude needs your attention"}
        """#
        let p = try HookPayload.parse(Data(json.utf8))
        #expect(p.routeKind == .event)
        #expect(DecisionIngress.attention(for: p) == nil)
    }
}
