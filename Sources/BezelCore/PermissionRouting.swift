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

        if event == .permissionRequest {
            return .permission
        }

        // Claude-only Phase 1: PreToolUse blocks only for interactive tools.
        // Gemini-family PreToolUse-as-permission is deferred to multi-agent phase.
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

    /// Retained for Phase 3 adapters; unused in Claude-only routing.
    public static func isGeminiFamily(_ source: String) -> Bool {
        source == "gemini" || source == "google-antigravity" || source == "antigravity"
    }
}
