import Testing
import Foundation
import BezelCore

@Suite("QuestionParser")
struct QuestionParserTests {
    @Test func parsesToolInputQuestions() throws {
        let json = #"""
        {"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Target?","header":"T","options":[{"label":"Prod","description":"p"}],"multiSelect":false}]}}
        """#.data(using: .utf8)!
        let ti = QuestionParser.toolInput(from: json)
        let items = QuestionParser.parse(fromToolInput: ti)
        #expect(items.count == 1)
        #expect(items[0].question == "Target?")
        #expect(items[0].options.first?.label == "Prod")
    }
}
