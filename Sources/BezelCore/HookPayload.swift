import Foundation

/// Parsed hook JSON with the fields Bezel cares about.
public struct HookPayload: Sendable {
    public var hookEventName: String
    public var sessionID: String?
    public var toolName: String?
    public var cwd: String?
    public var source: String?
    public var question: String?
    public var rawJSON: Data

    public var routeKind: RouteKind {
        PermissionRouting.routeKind(
            hookEventName: hookEventName,
            toolName: toolName,
            source: source,
            question: question
        )
    }

    public static func parse(_ data: Data) throws -> HookPayload {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookPayloadError.invalidJSON
        }

        let event = string(in: obj, keys: [
            "hook_event_name", "hookEventName", "eventName", "event",
        ]) ?? "Unknown"

        let session = string(in: obj, keys: [
            "session_id", "sessionId", "conversationId",
        ])

        let tool = string(in: obj, keys: ["tool_name", "toolName"])
            ?? nestedString(obj, path: ["toolCall", "name"])

        let cwd = string(in: obj, keys: ["cwd"])
        let source = string(in: obj, keys: ["_source", "source"])
        let question = string(in: obj, keys: ["question"])

        return HookPayload(
            hookEventName: EventNormalizer.pascalCase(event),
            sessionID: session,
            toolName: tool,
            cwd: cwd,
            source: source,
            question: question,
            rawJSON: data
        )
    }

    private static func string(in obj: [String: Any], keys: [String]) -> String? {
        for k in keys {
            if let s = obj[k] as? String, !s.isEmpty { return s }
        }
        return nil
    }

    private static func nestedString(_ obj: [String: Any], path: [String]) -> String? {
        var current: Any = obj
        for key in path {
            guard let dict = current as? [String: Any], let next = dict[key] else { return nil }
            current = next
        }
        return current as? String
    }
}

public enum HookPayloadError: Error {
    case invalidJSON
}
