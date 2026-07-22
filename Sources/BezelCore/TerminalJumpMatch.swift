import Foundation

/// Unique surface identities, strongest → weakest.
///
/// Matching priority (mission): tty > iTerm session id > tmux pane >
/// TERM_SESSION_ID / kitty / warp > agent PID > activate-only.
/// Cwd is never a unique identity — only allowed as fallback when the host
/// reports exactly one match (`allowCwdFallback`).
public enum TerminalJumpIdentity: String, Sendable, Equatable, CaseIterable {
    case tty
    case itermSession
    case tmuxPane
    case termSessionID
    case kittyWindow
    case warpFocusURL
    case agentPID
}

public enum ITermSelectKey: String, Sendable, Equatable {
    case tty
    case itermSession
}

/// Pure matching policy for precise jump — no AppleScript / process I/O.
public enum TerminalJumpMatch {
    /// Strongest unique identity present on the hint, or nil if none.
    public static func strongestIdentity(for hint: TerminalHint) -> TerminalJumpIdentity? {
        identities(for: hint).first
    }

    /// All unique identities present, ordered strongest → weakest.
    public static func identities(for hint: TerminalHint) -> [TerminalJumpIdentity] {
        var out: [TerminalJumpIdentity] = []
        if let tty = hint.tty, !tty.isEmpty { out.append(.tty) }
        if let sid = hint.itermSession, !sid.isEmpty { out.append(.itermSession) }
        if let pane = hint.tmuxPane, !pane.isEmpty { out.append(.tmuxPane) }
        if let ts = hint.termSessionID, !ts.isEmpty { out.append(.termSessionID) }
        if let kid = hint.kittyWindow, !kid.isEmpty { out.append(.kittyWindow) }
        if let warp = hint.warpFocusURL, !warp.isEmpty { out.append(.warpFocusURL) }
        if let pid = hint.agentPID, pid > 0 { out.append(.agentPID) }
        return out
    }

    /// True when we have a unique surface key (not merely TERM_PROGRAM / cwd).
    public static func isPreciseSurfaceJump(_ hint: TerminalHint) -> Bool {
        guard let strongest = strongestIdentity(for: hint) else { return false }
        switch strongest {
        case .tty, .itermSession, .tmuxPane, .termSessionID, .kittyWindow, .warpFocusURL:
            return true
        case .agentPID:
            // PID helps Ghostty/disambiguation but alone is best-effort.
            return false
        }
    }

    /// Cwd fallback is only safe when the host reports exactly one match.
    /// Never pick arbitrarily among same-project sessions.
    public static func allowCwdFallback(matchCount: Int) -> Bool {
        matchCount == 1
    }

    /// iTerm select order: tty first (stable device), then session id.
    public static func itermSelectKeys(for hint: TerminalHint) -> [ITermSelectKey] {
        var keys: [ITermSelectKey] = []
        if let tty = hint.tty, !tty.isEmpty { keys.append(.tty) }
        if let sid = hint.itermSession, !sid.isEmpty { keys.append(.itermSession) }
        return keys
    }
}
