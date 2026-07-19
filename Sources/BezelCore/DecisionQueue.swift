import Foundation

/// What the notch must surface for a queued blocking decision.
public enum AttentionKind: String, Sendable, Equatable, CaseIterable {
    case planReview
    case permission
    case question
}

/// Stable identity for one blocking hook wait. Keyed by session + request id.
public struct DecisionKey: Hashable, Sendable, Codable, Equatable {
    public let sessionID: SessionID
    public let requestID: String

    public init(sessionID: SessionID, requestID: String) {
        self.sessionID = sessionID
        self.requestID = requestID
    }
}

/// Pure descriptor for a queued decision (no resume closures — those stay in the app layer).
public struct DecisionEntry: Identifiable, Sendable, Equatable {
    public var id: DecisionKey { key }
    public let key: DecisionKey
    public let kind: AttentionKind
    public let enqueuedAt: Date
    public let toolName: String?
    public let summary: String
    /// Original hook event name (`PermissionRequest` vs `PreToolUse`) for response shape.
    public let hookEventName: String
    public let planText: String?
    public let planFilePath: String?
    public let questions: [QuestionItem]
    /// Canonical `tool_input.questions` JSON for AskUserQuestionEncoder (preserves fixture shape).
    public let rawQuestionsJSON: Data?
    public let prompt: String?
    /// Claude `permission_suggestions` JSON array — echo as `updatedPermissions` for Always allow.
    public let permissionSuggestionsJSON: Data?
    /// Requested command/description for opt-in memory fallback matching.
    public let requestedRuleContent: String?

    public init(
        key: DecisionKey,
        kind: AttentionKind,
        enqueuedAt: Date = Date(),
        toolName: String? = nil,
        summary: String,
        hookEventName: String,
        planText: String? = nil,
        planFilePath: String? = nil,
        questions: [QuestionItem] = [],
        rawQuestionsJSON: Data? = nil,
        prompt: String? = nil,
        permissionSuggestionsJSON: Data? = nil,
        requestedRuleContent: String? = nil
    ) {
        self.key = key
        self.kind = kind
        self.enqueuedAt = enqueuedAt
        self.toolName = toolName
        self.summary = summary
        self.hookEventName = hookEventName
        self.planText = planText
        self.planFilePath = planFilePath
        self.questions = questions
        self.rawQuestionsJSON = rawQuestionsJSON
        self.prompt = prompt
        self.permissionSuggestionsJSON = permissionSuggestionsJSON
        self.requestedRuleContent = requestedRuleContent
    }
}

/// Pure FIFO+priority queue. Concurrent sessions never clobber each other.
public struct DecisionQueue: Sendable, Equatable {
    public private(set) var entries: [DecisionEntry]

    public init(entries: [DecisionEntry] = []) {
        self.entries = entries
    }

    public var isEmpty: Bool { entries.isEmpty }

    public var head: DecisionEntry? {
        Self.selectHead(from: entries)
    }

    /// Insert or replace by key. Returns the displaced entry when replacing.
    @discardableResult
    public mutating func enqueue(_ entry: DecisionEntry) -> DecisionEntry? {
        let displaced: DecisionEntry?
        if let idx = entries.firstIndex(where: { $0.key == entry.key }) {
            displaced = entries.remove(at: idx)
        } else {
            displaced = nil
        }
        entries.append(entry)
        return displaced
    }

    @discardableResult
    public mutating func remove(_ key: DecisionKey) -> DecisionEntry? {
        guard let idx = entries.firstIndex(where: { $0.key == key }) else { return nil }
        return entries.remove(at: idx)
    }

    public func entries(for sessionID: SessionID) -> [DecisionEntry] {
        entries.filter { $0.key.sessionID == sessionID }
    }

    /// Highest priority first; within the same kind, oldest enqueued wins.
    public static func selectHead(from entries: [DecisionEntry]) -> DecisionEntry? {
        entries.min { a, b in
            let pa = priority(a.kind)
            let pb = priority(b.kind)
            if pa != pb { return pa < pb }
            if a.enqueuedAt != b.enqueuedAt { return a.enqueuedAt < b.enqueuedAt }
            return a.key.requestID < b.key.requestID
        }
    }

    /// Lower number = higher priority (matches `NotchSurfaceMapper` order).
    public static func priority(_ kind: AttentionKind) -> Int {
        switch kind {
        case .planReview: return 0
        case .permission: return 1
        case .question: return 2
        }
    }

    public static func phase(for kind: AttentionKind) -> SessionPhase {
        switch kind {
        case .planReview: return .planReview
        case .permission: return .waitingPermission
        case .question: return .waitingQuestion
        }
    }

    public static func attentionKind(
        routeKind: RouteKind,
        toolName: String?,
        hookEventName _: String
    ) -> AttentionKind? {
        let tool = toolName ?? ""
        if tool == "ExitPlanMode" { return .planReview }
        switch routeKind {
        case .permission: return .permission
        case .question: return .question
        case .event: return nil
        }
    }
}

/// Build stable decision keys from hook JSON.
public enum DecisionKeyFactory {
    public static func make(sessionID: SessionID, rawJSON: Data, fallback: @autoclosure () -> String = UUID().uuidString) -> DecisionKey {
        DecisionKey(sessionID: sessionID, requestID: extractRequestID(from: rawJSON) ?? fallback())
    }

    public static func extractRequestID(from rawJSON: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: rawJSON) as? [String: Any] else {
            return nil
        }
        // Prefer tool_use_id everywhere it may appear (top-level or nested).
        let toolUseKeys = ["tool_use_id", "toolUseId"]
        if let id = firstString(in: obj, keys: toolUseKeys) { return id }
        for nestKey in ["tool", "tool_input", "toolInput", "toolCall"] {
            if let nest = obj[nestKey] as? [String: Any],
               let id = firstString(in: nest, keys: toolUseKeys) {
                return id
            }
        }
        let fallbackKeys = ["request_id", "requestId", "id"]
        if let id = firstString(in: obj, keys: fallbackKeys) { return id }
        if let tool = obj["tool"] as? [String: Any],
           let id = firstString(in: tool, keys: ["id"]) {
            return id
        }
        return nil
    }

    private static func firstString(in obj: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let s = obj[key] as? String, !s.isEmpty { return s }
        }
        return nil
    }
}
