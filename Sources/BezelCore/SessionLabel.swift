import Foundation

/// Pure session row label: `Provider · project · phase`.
public enum SessionLabel {
    public static func format(session: Session) -> String {
        let provider = session.source.displayName
        let project = projectName(for: session)
        let phase = shortPhase(session.phase)
        return "\(provider) · \(project) · \(phase)"
    }

    /// Short human token for notch rows.
    public static func shortPhase(_ phase: SessionPhase) -> String {
        switch phase {
        case .waitingPermission, .waitingQuestion, .planReview:
            return "waiting"
        case .idle:
            return "idle"
        case .working:
            return "working"
        case .done:
            return "done"
        case .error:
            return "error"
        }
    }

    /// Prefer cleaned title, then cwd basename, then a quiet fallback.
    public static func projectName(for session: Session) -> String {
        if let title = DisplayNames.sessionTitle(
            sessionTitle: session.title,
            cwd: session.cwd,
            agentType: nil,
            existing: nil
        ), !DisplayNames.looksLikeSessionID(title) {
            return title
        }
        if let cwd = session.cwd, !cwd.isEmpty {
            let base = (cwd as NSString).lastPathComponent
            if !base.isEmpty, base != "/", base != "~" { return base }
        }
        return "session"
    }
}

extension AgentSource {
    /// Human provider name for labels (not raw enum).
    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .gemini: return "Gemini"
        case .opencode: return "OpenCode"
        case .unknown: return "Agent"
        }
    }
}
