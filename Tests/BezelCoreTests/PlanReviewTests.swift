import Testing
import Foundation
import BezelCore

@Suite("PlanInputParser")
struct PlanInputParserTests {
    @Test func parsesPlanAndFilePath() {
        let input: [String: Any] = [
            "plan": "## Ship it\n1. Build\n2. Test",
            "planFilePath": "/tmp/plans/ship.md",
        ]
        let content = PlanInputParser.parse(fromToolInput: input)
        #expect(content.plan.contains("Ship it"))
        #expect(content.planFilePath == "/tmp/plans/ship.md")
        #expect(content.displayBody.contains("Ship it"))
    }

    @Test func fallsBackToFilePathWhenPlanEmpty() {
        let content = PlanInputParser.parse(fromToolInput: [
            "planFilePath": "/tmp/plans/empty.md",
        ])
        #expect(content.plan.isEmpty)
        #expect(content.displayBody.contains("/tmp/plans/empty.md"))
    }

    @Test func parsesFromRawHookJSON() {
        let json = #"""
        {"hook_event_name":"PreToolUse","tool_name":"ExitPlanMode","tool_input":{"plan":"Do the thing","planFilePath":"/p.md"}}
        """#
        let content = PlanInputParser.parse(from: Data(json.utf8))
        #expect(content.plan == "Do the thing")
        #expect(content.planFilePath == "/p.md")
    }
}

@Suite("PlanReviewEncoder")
struct PlanReviewEncoderTests {
    @Test func approveEchoesPlanInUpdatedInput() throws {
        let data = try PlanReviewEncoder.approve(
            plan: "## Refactor\n1. Extract",
            planFilePath: "/tmp/plan.md"
        )
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hook = root?["hookSpecificOutput"] as? [String: Any]
        #expect(hook?["hookEventName"] as? String == "PreToolUse")
        #expect(hook?["permissionDecision"] as? String == "allow")
        let updated = hook?["updatedInput"] as? [String: Any]
        #expect(updated?["plan"] as? String == "## Refactor\n1. Extract")
        #expect(updated?["planFilePath"] as? String == "/tmp/plan.md")
    }

    @Test func rejectUsesPreToolUseDeny() throws {
        let data = PlanReviewEncoder.reject(reason: "Needs more detail")
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hook = root?["hookSpecificOutput"] as? [String: Any]
        #expect(hook?["hookEventName"] as? String == "PreToolUse")
        #expect(hook?["permissionDecision"] as? String == "deny")
        #expect(hook?["permissionDecisionReason"] as? String == "Needs more detail")
    }

    @Test func approvePermissionRequestShape() throws {
        let data = try PlanReviewEncoder.approve(
            plan: "do it",
            planFilePath: nil,
            hookEventName: "PermissionRequest"
        )
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hook = root?["hookSpecificOutput"] as? [String: Any]
        #expect(hook?["hookEventName"] as? String == "PermissionRequest")
        let decision = hook?["decision"] as? [String: Any]
        #expect(decision?["behavior"] as? String == "allow")
        #expect(hook?["permissionDecision"] == nil)
    }

    @Test func rejectPermissionRequestShape() throws {
        let data = PlanReviewEncoder.reject(reason: "no", hookEventName: "PermissionRequest")
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hook = root?["hookSpecificOutput"] as? [String: Any]
        #expect(hook?["hookEventName"] as? String == "PermissionRequest")
        let decision = hook?["decision"] as? [String: Any]
        #expect(decision?["behavior"] as? String == "deny")
    }

    @Test func denyForExitPlanModeUsesPreToolUseShape() throws {
        let data = DecisionJSON.deny(
            for: .permission,
            hookEventName: "PreToolUse",
            message: "Timed out"
        )
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hook = root?["hookSpecificOutput"] as? [String: Any]
        #expect(hook?["permissionDecision"] as? String == "deny")
        #expect(hook?["hookEventName"] as? String == "PreToolUse")
    }
}
