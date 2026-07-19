import Testing
import BezelCore

@Suite("Permission routing")
struct PermissionRoutingTests {
    @Test func permissionRequestIsBlocking() {
        let kind = PermissionRouting.routeKind(
            hookEventName: "PermissionRequest",
            toolName: "Bash",
            source: "claude",
            question: nil
        )
        #expect(kind == .permission)
        #expect(PermissionRouting.isBlocking(kind))
    }

    @Test func askUserQuestionIsQuestion() {
        let kind = PermissionRouting.routeKind(
            hookEventName: "PreToolUse",
            toolName: "AskUserQuestion",
            source: "claude",
            question: nil
        )
        #expect(kind == .question)
    }

    @Test func exitPlanModeIsPermission() {
        let kind = PermissionRouting.routeKind(
            hookEventName: "PreToolUse",
            toolName: "ExitPlanMode",
            source: "claude",
            question: nil
        )
        #expect(kind == .permission)
    }

    @Test func genericPreToolUseIsEvent() {
        let kind = PermissionRouting.routeKind(
            hookEventName: "PreToolUse",
            toolName: "Bash",
            source: "claude",
            question: nil
        )
        #expect(kind == .event)
        #expect(!PermissionRouting.isBlocking(kind))
    }

    @Test func geminiPreToolUseIsEventInClaudeOnlyScope() {
        let kind = PermissionRouting.routeKind(
            hookEventName: "PreToolUse",
            toolName: "Bash",
            source: "gemini",
            question: nil
        )
        #expect(kind == .event)
    }

    @Test func sessionStartIsEvent() {
        let kind = PermissionRouting.routeKind(
            hookEventName: "session_start",
            toolName: nil,
            source: "claude",
            question: nil
        )
        #expect(kind == .event)
    }

    /// Notification+question must not block as AskUserQuestion (wrong response shape).
    @Test func notificationWithQuestionIsEvent() {
        let kind = PermissionRouting.routeKind(
            hookEventName: "Notification",
            toolName: nil,
            source: "claude",
            question: "Claude needs your attention"
        )
        #expect(kind == .event)
        #expect(!PermissionRouting.isBlocking(kind))
    }
}

@Suite("Event normalizer")
struct EventNormalizerTests {
    @Test func normalizesSnakeAndCamel() {
        #expect(EventNormalizer.pascalCase("pre_tool_use") == "PreToolUse")
        #expect(EventNormalizer.pascalCase("preToolUse") == "PreToolUse")
        #expect(EventNormalizer.pascalCase("PermissionRequest") == "PermissionRequest")
        #expect(EventNormalizer.pascalCase("sessionStart") == "SessionStart")
    }
}

@Suite("Hook payload")
struct HookPayloadTests {
    @Test func parsesClaudeShape() throws {
        let json = #"""
        {"hook_event_name":"PermissionRequest","session_id":"s1","tool_name":"Bash","cwd":"/tmp","_source":"claude"}
        """#.data(using: .utf8)!
        let payload = try HookPayload.parse(json)
        #expect(payload.hookEventName == "PermissionRequest")
        #expect(payload.sessionID == "s1")
        #expect(payload.toolName == "Bash")
        #expect(payload.routeKind == .permission)
    }
}
