import Foundation

/// Pure breakdown of a blocking hook payload into attention work for the store.
public struct DecisionAttention: Sendable, Equatable {
    public let kind: AttentionKind
    public let plan: PlanContent?
    public let questions: [QuestionItem]
    public let rawQuestionsJSON: Data?
    public let prompt: String?
    public let toolName: String?
    public let summary: String
    public let hookEventName: String
    public let permissionSuggestionsJSON: Data?
    public let requestedRuleContent: String?

    public init(
        kind: AttentionKind,
        plan: PlanContent? = nil,
        questions: [QuestionItem] = [],
        rawQuestionsJSON: Data? = nil,
        prompt: String? = nil,
        toolName: String?,
        summary: String,
        hookEventName: String,
        permissionSuggestionsJSON: Data? = nil,
        requestedRuleContent: String? = nil
    ) {
        self.kind = kind
        self.plan = plan
        self.questions = questions
        self.rawQuestionsJSON = rawQuestionsJSON
        self.prompt = prompt
        self.toolName = toolName
        self.summary = summary
        self.hookEventName = hookEventName
        self.permissionSuggestionsJSON = permissionSuggestionsJSON
        self.requestedRuleContent = requestedRuleContent
    }
}

public enum DecisionIngress {
    /// Returns attention work for blocking routes; `nil` for fire-and-forget events.
    public static func attention(for payload: HookPayload) -> DecisionAttention? {
        // Notification is never AskUserQuestion PreToolUse — do not synthesize a blocking question.
        if HookEventName(raw: payload.hookEventName) == .notification {
            return nil
        }

        let kind = DecisionQueue.attentionKind(
            routeKind: payload.routeKind,
            toolName: payload.toolName,
            hookEventName: payload.hookEventName
        )
        guard let kind else { return nil }

        switch kind {
        case .planReview:
            let plan = PlanInputParser.parse(from: payload.rawJSON)
            return DecisionAttention(
                kind: .planReview,
                plan: plan,
                toolName: "ExitPlanMode",
                summary: "Review plan",
                hookEventName: payload.hookEventName
            )
        case .permission:
            let suggestions = PermissionSuggestions.json(from: payload.rawJSON)
            return DecisionAttention(
                kind: .permission,
                toolName: payload.toolName,
                summary: permissionSummary(for: payload),
                hookEventName: payload.hookEventName,
                permissionSuggestionsJSON: suggestions,
                requestedRuleContent: PermissionSuggestions.requestedRuleContent(from: payload.rawJSON)
            )
        case .question:
            let toolInput = QuestionParser.toolInput(from: payload.rawJSON)
            let rawQuestions = AskUserQuestionEncoder.questions(fromToolInput: toolInput)
            var questions = QuestionParser.parse(fromToolInput: toolInput)
            if questions.isEmpty {
                let prompt = payload.question ?? "Agent question"
                questions = [QuestionItem(question: prompt, options: [])]
            }
            let prompt = questions.first?.question ?? payload.question ?? "Agent question"
            let rawJSON = try? JSONSerialization.data(withJSONObject: rawQuestions, options: [.sortedKeys])
            return DecisionAttention(
                kind: .question,
                questions: questions,
                rawQuestionsJSON: rawJSON,
                prompt: prompt,
                toolName: "AskUserQuestion",
                summary: prompt,
                hookEventName: payload.hookEventName
            )
        }
    }

    private static func permissionSummary(for payload: HookPayload) -> String {
        let tool = payload.toolName ?? "tool"
        if let obj = try? JSONSerialization.jsonObject(with: payload.rawJSON) as? [String: Any] {
            let input = (obj["tool_input"] as? [String: Any])
                ?? (obj["toolInput"] as? [String: Any])
            if let command = input?["command"] as? String, !command.isEmpty {
                let clipped = command.count > 80 ? String(command.prefix(77)) + "…" : command
                return "Allow \(tool)?\n\(clipped)"
            }
            if let desc = input?["description"] as? String, !desc.isEmpty {
                return "Allow \(tool)?\n\(desc)"
            }
        }
        return "Allow \(tool)?"
    }
}
