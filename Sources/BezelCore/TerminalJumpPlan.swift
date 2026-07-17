import Foundation

public enum TerminalJumpStrategy: String, Sendable, Equatable {
    case itermReveal
    case ghosttyFocus
    case terminalTTY
    case warpURL
    case kittyWindow
    case tmuxThenHost
    case activateOnly
    case unsupported
}

public enum TerminalJumpPlan {
    /// Primary strategy for a hint. tmux wins so the jumper can select-pane then host-jump.
    public static func plan(for hint: TerminalHint) -> TerminalJumpStrategy {
        if hint.tmux != nil || hint.tmuxPane != nil {
            return .tmuxThenHost
        }
        return hostPlan(for: hint)
    }

    /// Host terminal strategy with tmux fields ignored (used after pane select).
    public static func hostPlan(for hint: TerminalHint) -> TerminalJumpStrategy {
        let program = (hint.termProgram ?? "").lowercased()
        let bundle = (hint.bundleID ?? "").lowercased()

        if program.contains("iterm") || bundle.contains("iterm") || hint.itermSession != nil {
            // Real reveal when session id present; activateOnly only when hint is missing.
            return hint.itermSession != nil ? .itermReveal : .activateOnly
        }
        if program.contains("ghostty") || bundle.contains("ghostty") {
            // Always Ghostty focus path (AppleScript tty/cwd); never degrade to activateOnly.
            return .ghosttyFocus
        }
        if program.contains("apple_terminal") || program == "terminal" || bundle == "com.apple.terminal" {
            return hint.tty != nil ? .terminalTTY : .activateOnly
        }
        if program.contains("warp") || hint.warpFocusURL != nil {
            // Warp: deep link when available; otherwise activateOnly degrade.
            return hint.warpFocusURL != nil ? .warpURL : .activateOnly
        }
        if program.contains("wezterm") || bundle.contains("wezterm") {
            // No pane id in TerminalHint yet — activate only.
            return .activateOnly
        }
        if program.contains("kitty") || hint.kittyWindow != nil {
            return hint.kittyWindow != nil ? .kittyWindow : .activateOnly
        }
        // Cursor / unknown hosts: activate-only degrade when we at least know a bundle/program.
        if program.contains("cursor") || bundle.contains("cursor")
            || !program.isEmpty || !(hint.bundleID ?? "").isEmpty
        {
            return .activateOnly
        }
        return .unsupported
    }
}
