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
    /// Canonical id when the agent omits session_id (never invent a UUID).
    public static let unknown = SessionID("unknown")
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
