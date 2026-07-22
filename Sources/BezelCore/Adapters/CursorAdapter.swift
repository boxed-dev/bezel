import Foundation

/// Cursor IDE adapter: parse/merge `~/.cursor/hooks.json` with honest phases only.
///
/// Cursor hooks are activate/lifecycle oriented — never invent `waitingPermission`.
public enum CursorAdapter {
    public static let source: AgentSource = .cursor

    /// Events Bezel registers for presence/liveness (not permission blocking).
    public static let managedEvents: [String] = [
        "beforeSubmitPrompt",
        "afterAgentResponse",
        "afterFileEdit",
        "stop",
        "subagentStart",
        "subagentStop",
    ]

    public struct HooksRoot: Sendable, Equatable {
        public var version: Int
        public var hooks: [String: [HookEntry]]
    }

    public struct HookEntry: Sendable, Equatable {
        public var command: String
    }

    public static func parseHooksJSON(_ data: Data) throws -> HooksRoot {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookPayloadError.invalidJSON
        }
        let version = (obj["version"] as? Int) ?? 1
        let rawHooks = obj["hooks"] as? [String: Any] ?? [:]
        var hooks: [String: [HookEntry]] = [:]
        for (name, value) in rawHooks {
            guard let list = value as? [[String: Any]] else { continue }
            hooks[name] = list.compactMap { entry in
                guard let command = entry["command"] as? String, !command.isEmpty else { return nil }
                return HookEntry(command: command)
            }
        }
        return HooksRoot(version: version, hooks: hooks)
    }

    /// Honest phase from Cursor lifecycle + process liveness — never fake permission waits.
    public static func phase(forEvent raw: String, processAlive: Bool) -> SessionPhase {
        guard processAlive else { return .idle }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "stop", "subagentstop":
            return .idle
        case "beforesubmitprompt", "afteragentresponse", "afterfileedit",
             "aftershellexecution", "beforeshellexecution",
             "subagentstart", "afteragentthought":
            return .working
        default:
            // Unknown Cursor events → working if process alive, never waitingPermission.
            return .working
        }
    }

    /// Idempotent merge of Bezel hook commands into Cursor `hooks.json`.
    public static func mergeBezelHooks(existing: Data?, hookCommand: String) throws -> Data {
        var root: [String: Any]
        if let existing, !existing.isEmpty,
           let obj = try JSONSerialization.jsonObject(with: existing) as? [String: Any]
        {
            root = obj
        } else {
            root = ["version": 1, "hooks": [String: Any]()]
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for name in managedEvents {
            var list = hooks[name] as? [[String: Any]] ?? []
            list = list.filter { entry in
                let cmd = entry["command"] as? String ?? ""
                return !isBezelCommand(cmd)
            }
            list.append(["command": hookCommand])
            hooks[name] = list
        }
        root["hooks"] = hooks
        if root["version"] == nil { root["version"] = 1 }
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .prettyPrinted])
    }

    /// Normalize a Cursor hook stdin payload into Bezel `HookPayload` (source stamped).
    public static func normalizeHookJSON(_ data: Data, eventOverride: String? = nil) throws -> HookPayload {
        guard var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookPayloadError.invalidJSON
        }
        obj["_source"] = source.rawValue
        if let eventOverride {
            obj["hook_event_name"] = mapCursorEvent(eventOverride)
        } else if let existing = obj["hook_event_name"] as? String {
            obj["hook_event_name"] = mapCursorEvent(existing)
        } else if let existing = obj["event"] as? String {
            obj["hook_event_name"] = mapCursorEvent(existing)
        }
        let enriched = try JSONSerialization.data(withJSONObject: obj)
        return try HookPayload.parse(enriched)
    }

    /// Map Cursor lifecycle events onto Claude-ish names Bezel already understands.
    /// Accepts camelCase, PascalCase, and snake_case variants from hooks / bridge.
    public static func mapCursorEvent(_ raw: String) -> String {
        let key = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "")
            .lowercased()
        switch key {
        case "beforesubmitprompt", "subagentstart":
            return "UserPromptSubmit"
        case "stop", "subagentstop":
            return "Stop"
        case "afteragentresponse", "afterfileedit", "aftershellexecution", "afteragentthought":
            return "PostToolUse"
        case "beforeshellexecution", "beforemcpexecution":
            return "PreToolUse"
        default:
            return EventNormalizer.pascalCase(raw)
        }
    }

    private static func isBezelCommand(_ command: String) -> Bool {
        command.contains(".bezel/bezel-hook.sh")
            || command.contains("BEZEL_SOURCE=cursor")
            || command.contains("bezel-bridge --source cursor")
    }
}
