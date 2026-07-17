import Foundation

/// Claude-compatible decision payloads returned on bridge stdout.
public enum DecisionJSON {
    public static func permissionAllow() -> Data {
        utf8(#"""
        {"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
        """#)
    }

    public static func permissionDeny(message: String = "Denied from Bezel") -> Data {
        encodePermissionDeny(message: message)
    }

    /// PreToolUse allow without `updatedInput` (generic tools).
    public static func preToolUseAllow(reason: String = "Allowed from Bezel") -> Data {
        encodePreToolUse(decision: "allow", reason: reason)
    }

    /// PreToolUse deny — required for AskUserQuestion / ExitPlanMode (must not use PermissionRequest shape).
    public static func preToolUseDeny(reason: String = "Denied from Bezel") -> Data {
        encodePreToolUse(decision: "deny", reason: reason)
    }

    /// Kind-correct deny for blocking routes (timeouts, Bezel-down, encode failures).
    /// PreToolUse (AskUserQuestion / ExitPlanMode) must not use PermissionRequest shape.
    public static func deny(
        for kind: RouteKind,
        hookEventName: String = "",
        message: String
    ) -> Data {
        switch kind {
        case .question:
            return preToolUseDeny(reason: message)
        case .permission:
            if hookEventName == "PreToolUse" {
                return preToolUseDeny(reason: message)
            }
            return permissionDeny(message: message)
        case .event:
            return emptyAck()
        }
    }

    public static func emptyAck() -> Data {
        Data("{}".utf8)
    }

    public static func parseFailed() -> Data {
        Data(#"{"error":"parse_failed"}"#.utf8)
    }

    /// RFC-8259 JSON string escape (control chars, quotes, backslashes).
    public static func escapeJSONString(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count + 8)
        for ch in s {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if let scalar = ch.unicodeScalars.first, scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.append(ch)
                }
            }
        }
        return out
    }

    private static func encodePermissionDeny(message: String) -> Data {
        let root: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": [
                    "behavior": "deny",
                    "message": message,
                ] as [String: Any],
            ] as [String: Any],
        ]
        return (try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]))
            ?? utf8(#"""
            {"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from Bezel"}}}
            """#)
    }

    private static func encodePreToolUse(decision: String, reason: String) -> Data {
        let root: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PreToolUse",
                "permissionDecision": decision,
                "permissionDecisionReason": reason,
            ] as [String: Any],
        ]
        return (try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]))
            ?? utf8(#"""
            {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Denied from Bezel"}}
            """#)
    }

    private static func utf8(_ s: String) -> Data {
        Data(s.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
    }
}
