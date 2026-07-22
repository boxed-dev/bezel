import Foundation

/// Shared bridge/server enrichment: stamp `_source` and normalize vendor event names
/// before `HookPayload.parse`. Keeps Cursor/Codex mapping out of BezelBridge-only code.
public enum HookEventEnrichment {
    /// Mutates `obj` in place. Safe for Claude (default), Codex, Cursor, OpenCode.
    public static func applySourceAndEvent(
        to obj: inout [String: Any],
        sourceOverride: String? = nil,
        eventOverride: String? = nil
    ) {
        // Capture vendor event name before normalization (Cursor inference needs it).
        let rawEvent = eventOverride
            ?? string(in: obj, keys: ["hook_event_name", "hookEventName", "eventName", "event"])

        let explicitSource = sourceOverride ?? (obj["_source"] as? String)
        // Cursor-shaped vendor events win over `--source claude` from a shared hook script.
        if let resolved = AgentSource.resolve(raw: explicitSource, hookEventName: rawEvent),
           resolved != .unknown
        {
            obj["_source"] = resolved.rawValue
        } else if obj["_source"] == nil {
            obj["_source"] = explicitSource ?? "claude"
        }

        let sourceRaw = (obj["_source"] as? String) ?? "claude"
        let source = AgentSource(rawValue: sourceRaw) ?? .unknown

        if let rawEvent {
            switch source {
            case .cursor:
                obj["hook_event_name"] = CursorAdapter.mapCursorEvent(rawEvent)
            case .codex:
                obj["hook_event_name"] = EventNormalizer.pascalCase(rawEvent)
            default:
                obj["hook_event_name"] = EventNormalizer.pascalCase(rawEvent)
            }
        }

        // Promote Cursor snake_case conversation id so session keys stay stable.
        if string(in: obj, keys: ["session_id", "sessionId"]) == nil,
           let cid = string(in: obj, keys: ["conversation_id", "conversationId"])
        {
            obj["session_id"] = cid
        }

        // Cursor often sends workspace_roots instead of cwd.
        if string(in: obj, keys: ["cwd"]) == nil,
           let roots = (obj["workspace_roots"] as? [String])
            ?? (obj["workspaceRoots"] as? [String])
            ?? (obj["workspace_roots"] as? [Any])?.compactMap({ $0 as? String }),
           let first = roots.first(where: { !$0.isEmpty })
        {
            obj["cwd"] = first
        }
    }

    private static func string(in obj: [String: Any], keys: [String]) -> String? {
        for k in keys {
            if let s = obj[k] as? String, !s.isEmpty { return s }
        }
        return nil
    }
}
