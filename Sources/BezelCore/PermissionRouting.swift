import Foundation

/// Shared permission/question routing — MUST stay identical in bridge + HookServer.
public enum PermissionRouting {
    public static func routeKind(
        hookEventName: String,
        toolName: String?,
        source: String?,
        question: String?
    ) -> RouteKind {
        let event = HookEventName(raw: hookEventName)
        let src = (source ?? "claude").lowercased()

        if event == .permissionRequest {
            return .permission
        }

        // Gemini family uses PreToolUse as the permission gate.
        if event == .preToolUse, isGeminiFamily(src) {
            return .permission
        }

        if event == .preToolUse {
            let tool = toolName ?? ""
            if tool == "AskUserQuestion" || tool == "ExitPlanMode" {
                return tool == "AskUserQuestion" ? .question : .permission
            }
        }

        if (event == .notification), let q = question, !q.isEmpty {
            return .question
        }

        return .event
    }

    public static func isBlocking(_ kind: RouteKind) -> Bool {
        kind != .event
    }

    public static func isGeminiFamily(_ source: String) -> Bool {
        source == "gemini" || source == "google-antigravity" || source == "antigravity"
    }
}
