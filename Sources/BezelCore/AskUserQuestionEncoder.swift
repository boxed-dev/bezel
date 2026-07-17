import Foundation

public struct AskUserQuestionAnswer: Sendable, Equatable {
    /// Exact question text (must match tool_input.questions[].question).
    public var question: String
    /// Option label, or comma-joined labels for multi-select.
    public var answer: String

    public init(question: String, answer: String) {
        self.question = question
        self.answer = answer
    }
}

public enum AskUserQuestionEncoder {
    public enum EncodeError: Error, Equatable {
        case missingQuestions
        case emptyAnswers
    }

    /// Build Claude PreToolUse allow + updatedInput for AskUserQuestion.
    public static func encode(
        questions: [[String: Any]],
        answers: [AskUserQuestionAnswer]
    ) throws -> Data {
        guard !questions.isEmpty else { throw EncodeError.missingQuestions }
        guard !answers.isEmpty else { throw EncodeError.emptyAnswers }

        var answerMap: [String: String] = [:]
        for a in answers {
            answerMap[a.question] = a.answer
        }

        let updatedInput: [String: Any] = [
            "questions": questions,
            "answers": answerMap,
        ]

        let root: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "permissionDecisionReason": "Answered from Bezel",
                "updatedInput": updatedInput,
            ] as [String: Any],
        ]

        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    /// Parse questions array from a PreToolUse tool_input object.
    public static func questions(fromToolInput toolInput: [String: Any]?) -> [[String: Any]] {
        toolInput?["questions"] as? [[String: Any]] ?? []
    }
}
