import Foundation

public enum AgentSource: String, Codable, Sendable, CaseIterable, Hashable {
    case claude
    case codex
    case cursor
    case gemini
    case opencode
    case unknown

    /// Resolve vendor source from explicit `_source` / `source`, else infer from Cursor-shaped events.
    ///
    /// Cursor-only hook names always win — a shared Claude hook script may stamp
    /// `--source claude`, but `beforeShellExecution` is never emitted by Claude Code.
    /// Claude Code inside Cursor's terminal still uses `PreToolUse` + `_source=claude`.
    public static func resolve(raw: String?, hookEventName: String?) -> AgentSource? {
        if let hookEventName, isCursorHookEvent(hookEventName) {
            return .cursor
        }
        if let raw {
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let parsed = AgentSource(rawValue: key) { return parsed }
        }
        return nil
    }

    /// True for vendor event names that only Cursor emits (pre-normalization).
    public static func isCursorHookEvent(_ hookEventName: String) -> Bool {
        let rawKey = hookEventName
            .replacingOccurrences(of: "-", with: "_")
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
        let cursorHints = [
            "beforeshellexecution", "aftershellexecution",
            "beforemcpexecution", "aftermcpexecution",
            "afterfileedit", "beforereadfile", "beforesubmitprompt",
            "afteragentresponse", "afteragentthought",
            "subagentstart", "subagentstop",
        ]
        return cursorHints.contains(rawKey)
    }
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

    /// Prefer non-empty fields from `other`, keep ours when the new hook omitted them.
    public func merging(_ other: TerminalHint) -> TerminalHint {
        func pick(_ a: String?, _ b: String?) -> String? {
            if let b, !b.isEmpty { return b }
            if let a, !a.isEmpty { return a }
            return nil
        }
        return TerminalHint(
            termProgram: pick(termProgram, other.termProgram),
            bundleID: pick(bundleID, other.bundleID),
            itermSession: pick(itermSession, other.itermSession),
            tty: pick(tty, other.tty),
            tmux: pick(tmux, other.tmux),
            tmuxPane: pick(tmuxPane, other.tmuxPane),
            kittyWindow: pick(kittyWindow, other.kittyWindow),
            warpFocusURL: pick(warpFocusURL, other.warpFocusURL)
        )
    }

    public var hasJumpTarget: Bool {
        (itermSession?.isEmpty == false)
            || (tty?.isEmpty == false)
            || (warpFocusURL?.isEmpty == false)
            || (kittyWindow?.isEmpty == false)
            || (tmuxPane?.isEmpty == false)
            || (termProgram?.isEmpty == false)
            || (bundleID?.isEmpty == false)
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
    /// Subagent / named agent (`agent_type`), humanized for UI separately.
    public var agentType: String?
    public var lastTool: String?
    /// Command / path / description from the latest tool_input.
    public var lastToolDetail: String?
    public var terminal: TerminalHint?
    public var updatedAt: Date

    public init(
        id: SessionID,
        source: AgentSource = .claude,
        phase: SessionPhase = .idle,
        cwd: String? = nil,
        title: String? = nil,
        agentType: String? = nil,
        lastTool: String? = nil,
        lastToolDetail: String? = nil,
        terminal: TerminalHint? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.phase = phase
        self.cwd = cwd
        self.title = title
        self.agentType = agentType
        self.lastTool = lastTool
        self.lastToolDetail = lastToolDetail
        self.terminal = terminal
        self.updatedAt = updatedAt
    }
}
