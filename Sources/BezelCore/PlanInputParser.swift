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

/// Loads plan body for the notch HUD — prefers inline text, then a capped file read.
public enum PlanBodyLoader {
    public static let defaultMaxBytes = 12_288 // 12KB

    public struct Loaded: Equatable, Sendable {
        public let text: String
        public let truncated: Bool
        public let fromFile: Bool

        public init(text: String, truncated: Bool, fromFile: Bool) {
            self.text = text
            self.truncated = truncated
            self.fromFile = fromFile
        }
    }

    /// Resolve display text for plan review. Caps file reads so the HUD never ingests megabytes.
    public static func load(
        planText: String?,
        planFilePath: String?,
        summary: String,
        maxBytes: Int = defaultMaxBytes,
        fileContents: ((String) -> Data?)? = nil
    ) -> Loaded {
        let inline = planText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !inline.isEmpty, inline != summary {
            let (text, truncated) = Self.cap(inline, maxBytes: maxBytes)
            return Loaded(text: text, truncated: truncated, fromFile: false)
        }
        if let path = planFilePath, !path.isEmpty {
            let data = fileContents?(path) ?? Data(readingCappedFileAt: path, maxBytes: maxBytes + 1)
            if let data, !data.isEmpty {
                let truncated = data.count > maxBytes
                let slice = truncated ? data.prefix(maxBytes) : data[...]
                let text = String(decoding: slice, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return Loaded(text: text, truncated: truncated, fromFile: true)
                }
            }
        }
        if !inline.isEmpty {
            let (text, truncated) = Self.cap(inline, maxBytes: maxBytes)
            return Loaded(text: text, truncated: truncated, fromFile: false)
        }
        let fallback = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let (text, truncated) = Self.cap(fallback.isEmpty ? "(No plan content)" : fallback, maxBytes: maxBytes)
        return Loaded(text: text, truncated: truncated, fromFile: false)
    }

    private static func cap(_ value: String, maxBytes: Int) -> (String, Bool) {
        let data = Data(value.utf8)
        guard data.count > maxBytes else { return (value, false) }
        let slice = data.prefix(maxBytes)
        let text = String(decoding: slice, as: UTF8.self)
        return (text, true)
    }
}

private extension Data {
    init?(readingCappedFileAt path: String, maxBytes: Int) {
        let url = URL(fileURLWithPath: path)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let chunk = try? handle.read(upToCount: maxBytes)
        guard let chunk, !chunk.isEmpty else { return nil }
        self = chunk
    }
}
