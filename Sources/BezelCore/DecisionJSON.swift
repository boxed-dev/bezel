import Foundation

/// Claude-compatible decision payloads returned on bridge stdout.
public enum DecisionJSON {
    public static func permissionAllow() -> Data {
        utf8(#"""
        {"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
        """#)
    }

    public static func permissionDeny(message: String = "Denied from Bezel") -> Data {
        let escaped = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return utf8(#"""
        {"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"\#(escaped)"}}}
        """#)
    }

    public static func emptyAck() -> Data {
        Data("{}".utf8)
    }

    public static func parseFailed() -> Data {
        Data(#"{"error":"parse_failed"}"#.utf8)
    }

    private static func utf8(_ s: String) -> Data {
        Data(s.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
    }
}
