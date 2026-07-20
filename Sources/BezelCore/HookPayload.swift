import Foundation

/// Parsed hook JSON with the fields Bezel cares about.
public struct HookPayload: Sendable {
    public var hookEventName: String
    public var sessionID: String?
    public var toolName: String?
    public var cwd: String?
    public var source: String?
    public var question: String?
    /// Claude `/rename` or SessionStart `session_title`.
    public var sessionTitle: String?
    /// Subagent / `--agent` name (e.g. `regression-guard`).
    public var agentType: String?
    public var agentID: String?
    /// Bash command / tool description from `tool_input`.
    public var toolDetail: String?
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
            "session_id", "sessionId", "conversation_id", "conversationId",
        ])

        let tool = string(in: obj, keys: ["tool_name", "toolName"])
            ?? nestedString(obj, path: ["toolCall", "name"])

        let cwd = string(in: obj, keys: ["cwd"])
            ?? firstWorkspaceRoot(obj)
        // Resolve against the raw vendor event name (before PascalCase normalization).
        // Cursor-shaped events win over a stale `_source=claude` stamp.
        let source = AgentSource.resolve(
            raw: string(in: obj, keys: ["_source", "source"]),
            hookEventName: event
        )?.rawValue
        let question = string(in: obj, keys: ["question"])
        let sessionTitle = string(in: obj, keys: ["session_title", "sessionTitle"])
        let agentType = string(in: obj, keys: ["agent_type", "agentType"])
        let agentID = string(in: obj, keys: ["agent_id", "agentId"])
        let toolDetail = toolDetail(from: obj)

        return HookPayload(
            hookEventName: EventNormalizer.pascalCase(event),
            sessionID: session,
            toolName: tool,
            cwd: cwd,
            source: source,
            question: question,
            sessionTitle: sessionTitle,
            agentType: agentType,
            agentID: agentID,
            toolDetail: toolDetail,
            rawJSON: data
        )
    }

    private static func string(in obj: [String: Any], keys: [String]) -> String? {
        for k in keys {
            if let s = obj[k] as? String, !s.isEmpty { return s }
        }
        return nil
    }

    private static func toolDetail(from obj: [String: Any]) -> String? {
        // Cursor shell hooks put `command` at the top level (not under tool_input).
        if let top = meaningfulDetail(obj["command"] as? String) { return top }

        let input = (obj["tool_input"] as? [String: Any])
            ?? (obj["toolInput"] as? [String: Any])
        if let input {
            if let command = meaningfulDetail(input["command"] as? String) { return command }
            if let desc = meaningfulDetail(input["description"] as? String) { return desc }
            if let file = meaningfulDetail(input["file_path"] as? String)
                ?? meaningfulDetail(input["filePath"] as? String)
            {
                return (file as NSString).lastPathComponent
            }
        }
        return nil
    }

    /// Reject empty / placeholder serializer junk (`null`, `null;`, bare `;`).
    private static func meaningfulDetail(_ value: String?) -> String? {
        guard var t = value?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else {
            return nil
        }
        while t.hasSuffix(";") {
            t = String(t.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !t.isEmpty else { return nil }
        let lower = t.lowercased()
        if ["null", "nil", "none", "undefined", "n/a", "na", "(null)", "<null>"].contains(lower) {
            return nil
        }
        return t
    }

    private static func firstWorkspaceRoot(_ obj: [String: Any]) -> String? {
        let roots = (obj["workspace_roots"] as? [String])
            ?? (obj["workspaceRoots"] as? [String])
        guard let root = roots?.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !root.isEmpty
        else { return nil }
        return root
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
