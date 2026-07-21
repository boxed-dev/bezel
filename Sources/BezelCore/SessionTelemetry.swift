import Foundation

public struct SessionTodo: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var label: String
    public var done: Bool

    public init(id: String = UUID().uuidString, label: String, done: Bool = false) {
        self.id = id
        self.label = label
        self.done = done
    }
}

/// Optional fields parsed from hook JSON — degrade gracefully when absent.
public struct HookTelemetry: Sendable, Equatable {
    public var model: String?
    public var gitBranch: String?
    public var tokensIn: Int?
    public var tokensOut: Int?
    public var costUSD: Double?
    public var diffAdded: Int?
    public var diffRemoved: Int?
    public var lastReply: String?
    public var todos: [SessionTodo]?

    public init(
        model: String? = nil,
        gitBranch: String? = nil,
        tokensIn: Int? = nil,
        tokensOut: Int? = nil,
        costUSD: Double? = nil,
        diffAdded: Int? = nil,
        diffRemoved: Int? = nil,
        lastReply: String? = nil,
        todos: [SessionTodo]? = nil
    ) {
        self.model = model
        self.gitBranch = gitBranch
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
        self.costUSD = costUSD
        self.diffAdded = diffAdded
        self.diffRemoved = diffRemoved
        self.lastReply = lastReply
        self.todos = todos
    }
}

public enum SessionTelemetry {
    public static func parse(from obj: [String: Any]) -> HookTelemetry {
        HookTelemetry(
            model: string(in: obj, keys: ["model", "model_name", "modelName"]),
            gitBranch: string(in: obj, keys: ["git_branch", "gitBranch", "branch"]),
            tokensIn: int(in: obj, keys: ["tokens_in", "tokensIn", "input_tokens", "inputTokens"]),
            tokensOut: int(in: obj, keys: ["tokens_out", "tokensOut", "output_tokens", "outputTokens"]),
            costUSD: double(in: obj, keys: ["cost_usd", "costUSD", "cost", "usd"]),
            diffAdded: int(in: obj, keys: ["diff_added", "diffAdded", "lines_added", "linesAdded"]),
            diffRemoved: int(in: obj, keys: ["diff_removed", "diffRemoved", "lines_removed", "linesRemoved"]),
            lastReply: clippedReply(from: obj),
            todos: todos(from: obj)
        )
    }

    public static func merge(into session: Session, telemetry: HookTelemetry, event: HookEventName) -> Session {
        var next = session
        if let model = clean(telemetry.model) { next.model = model }
        if let branch = clean(telemetry.gitBranch) { next.gitBranch = branch }
        if let v = telemetry.tokensIn { next.tokensIn = max(next.tokensIn ?? 0, v) }
        if let v = telemetry.tokensOut { next.tokensOut = max(next.tokensOut ?? 0, v) }
        if let v = telemetry.costUSD { next.costUSD = max(next.costUSD ?? 0, v) }
        if let a = telemetry.diffAdded { next.diffAdded = (next.diffAdded ?? 0) + a }
        if let r = telemetry.diffRemoved { next.diffRemoved = (next.diffRemoved ?? 0) + r }
        if let reply = clean(telemetry.lastReply) { next.lastReply = clip(reply, 2000) }
        if let todos = telemetry.todos, !todos.isEmpty { next.todos = todos }

        switch event {
        case .userPromptSubmit:
            next.messageCount = (next.messageCount ?? 0) + 1
        case .postToolUse:
            if next.lastTool?.lowercased().contains("edit") == true
                || next.lastTool?.lowercased().contains("write") == true
            {
                next.fileEditCount = (next.fileEditCount ?? 0) + 1
            }
        default:
            break
        }
        return next
    }

    // MARK: - Private

    private static func string(in obj: [String: Any], keys: [String]) -> String? {
        for k in keys {
            if let s = obj[k] as? String, !s.isEmpty { return s }
        }
        return nil
    }

    private static func int(in obj: [String: Any], keys: [String]) -> Int? {
        for k in keys {
            if let n = obj[k] as? Int { return n }
            if let n = obj[k] as? Double { return Int(n) }
            if let s = obj[k] as? String, let n = Int(s.trimmingCharacters(in: .whitespaces)) { return n }
        }
        return nil
    }

    private static func double(in obj: [String: Any], keys: [String]) -> Double? {
        for k in keys {
            if let n = obj[k] as? Double { return n }
            if let n = obj[k] as? Int { return Double(n) }
            if let s = obj[k] as? String, let n = Double(s.trimmingCharacters(in: .whitespaces)) { return n }
        }
        return nil
    }

    private static func clippedReply(from obj: [String: Any]) -> String? {
        if let s = string(in: obj, keys: ["last_reply", "lastReply", "response", "assistant_response"]) {
            return s
        }
        if let s = string(in: obj, keys: ["text", "content"]) { return s }
        return nil
    }

    private static func todos(from obj: [String: Any]) -> [SessionTodo]? {
        let arrays: [[Any]]? = (obj["todos"] as? [[Any]])
            ?? (obj["todo_list"] as? [[Any]])
        guard let arrays, !arrays.isEmpty else { return nil }
        var out: [SessionTodo] = []
        for item in arrays {
            guard let dict = item as? [String: Any] else { continue }
            let label = (dict["content"] as? String)
                ?? (dict["label"] as? String)
                ?? (dict["text"] as? String)
            guard let label, !label.isEmpty else { continue }
            let done = (dict["done"] as? Bool) ?? (dict["completed"] as? Bool) ?? false
            out.append(SessionTodo(label: label, done: done))
        }
        return out.isEmpty ? nil : out
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func clip(_ value: String, _ max: Int) -> String {
        guard value.count > max else { return value }
        return String(value.prefix(max - 1)) + "…"
    }
}
