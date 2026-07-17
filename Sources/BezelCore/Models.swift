import Foundation

public enum AgentSource: String, Codable, Sendable, CaseIterable, Hashable {
    case claude
    case codex
    case cursor
    case gemini
    case opencode
    case unknown
}

public enum SessionPhase: String, Codable, Sendable, Hashable {
    case idle
    case working
    case waitingPermission
    case waitingQuestion
    case planReview
    case done
    case error
}

public enum HookEventName: String, Codable, Sendable, Hashable {
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case permissionRequest = "PermissionRequest"
    case notification = "Notification"
    case stop = "Stop"
    case unknown

    public init(raw: String) {
        let normalized = EventNormalizer.pascalCase(raw)
        self = HookEventName(rawValue: normalized) ?? .unknown
    }
}

/// How the server/bridge must treat an inbound event.
public enum RouteKind: String, Sendable, Hashable {
    /// Block until UI returns a decision JSON.
    case permission
    /// Block until UI returns a question answer.
    case question
    /// Fire-and-forget status update.
    case event
}

public struct TerminalHint: Codable, Sendable, Hashable {
    public var termProgram: String?
    public var bundleID: String?
    public var itermSession: String?
    public var tty: String?
    public var tmux: String?
    public var tmuxPane: String?
    public var kittyWindow: String?
    public var warpFocusURL: String?

    public init(
        termProgram: String? = nil,
        bundleID: String? = nil,
        itermSession: String? = nil,
        tty: String? = nil,
        tmux: String? = nil,
        tmuxPane: String? = nil,
        kittyWindow: String? = nil,
        warpFocusURL: String? = nil
    ) {
        self.termProgram = termProgram
        self.bundleID = bundleID
        self.itermSession = itermSession
        self.tty = tty
        self.tmux = tmux
        self.tmuxPane = tmuxPane
        self.kittyWindow = kittyWindow
        self.warpFocusURL = warpFocusURL
    }
}

public struct SessionID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { self.rawValue = value }
}

public struct Session: Identifiable, Codable, Sendable, Hashable {
    public var id: SessionID
    public var source: AgentSource
    public var phase: SessionPhase
    public var cwd: String?
    public var title: String?
    public var lastTool: String?
    public var terminal: TerminalHint?
    public var updatedAt: Date

    public init(
        id: SessionID,
        source: AgentSource = .claude,
        phase: SessionPhase = .idle,
        cwd: String? = nil,
        title: String? = nil,
        lastTool: String? = nil,
        terminal: TerminalHint? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.phase = phase
        self.cwd = cwd
        self.title = title
        self.lastTool = lastTool
        self.terminal = terminal
        self.updatedAt = updatedAt
    }
}

public struct IslandEnvelope: Codable, Sendable {
    public var hookEventName: String
    public var sessionID: String?
    public var toolName: String?
    public var cwd: String?
    public var source: String?
    public var question: String?
    public var raw: [String: AnyCodable]

    public enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionID = "session_id"
        case toolName = "tool_name"
        case cwd
        case source = "_source"
        case question
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hookEventName = try c.decodeIfPresent(String.self, forKey: .hookEventName)
            ?? (try? decoder.container(keyedBy: AltKeys.self).decode(String.self, forKey: .hookEventName))
            ?? "Unknown"
        sessionID = try c.decodeIfPresent(String.self, forKey: .sessionID)
        toolName = try c.decodeIfPresent(String.self, forKey: .toolName)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        question = try c.decodeIfPresent(String.self, forKey: .question)
        raw = [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(hookEventName, forKey: .hookEventName)
        try c.encodeIfPresent(sessionID, forKey: .sessionID)
        try c.encodeIfPresent(toolName, forKey: .toolName)
        try c.encodeIfPresent(cwd, forKey: .cwd)
        try c.encodeIfPresent(source, forKey: .source)
        try c.encodeIfPresent(question, forKey: .question)
    }

    private enum AltKeys: String, CodingKey {
        case hookEventName
    }
}

/// Minimal type-erased JSON value for passthrough.
public struct AnyCodable: Codable, Sendable, Hashable {
    public let value: String
    public init(_ value: String) { self.value = value }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int.self) { value = String(i) }
        else if let b = try? c.decode(Bool.self) { value = String(b) }
        else { value = "" }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}
