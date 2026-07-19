import Testing
import Foundation
import BezelCore

@Suite("AskUserQuestionEncoder")
struct AskUserQuestionEncoderTests {
    @Test func encodesAllowWithAnswers() throws {
        let questions: [[String: Any]] = [
            [
                "question": "Which deployment target?",
                "header": "Target",
                "options": [
                    ["label": "Production", "description": "Prod"],
                    ["label": "Staging", "description": "Stage"],
                ],
                "multiSelect": false,
            ],
        ]
        let data = try AskUserQuestionEncoder.encode(
            questions: questions,
            answers: [.init(question: "Which deployment target?", answer: "Production")]
        )
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hook = root?["hookSpecificOutput"] as? [String: Any]
        #expect(hook?["permissionDecision"] as? String == "allow")
        #expect(hook?["hookEventName"] as? String == "PreToolUse")
        let updated = hook?["updatedInput"] as? [String: Any]
        let answers = updated?["answers"] as? [String: String]
        #expect(answers?["Which deployment target?"] == "Production")
        #expect((updated?["questions"] as? [[String: Any]])?.count == 1)
    }

    @Test func matchesClaudeDocsFixture() throws {
        let questions: [[String: Any]] = [
            [
                "question": "Which deployment target?",
                "header": "Target",
                "options": [
                    ["label": "Production", "description": "Prod"],
                    ["label": "Staging", "description": "Stage"],
                ],
                "multiSelect": false,
            ],
        ]
        let data = try AskUserQuestionEncoder.encode(
            questions: questions,
            answers: [.init(question: "Which deployment target?", answer: "Production")]
        )
        let fixture = try loadFixture("ask-user-question-allow")
        #expect(JSONCanonical.equal(data, fixture))
    }

    @Test func rejectsMissingQuestions() {
        #expect(throws: AskUserQuestionEncoder.EncodeError.missingQuestions) {
            try AskUserQuestionEncoder.encode(questions: [], answers: [.init(question: "q", answer: "a")])
        }
    }

    @Test func rejectsIncompleteAnswers() {
        let questions: [[String: Any]] = [
            ["question": "A?", "options": [["label": "1"]]],
            ["question": "B?", "options": [["label": "2"]]],
        ]
        #expect(throws: AskUserQuestionEncoder.EncodeError.incompleteAnswers) {
            try AskUserQuestionEncoder.encode(
                questions: questions,
                answers: [.init(question: "A?", answer: "1")]
            )
        }
    }

    /// M3: resolve path must echo original tool_input.questions (extra keys survive).
    @Test func echoesOriginalQuestionsIncludingExtraKeys() throws {
        let original: [[String: Any]] = [
            [
                "question": "Target?",
                "header": "T",
                "options": [["label": "Prod", "description": "p"]],
                "multiSelect": false,
                "customField": "must-survive",
            ],
        ]
        let data = try AskUserQuestionEncoder.encode(
            questions: original,
            answers: [.init(question: "Target?", answer: "Prod")]
        )
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let updated = (root?["hookSpecificOutput"] as? [String: Any])?["updatedInput"] as? [String: Any]
        let echoed = updated?["questions"] as? [[String: Any]]
        #expect(echoed?.first?["customField"] as? String == "must-survive")
        #expect(echoed?.first?["question"] as? String == "Target?")
    }

    private func loadFixture(_ name: String) throws -> Data {
        if let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "decisions") {
            return try Data(contentsOf: url)
        }
        let path = FileManager.default.currentDirectoryPath + "/Tests/BezelCoreTests/Fixtures/decisions/\(name).json"
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }
}
