import Foundation

/// Claude decision payloads for ExitPlanMode plan review.
public enum PlanReviewEncoder {
    public static func approve(
        plan: String,
        planFilePath: String?,
        reason: String = "Approved plan from Bezel",
        hookEventName: String = "PreToolUse"
    ) throws -> Data {
        if hookEventName == "PermissionRequest" {
            return try encodePermission(behavior: "allow", message: reason)
        }
        var updatedInput: [String: Any] = ["plan": plan]
        if let planFilePath, !planFilePath.isEmpty {
            updatedInput["planFilePath"] = planFilePath
        }

        let root: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "permissionDecisionReason": reason,
                "updatedInput": updatedInput,
            ] as [String: Any],
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    public static func reject(
        reason: String = "Rejected plan from Bezel",
        hookEventName: String = "PreToolUse"
    ) -> Data {
        if hookEventName == "PermissionRequest" {
            return (try? encodePermission(behavior: "deny", message: reason))
                ?? DecisionJSON.permissionDeny(message: reason)
        }
        return DecisionJSON.preToolUseDeny(reason: reason)
    }

    private static func encodePermission(behavior: String, message: String) throws -> Data {
        var decision: [String: Any] = ["behavior": behavior]
        if behavior == "deny" {
            decision["message"] = message
        }
        let root: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decision,
            ] as [String: Any],
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }
}
