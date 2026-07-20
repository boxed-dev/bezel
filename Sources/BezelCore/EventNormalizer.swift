import Foundation

public enum EventNormalizer {
    private static let known: [String: String] = [
        "sessionstart": "SessionStart",
        "session_start": "SessionStart",
        "sessionend": "SessionEnd",
        "session_end": "SessionEnd",
        "userpromptsubmit": "UserPromptSubmit",
        "user_prompt_submit": "UserPromptSubmit",
        "pretooluse": "PreToolUse",
        "pre_tool_use": "PreToolUse",
        "beforetool": "PreToolUse",
        "posttooluse": "PostToolUse",
        "post_tool_use": "PostToolUse",
        "permissionrequest": "PermissionRequest",
        "permission_request": "PermissionRequest",
        "notification": "Notification",
        "stop": "Stop",
        // Cursor agent hooks → Claude-shaped lifecycle events.
        "beforeshellexecution": "PreToolUse",
        "before_shell_execution": "PreToolUse",
        "aftershellexecution": "PostToolUse",
        "after_shell_execution": "PostToolUse",
        "beforemcpexecution": "PreToolUse",
        "before_mcp_execution": "PreToolUse",
        "aftermcpexecution": "PostToolUse",
        "after_mcp_execution": "PostToolUse",
        "afterfileedit": "PostToolUse",
        "after_file_edit": "PostToolUse",
        "beforereadfile": "PreToolUse",
        "before_read_file": "PreToolUse",
        "beforesubmitprompt": "UserPromptSubmit",
        "before_submit_prompt": "UserPromptSubmit",
        "afteragentresponse": "Stop",
        "after_agent_response": "Stop",
        "subagentstart": "SessionStart",
        "subagent_start": "SessionStart",
        "subagentstop": "Stop",
        "subagent_stop": "Stop",
    ]

    /// Normalize vendor event names to Claude-style PascalCase.
    public static func pascalCase(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown" }

        let key = trimmed
            .replacingOccurrences(of: "-", with: "_")
            .lowercased()

        if let hit = known[key] { return hit }
        if let hit = known[key.replacingOccurrences(of: "_", with: "")] { return hit }

        // Already correct PascalCase from Claude
        if trimmed == "SessionStart" || trimmed == "SessionEnd"
            || trimmed == "PreToolUse" || trimmed == "PostToolUse"
            || trimmed == "PermissionRequest" || trimmed == "UserPromptSubmit"
            || trimmed == "Notification" || trimmed == "Stop"
        {
            return trimmed
        }

        // Generic camel → Pascal
        if let first = trimmed.first {
            return String(first).uppercased() + trimmed.dropFirst()
        }
        return trimmed
    }
}
