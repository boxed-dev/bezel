import Foundation

/// Parsed ExitPlanMode `tool_input` fields.
public struct PlanContent: Sendable, Equatable {
    public let plan: String
    public let planFilePath: String?

    public init(plan: String, planFilePath: String? = nil) {
        self.plan = plan
        self.planFilePath = planFilePath
    }

    public var displayBody: String {
        if !plan.isEmpty { return plan }
        if let planFilePath, !planFilePath.isEmpty {
            return "(Plan file)\n\(planFilePath)"
        }
        return "(No plan content in tool_input)"
    }
}

public enum PlanInputParser {
    public static func parse(fromToolInput toolInput: [String: Any]?) -> PlanContent {
        guard let toolInput else {
            return PlanContent(plan: "", planFilePath: nil)
        }
        let plan = (toolInput["plan"] as? String)
            ?? (toolInput["content"] as? String)
            ?? ""
        let path = (toolInput["planFilePath"] as? String)
            ?? (toolInput["plan_file_path"] as? String)
            ?? (toolInput["filePath"] as? String)
        return PlanContent(plan: plan, planFilePath: path)
    }

    public static func parse(from rawJSON: Data) -> PlanContent {
        parse(fromToolInput: QuestionParser.toolInput(from: rawJSON))
    }
}
