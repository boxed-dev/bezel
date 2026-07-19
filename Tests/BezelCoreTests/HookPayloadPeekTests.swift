import Testing
import Foundation
import BezelCore

@Suite("HookPayloadPeek")
struct HookPayloadPeekTests {
    @Test func oversizedQuestionUsesPreToolUseDenyShape() throws {
        var json = #"{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","session_id":"s1"}"#
        json += String(repeating: "x", count: 200)
        let data = Data(json.utf8)
        let deny = HookPayloadPeek.denyResponse(for: data, message: "Payload too large")
        let root = try JSONSerialization.jsonObject(with: deny) as? [String: Any]
        let hook = root?["hookSpecificOutput"] as? [String: Any]
        #expect(hook?["hookEventName"] as? String == "PreToolUse")
        #expect(hook?["permissionDecision"] as? String == "deny")
        #expect(hook?["permissionDecisionReason"] as? String == "Payload too large")
        #expect(hook?["decision"] == nil)
    }

    @Test func oversizedPermissionUsesPermissionDenyShape() throws {
        var json = #"{"hook_event_name":"PermissionRequest","tool_name":"Bash","session_id":"s1"}"#
        json += String(repeating: " ", count: 50)
        let data = Data(json.utf8)
        let deny = HookPayloadPeek.denyResponse(for: data, message: "Payload too large")
        let root = try JSONSerialization.jsonObject(with: deny) as? [String: Any]
        let hook = root?["hookSpecificOutput"] as? [String: Any]
        let decision = hook?["decision"] as? [String: Any]
        #expect(hook?["hookEventName"] as? String == "PermissionRequest")
        #expect(decision?["behavior"] as? String == "deny")
        #expect(decision?["message"] as? String == "Payload too large")
    }

    @Test func peekRouteKindFromTruncatedAskUserQuestion() {
        let truncated = Data(#"{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","questions":[{"# .utf8)
        let peeked = HookPayloadPeek.routeKind(from: truncated)
        #expect(peeked?.kind == .question)
        #expect(peeked?.hookEventName == "PreToolUse")
    }
}
