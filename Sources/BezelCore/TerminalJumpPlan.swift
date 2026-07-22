import Foundation

public enum TerminalJumpStrategy: String, Sendable, Equatable {
    case itermReveal
    case ghosttyFocus
    case terminalTTY
    case warpURL
    case kittyWindow
    case tmuxThenHost
    /// Unknown host but we have a tty — probe Ghostty / Terminal / iTerm by tty.
    case ttyHunt
    /// Cursor / VS Code: reopen workspace via CLI (`cursor -r` / `code -r`).
    /// Honest best-effort — cannot target an IDE chat tab, only the workspace window.
    case ideWorkspace
    case activateOnly
    case unsupported
}

public enum TerminalJumpPlan {
    /// Primary strategy for a hint. tmux wins so the jumper can select-pane then host-jump.
    public static func plan(for hint: TerminalHint, cwd: String? = nil) -> TerminalJumpStrategy {
        if hint.tmux != nil || hint.tmuxPane != nil {
            return .tmuxThenHost
        }
        return hostPlan(for: hint, cwd: cwd)
    }

    /// Host terminal strategy with tmux fields ignored (used after pane select).
    public static func hostPlan(for hint: TerminalHint, cwd: String? = nil) -> TerminalJumpStrategy {
        let program = (hint.termProgram ?? "").lowercased()
        let bundle = (hint.bundleID ?? "").lowercased()

        if program.contains("iterm") || bundle.contains("iterm") || hint.itermSession != nil {
            if hint.itermSession != nil || hint.tty != nil {
                return .itermReveal
            }
            return .activateOnly
        }
        if program.contains("ghostty") || bundle.contains("ghostty") {
            // Always attempt Ghostty AppleScript. Precise path needs tty (or unique pid);
            // cwd fallback is gated by TerminalJumpMatch.allowCwdFallback in the jumper.
            return .ghosttyFocus
        }
        if program.contains("apple_terminal") || program == "terminal" || bundle == "com.apple.terminal" {
            // TERM_SESSION_ID is captured for diagnostics; AppleScript selects by tty.
            return hint.tty != nil ? .terminalTTY : .activateOnly
        }
        if program.contains("warp") || hint.warpFocusURL != nil {
            return hint.warpFocusURL != nil ? .warpURL : .activateOnly
        }
        if program.contains("wezterm") || bundle.contains("wezterm") {
            // WezTerm pane CLI not wired yet — activate-only (honest).
            return .activateOnly
        }
        if program.contains("kitty") || hint.kittyWindow != nil {
            return hint.kittyWindow != nil ? .kittyWindow : .activateOnly
        }
        // Cursor / VS Code: workspace reopen when cwd known; never invent chat-tab precision.
        if program.contains("cursor") || bundle.contains("cursor")
            || program.contains("vscode") || bundle.contains("visualstudiocode")
        {
            if let cwd, !cwd.isEmpty {
                return .ideWorkspace
            }
            return .activateOnly
        }
        // Have a tty but unknown host — hunt across common terminals.
        if let tty = hint.tty, !tty.isEmpty {
            return .ttyHunt
        }
        if !program.isEmpty || !(hint.bundleID ?? "").isEmpty {
            return .activateOnly
        }
        return .unsupported
    }
}
